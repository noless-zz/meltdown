class_name Sim
extends RefCounted

## The authoritative simulation: owns every ship and advances them together,
## one fixed tick at a time, from one input per ship (MP-2).
##
## No nodes, devices, clock or unseeded randomness (ARC-1). Identical seed and
## inputs give an identical `state_hash()` (ARC-2), which is what replay tests
## and, later, network desync checks compare.

## Seed of this run; robot drops draw from it (ARC-2).
var run_seed: int = 0
## Number of ticks simulated so far.
var tick: int = 0
var ships: Array[ShipState] = []
## What the run fixes before its first tick (`SimRules`): the walls, the rule
## sets and the part catalogue. Filled by the constructor and the setters below.
var rules: SimRules = SimRules.new()
## Walls everything flies inside, or null for open space (GEN-5). Read-only.
var walls: BoxUnion:
	get: return rules.walls
## The first box of `walls`, or null, for older single-box callers. Read-only.
var bounds: BoxBounds:
	get: return rules.bounds
## What happened on the last tick only, in the order `SimEvent.Kind` describes.
## Output for haptics, shake and sound (PLT-6): not hashed, replaced every `step`.
var last_events: Array[SimEvent] = []
## Where each ship returns on a `reset_to_start` input, read-only here; see
## `ShipReset`. Change them with `set_start_pose`.
var start_positions: Array[Vector3]:
	get: return _reset.positions
var start_orientations: Array[Basis]:
	get: return _reset.orientations
## Every live projectile, oldest first (CMB-1). Part of the hash.
var projectiles: Array[Projectile] = []
## Every robot, in spawn order (CMB-3). Part of the hash while there are any.
var robots: Array[RobotState] = []
## Parts dropped by destroyed robots, in drop order (SLV-1), until a ship
## takes one (`SalvagePickup`). Part of the hash while there are any. They do
## not expire in M2.
var salvage: Array[SalvageItem] = []
## Component drops (CRF-1), all hashed only while `component_rules` is set
## (see `set_component_rules`; null means nothing drops): heaps in drop order
## until a ship flies through one, counts taken by kind id, and each robot's
## spawn number, which salts its drop roll (`ComponentPickup`).
var components: Array[ComponentItem] = []
var collected: Dictionary[String, int] = {}
var component_rules: ComponentPickup = null
var robot_serials: Dictionary = {}
## Miner rescue (SLV-3): rules and run state, or null when off. See `set_rescue_rules`.
var rescue: MinerRescue = null
## The level's reactor (RUN-2), or null; see `set_reactor`. Hashed when there is one.
var reactor: ReactorState = null
## Debris that falls once the reactor dies (RUN-4), or null; see `set_debris`. Hashed if any.
var debris: MeltdownDebris = null
## The level's alarm (RUN-6), or null when off; see `set_alarm_rules`. Hashed when set.
var alarm: Alarm = null
## The crew's bonus (`CrewBonus`, #1386), or null without one.
var crew: CrewBonus = null
var salvage_rules: SalvageRules:
	get: return rules.salvage_rules
var look_aim: LookAim:
	get: return rules.look_aim
var aim_assist: AimAssist:
	get: return rules.aim_assist
## This tick's projectile hit events, found before the ships move but reported after.
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
	var asleep: Array[RobotState] = Alarm.sleeping(self)
	if tick == 0:
		_reset.record(ships)
	ExitRule.count_down(self)
	if debris != null:
		DebrisRouteGuard.advance(self, last_events)
	# Projectiles already in flight move before any new shot, so a shot
	# spawns where its ship is at the end of the tick it was fired on.
	ProjectileHits.advance(self, _hit_events, _killers)
	var shots_before: int = projectiles.size()
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
		PartSlotting.apply(self, i, inputs[i], slot_drops)
		look_aim.turn_gun(ship, inputs[i].aim())
		ProjectileHits.fire(self, i, inputs[i].fire_primary)
	var shots: int = projectiles.size() - shots_before
	last_events.append_array(_hit_events)
	SalvagePickup.collect(self, from)
	ComponentPickup.collect(self, from)
	MinerRescue.step(self)
	RobotTick.advance(self)
	Alarm.step(self, shots, asleep)
	SalvagePickup.drift(self, slot_drops)
	ComponentPickup.drop(self)
	RobotTick.remove_destroyed(self, _killers)
	ExitRule.apply(self, last_events, live_before)
	_stepping = false
	tick += 1
	return true


