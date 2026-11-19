class_name Sim
extends RefCounted

## The authoritative simulation: owns every ship and advances them together,
## one fixed tick at a time, from one input per ship (MP-2).
##
## No nodes, devices, clock or unseeded randomness (ARC-1). Identical seed and
## inputs give an identical `state_hash()` (ARC-2), which is what replay tests
## and, later, network desync checks compare.

## Seed of this run. Nothing draws random numbers yet; it is part of the state
## so that replays recorded now stay valid once the generator and robots do.
var run_seed: int = 0
## Number of ticks simulated so far.
var tick: int = 0
var ships: Array[ShipState] = []
## Walls everything flies inside, or null for open space (GEN-5). Not part of
## the hash: it is fixed for the run, like the seed's mine will be. Set by the
## constructor from one box, or by `set_walls` for a multi-box level.
var walls: BoxUnion = null
## The first box of `walls`, or null: the single box older callers built the
## run with. Read-only; the simulation itself only uses `walls`.
var bounds: BoxBounds = null
## What happened on the last tick only, in ship order and, per ship, in the
## order of `SimEvent.Kind`. Derived output for haptics, shake and sound
## (PLT-6): not part of the hash, replaced by every call to `step`.
var last_events: Array[SimEvent] = []
## Where each ship returns on a `reset_to_start` input, read-only here; see
## `ShipReset`. Change them with `set_start_pose`.
var start_positions: Array[Vector3]:
	get:
		return _reset.positions
var start_orientations: Array[Basis]:
	get:
		return _reset.orientations
## Every live projectile, oldest first (CMB-1). Part of the hash.
var projectiles: Array[Projectile] = []
## Every robot, in spawn order (CMB-3). Part of the hash while there are any.
var robots: Array[RobotState] = []
## Parts dropped by destroyed robots, in drop order (SLV-1), until a ship
## takes one (`SalvagePickup`). Part of the hash while there are any. They do
## not expire in M2.
var salvage: Array[SalvageItem] = []
## The level's reactor (RUN-2), or null. Set before the first tick by
## `set_reactor`. Part of the hash only when there is one.
var reactor: ReactorState = null
## Debris that falls once the reactor dies (RUN-4), or null. Set before the
## first tick by `set_debris`. Part of the hash only when there is some.
var debris: MeltdownDebris = null
## The part catalogue: part id to the weapon that part is, each resolved by the
## caller since core opens no files (SLV-1, ARC-4). Set before the first tick
## by `set_parts` and read-only afterwards, through `part`. Part of the hash
## while non-empty.
var _parts: Dictionary[String, WeaponDef] = {}
## How parts are picked up, pulled and dropped; see `set_salvage_rules`. Not
## part of the hash: fixed for the run and recorded in the replay's header,
## like the walls; what they do to the parts shows in the parts' own state.
var salvage_rules: SalvageRules = SalvageRules.new()
## Projectile hit events of the tick being stepped. Hits are found when
## projectiles move, before the ships, but their events follow the ship events.
var _hit_events: Array[SimEvent] = []
## Robot index to the ship whose shot destroyed it, for the tick being stepped.
var _killers: Dictionary = {}
## True only while `step` runs, so a spawn cannot land part-way through a tick.
var _stepping: bool = false
var _reset: ShipReset = ShipReset.new()


func _init(p_run_seed: int = 0, ship_count: int = 1, p_bounds: BoxBounds = null) -> void:
	run_seed = p_run_seed
	if p_bounds != null:
		var one: Array[BoxBounds] = [p_bounds]
		set_walls(BoxUnion.new(one))
	for i: int in ship_count:
		ships.append(ShipState.new())
	_reset.record(ships)