## Adds a robot of type `def` at rest and returns its index in `robots`. `weapon`
## is `def.weapon` resolved by the caller (core opens no files); without one the
## robot never fires. During `step` it changes nothing and returns -1, because a
## robot appearing mid-tick would depend on the order things are advanced in.
func spawn_robot(def: RobotDef, position: Vector3, orientation: Basis,
		weapon: WeaponDef = null) -> int:
	if _stepping:
		return -1
	var robot: RobotState = RobotState.new(def, position, orientation)
	robot.weapon = weapon
	# Even spawn indices circle one way, odd the other, so a pair of
	# strafers spread around the ship instead of chasing each other's tail.
	robot.strafe_direction = 1 if robots.size() % 2 == 0 else -1
	robot_serials[robot] = robot_serials.size()
	robots.append(robot)
	return robots.size() - 1


## Sets the walls to `p_walls`, or null for open space; see `SimRules.set_walls`.
func set_walls(p_walls: BoxUnion) -> bool:
	return rules.set_walls(p_walls, tick != 0 or _stepping)


## Gives the run `p_reactor` (null for none). Only before the first tick: false once started.
func set_reactor(p_reactor: ReactorState) -> bool:
	if tick != 0 or _stepping:
		return false
	reactor = p_reactor
	return true


## Gives the run `p_debris` (null or empty for none). Only before the first tick, like the reactor.
func set_debris(p_debris: MeltdownDebris) -> bool:
	if tick != 0 or _stepping:
		return false
	debris = null if p_debris == null or p_debris.size() == 0 else p_debris
	return true


## Fills every ship's weapon slots from `loadout`. Only before the first tick, so
## a replay can arm the same from its header (ARC-2); false, changing nothing, after.
func equip(loadout: ShipLoadout) -> bool:
	if tick != 0 or _stepping:
		return false
	for ship: ShipState in ships:
		loadout.equip(ship)
	return true


## Sets the part catalogue, part id to resolved `WeaponDef`; see `SimRules`.
func set_parts(parts: Dictionary) -> String:
	return rules.set_parts(parts, tick != 0 or _stepping)


## Sets how parts are picked up, pulled and dropped (`SalvageRules`, #600).
func set_salvage_rules(p_rules: SalvageRules) -> String:
	return rules.set_salvage_rules(p_rules, tick != 0 or _stepping)


## Switches component drops on with `p_rules` (`ComponentPickup`, CRF-1).
func set_component_rules(p_rules: ComponentPickup) -> String:
	return ComponentPickup.install(self, p_rules, tick != 0 or _stepping)


## Switches miner rescue on (`MinerRescue`, SLV-3), trapping `miners` in mm as `LevelDef.miners`.
func set_rescue_rules(p_rules: MinerRescue, miners: Array[Vector3i] = []) -> String:
	return MinerRescue.install(self, p_rules, miners, tick != 0 or _stepping)


## Switches the alarm on with `p_rules` and the shaft's `risk` multiplier (`Alarm`, RUN-6).
func set_alarm_rules(p_rules: Alarm, risk: float = 1.0) -> String:
	return Alarm.install(self, p_rules, risk, tick != 0 or _stepping)


## Grows the holds and the countdown by the crew's `bonus` (`CrewBonus`, CRW-1). After the reactor.
func set_crew_bonus(bonus: CrewBonus) -> String:
	return CrewBonus.install(self, bonus, tick != 0 or _stepping)


## Sets the look-aim cone and gimbal rate (`LookAim`, CMB-6).
func set_look_aim(aim: LookAim) -> String:
	return rules.set_look_aim(aim, tick != 0 or _stepping)


## Sets the aim assist cone and range (`AimAssist`, CMB-7).
func set_aim_assist(assist: AimAssist) -> String:
	return rules.set_aim_assist(assist, tick != 0 or _stepping)


## The weapon part `id` is, or null if the catalogue has no such part.
func part(id: String) -> WeaponDef:
	return rules.part(id)


## Every part id in the catalogue, sorted, so callers and the hash see one order.
func part_ids() -> Array[String]:
	return rules.part_ids()


## How the run stands (RUN-3, RUN-7): running, escaped or lost. Read-only.
func outcome() -> ExitRule.Outcome:
	return ExitRule.outcome(self)


## The live ship (hull above zero, not escaped) nearest `point`, or null; ties go low.
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


## Hash of the whole simulation state; see `SimHash`.
func state_hash() -> int:
	return SimHash.of(self)