## Advances every ship by one tick. `inputs[i]` drives `ships[i]`.
## Returns false and changes no state if there is not exactly one input per
## ship: guessing a missing input would silently fork the simulation. A refused
## step still empties `last_events`, because no tick happened.
func step(inputs: Array[ShipInput]) -> bool:
	last_events = []
	if inputs.size() != ships.size():
		return false
	_hit_events = []
	_killers = {}
	_stepping = true
	var live_before: Array[bool] = ExitRule.live_ships(self)
	if tick == 0:
		_reset.record(ships)
	if reactor != null:
		reactor.count_down()
	if debris != null:
		DebrisRouteGuard.advance(self, last_events)
	# Projectiles already in flight move before any new shot, so a shot
	# spawns where its ship is at the end of the tick it was fired on.
	ProjectileHits.advance(self, _hit_events, _killers)
	var from: Array[Vector3] = []
	var slot_drops: Array[SalvageItem] = []
	for i: int in ships.size():
		var ship: ShipState = ships[i]
		from.append(ship.position)
		if ship.escaped:
			continue
		# The rest of the input applies even when the meltdown refuses the reset.
		if inputs[i].reset_to_start and _reset.apply(ship, i, reactor):
			from[i] = ship.position
		var was_active: bool = ship.afterburner_active
		var was_locked: bool = ship.afterburner_locked
		ship.step(inputs[i].thrust(), inputs[i].turn(), inputs[i].afterburner)
		if ship.afterburner_active and not was_active:
			last_events.append(SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, i))
		elif was_active and not ship.afterburner_active:
			last_events.append(SimEvent.new(SimEvent.Kind.AFTERBURNER_STOPPED, i))
		if ship.afterburner_locked and not was_locked:
			last_events.append(SimEvent.new(SimEvent.Kind.ENERGY_DEPLETED, i))
		ShipContact.apply(self, i, last_events)
		if inputs[i].slot_held and not ship.slot_was_held:
			PartSlotting.slot_held(self, i, slot_drops)
		ship.slot_was_held = inputs[i].slot_held
		ProjectileHits.fire(self, i, inputs[i].fire_primary)
	last_events.append_array(_hit_events)
	SalvagePickup.collect(self, from)
	RobotTick.advance(self)
	SalvagePickup.drift(self, slot_drops)
	RobotTick.remove_destroyed(self, _killers)
	ExitRule.apply(self, last_events, live_before)
	_stepping = false
	tick += 1
	return true


## Adds a robot of type `def` at rest and returns its index in `robots`.
## `weapon` is `def.weapon` resolved by the caller, since core opens no files;
## without one the robot never fires.
## Allowed before the first tick or between ticks; during `step` it changes
## nothing and returns -1, because a robot appearing mid-tick would depend on
## the order things happen to be advanced in.
func spawn_robot(def: RobotDef, position: Vector3, orientation: Basis,
		weapon: WeaponDef = null) -> int:
	if _stepping:
		return -1
	var robot: RobotState = RobotState.new(def, position, orientation)
	robot.weapon = weapon
	# Even spawn indices circle one way, odd the other, so a pair of
	# strafers spread around the ship instead of chasing each other's tail.
	robot.strafe_direction = 1 if robots.size() % 2 == 0 else -1
	robots.append(robot)
	return robots.size() - 1


## Sets the walls to `p_walls`, a union of one or more boxes, or null for open
## space. Only before the first tick, so a replay can rebuild the same level
## from its header (ARC-2). Returns false, changing nothing, once the run has
## started or for a union with no boxes (no space to fly in at all).
func set_walls(p_walls: BoxUnion) -> bool:
	if tick != 0 or _stepping:
		return false
	if p_walls != null and p_walls.boxes.is_empty():
		return false
	walls = p_walls
	bounds = null if p_walls == null else p_walls.boxes[0]
	return true


## Gives the run `p_reactor`, or none for null. Only before the first tick,
## like the walls. Returns false, changing nothing, once the run has started.
func set_reactor(p_reactor: ReactorState) -> bool:
	if tick != 0 or _stepping:
		return false
	reactor = p_reactor
	return true


## Gives the run `p_debris`, or none for null or an empty list. Only before the
## first tick, like the reactor. Returns false, changing nothing, once started.
func set_debris(p_debris: MeltdownDebris) -> bool:
	if tick != 0 or _stepping:
		return false
	debris = null if p_debris == null or p_debris.size() == 0 else p_debris
	return true


## Fills the weapon slots of every ship from `loadout`'s resolved weapons.
## Only before the first tick: a run starts armed or not, and a replay must be
## able to do the same from its header alone (ARC-2). Returns false, changing
## nothing, once the run has started.
func equip(loadout: ShipLoadout) -> bool:
	if tick != 0 or _stepping:
		return false
	for ship: ShipState in ships:
		loadout.equip(ship)
	return true


## Sets the part catalogue from `parts`, a Dictionary from part id to its
## resolved `WeaponDef`. Only before the first tick, so a replay can set the
## same catalogue from its header alone (ARC-2). Returns "" on success, or a
## problem naming the part; on any problem the catalogue is left unchanged.
func set_parts(parts: Dictionary) -> String:
	if tick != 0 or _stepping:
		return "the part catalogue is set before the first tick"
	var checked: Dictionary[String, WeaponDef] = {}
	for id: Variant in parts:
		if typeof(id) != TYPE_STRING:
			return "part id %s is not a string" % str(id)
		var id_problem: String = ShipLoadout.check_id("part id", id)
		if id_problem != "":
			return id_problem
		var weapon: Variant = parts[id]
		if not weapon is WeaponDef or (weapon as WeaponDef).error != "":
			return "part \"%s\" is not a resolved weapon" % id
		checked[id] = weapon
	_parts = checked
	return ""


## Sets how parts are picked up, pulled and dropped (`SalvageRules`, #600).
## Only before the first tick, like the catalogue, so a replay can set the same
## rules from its header. Returns "" on success, or the problem, changing nothing.
func set_salvage_rules(rules: SalvageRules) -> String:
	if tick != 0 or _stepping:
		return "the salvage rules are set before the first tick"
	if rules == null or rules.error != "":
		return "the salvage rules are not resolved"
	salvage_rules = rules
	return ""


## The weapon part `id` is, or null if the catalogue has no such part.
func part(id: String) -> WeaponDef:
	return _parts.get(id, null)


## Every part id in the catalogue, sorted, so callers and the hash see one order.
func part_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_parts.keys())
	ids.sort()
	return ids


## How the run stands (RUN-3, RUN-7): running, escaped or lost. Read-only.
func outcome() -> ExitRule.Outcome:
	return ExitRule.outcome(self)


## The live ship (hull above zero, not escaped) nearest to `point`, or null if there is
## none. Ships are tested in index order and only a strictly nearer one
## replaces the best, so ties go to the lower index.
func nearest_live_ship(point: Vector3) -> ShipState:
	var best: ShipState = null
	var best_distance: float = INF
	for ship: ShipState in ships:
		if ship.hull <= 0.0 or ship.escaped:
			continue
		var distance: float = point.distance_squared_to(ship.position)
		if distance < best_distance:
			best = ship
			best_distance = distance
	return best


## Sets where ship `index` returns on a reset. Before the first tick it also
## moves the ship there, so the run starts where it would reset to.
func set_start_pose(index: int, position: Vector3, orientation: Basis) -> void:
	_reset.set_pose(index, position, orientation)
	if tick == 0:
		ships[index].position = position
		ships[index].orientation = orientation


## Hash of the whole simulation state. Projectiles, robots, salvage, the part
## catalogue, the reactor, with the run's outcome, and debris join only while
## there are any, so runs recorded before them keep their hashes.
func state_hash() -> int:
	var parts: Array[int] = [run_seed, tick]
	for ship: ShipState in ships:
		parts.append(ship.state_hash())
	if not projectiles.is_empty():
		parts.append(hash("projectiles"))
		for projectile: Projectile in projectiles:
			parts.append(projectile.state_hash())
	if not robots.is_empty():
		parts.append(hash("robots"))
		for robot: RobotState in robots:
			parts.append(robot.state_hash())
	if not salvage.is_empty():
		parts.append(hash("salvage"))
		for item: SalvageItem in salvage:
			parts.append(item.state_hash())
	if not _parts.is_empty():
		parts.append(hash("parts"))
		for id: String in part_ids():
			parts.append(hash(id))
			parts.append(_parts[id].values_hash())
	if reactor != null:
		parts.append(hash("reactor"))
		parts.append(reactor.state_hash())
		parts.append(ExitRule.state_hash(self))
	if debris != null:
		parts.append(debris.state_hash())
	return hash(parts)
