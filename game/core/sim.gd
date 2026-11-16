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
## Walls the ships fly inside, or null for open space. Not part of the hash:
## it is fixed for the run, like the seed's mine will be.
var bounds: BoxBounds = null
## What happened on the last tick only, in ship order and, per ship, in the
## order of `SimEvent.Kind`. Derived output for haptics, shake and sound
## (PLT-6): not part of the hash, replaced by every call to `step`.
var last_events: Array[SimEvent] = []
## Where each ship returns on a `reset_to_start` input. Recorded when the ship
## is created and again just before the first tick, so a caller that places a
## ship before flying (for example inside the test tunnel) is honoured. Fixed
## for the run like `bounds`, so not part of the hash.
var start_positions: Array[Vector3] = []
var start_orientations: Array[Basis] = []
## Every live projectile, oldest first (CMB-1). Part of the hash.
var projectiles: Array[Projectile] = []
## Every robot, in spawn order (CMB-3). Part of the hash while there are any.
var robots: Array[RobotState] = []
## Parts dropped by destroyed robots, in drop order (SLV-1). Part of the hash
## while there are any. They do not expire in M2.
var salvage: Array[SalvageItem] = []
## Projectile hit events of the tick being stepped. Hits are found when
## projectiles move, before the ships, but their events follow the ship events.
var _hit_events: Array[SimEvent] = []
## Robot index to the ship whose shot destroyed it, for the tick being stepped.
var _killers: Dictionary = {}
## True only while `step` runs, so a spawn cannot land part-way through a tick.
var _stepping: bool = false


func _init(p_run_seed: int = 0, ship_count: int = 1, p_bounds: BoxBounds = null) -> void:
	run_seed = p_run_seed
	bounds = p_bounds
	for i: int in ship_count:
		ships.append(ShipState.new())
	_record_start_poses()


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
	if tick == 0:
		_record_start_poses()
	# Projectiles already in flight move before any new shot, so a shot
	# spawns where its ship is at the end of the tick it was fired on.
	_advance_projectiles()
	for i: int in ships.size():
		var ship: ShipState = ships[i]
		if inputs[i].reset_to_start:
			_reset_to_start(i)
		var was_active: bool = ship.afterburner_active
		var was_locked: bool = ship.afterburner_locked
		ship.step(inputs[i].thrust(), inputs[i].turn(), inputs[i].afterburner)
		if ship.afterburner_active and not was_active:
			last_events.append(SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, i))
		elif was_active and not ship.afterburner_active:
			last_events.append(SimEvent.new(SimEvent.Kind.AFTERBURNER_STOPPED, i))
		if ship.afterburner_locked and not was_locked:
			last_events.append(SimEvent.new(SimEvent.Kind.ENERGY_DEPLETED, i))
		if bounds != null:
			var impact: Vector3 = bounds.contain_impact(ship)
			if impact != Vector3.ZERO:
				last_events.append(SimEvent.new(
					SimEvent.Kind.WALL_IMPACT, i, impact.length(), -impact.normalized()))
		_fire(i, inputs[i].fire_primary)
	last_events.append_array(_hit_events)
	_advance_robots()
	# Items already floating move before this tick's drops, so a part appears
	# exactly where its robot died.
	for item: SalvageItem in salvage:
		item.advance(bounds)
	_remove_destroyed_robots()
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


## Moves every robot one tick, after the ships, towards its target, keeps it
## inside the walls and fires at its target if it can. The shot leaves the
## robot's centre along its facing at the weapon's speed, like a ship's.
func _advance_robots() -> void:
	for r: int in robots.size():
		var robot: RobotState = robots[r]
		robot.step(nearest_live_ship(robot.position))
		if bounds != null:
			robot.keep_inside(bounds)
		var weapon: WeaponDef = robot.fire_at(nearest_live_ship(robot.position))
		if weapon != null:
			projectiles.append(Projectile.new(robot.position,
				robot.forward() * weapon.projectile_speed, Projectile.robot_owner(r),
				weapon.lifetime_ticks(), weapon.damage))


## The live ship (hull above zero) nearest to `point`, or null if there is
## none. Ships are tested in index order and only a strictly nearer one
## replaces the best, so ties go to the lower index.
func nearest_live_ship(point: Vector3) -> ShipState:
	var best: ShipState = null
	var best_distance: float = INF
	for ship: ShipState in ships:
		if ship.hull <= 0.0:
			continue
		var distance: float = point.distance_squared_to(ship.position)
		if distance < best_distance:
			best = ship
			best_distance = distance
	return best


## Sets where ship `index` returns on a reset. Before the first tick it also
## moves the ship there, so the run starts where it would reset to.
func set_start_pose(index: int, position: Vector3, orientation: Basis) -> void:
	start_positions[index] = position
	start_orientations[index] = orientation
	if tick == 0:
		ships[index].position = position
		ships[index].orientation = orientation


func _record_start_poses() -> void:
	start_positions.clear()
	start_orientations.clear()
	for ship: ShipState in ships:
		start_positions.append(ship.position)
		start_orientations.append(ship.orientation)


## Pose and velocity only: hull, shield and energy are kept, so a reset is a
## way home and not a free repair.
func _reset_to_start(index: int) -> void:
	var ship: ShipState = ships[index]
	ship.position = start_positions[index]
	ship.orientation = start_orientations[index]
	ship.velocity = Vector3.ZERO


## Removes robots whose hull reached zero this tick, keeping the order of
## the rest, so robot indices stay in spawn order. Each leaves its salvage, in
## robot order, with a SALVAGE_DROPPED event after the tick's other events.
func _remove_destroyed_robots() -> void:
	var kept: Array[RobotState] = []
	for r: int in robots.size():
		var robot: RobotState = robots[r]
		if robot.is_alive():
			kept.append(robot)
			continue
		var item: SalvageItem = SalvageItem.dropped_by(robot)
		if item != null:
			salvage.append(item)
			last_events.append(SimEvent.new(SimEvent.Kind.SALVAGE_DROPPED,
				_killers.get(r, 0), salvage.size() - 1, item.position))
	robots = kept


## Moves every projectile one tick and removes those that hit a robot (ship
## shots) or a ship (robot shots), whose
## lifetime is over or that have left the walls. The hit test runs on the
## whole segment flown this tick, before the other two, so a shot on its
## last tick or leaving through a wall still hits what it passed on the way.
func _advance_projectiles() -> void:
	var kept: Array[Projectile] = []
	for projectile: Projectile in projectiles:
		var from: Vector3 = projectile.position
		var alive: bool = projectile.advance()
		var hit: bool = (_hit_ship(projectile, from) if projectile.is_robot_owned()
			else _hit_robot(projectile, from))
		if hit:
			continue
		if not alive:
			continue
		if bounds != null and not bounds.holds(projectile.position, 0.0):
			continue
		kept.append(projectile)
	projectiles = kept


## Applies `projectile`'s damage to the first live robot its segment from
## `from` to its current position passes within reach of, and records the
## events. Returns whether it hit, so the caller removes it: one shot never
## hits two robots. Robots are tested in index order and only a strictly
## nearer entry replaces the best, so ties go to the lower index.
func _hit_robot(projectile: Projectile, from: Vector3) -> bool:
	var best: int = -1
	var best_t: float = INF
	for r: int in robots.size():
		if not robots[r].is_alive():
			continue
		var t: float = robots[r].segment_entry(from, projectile.position)
		if t >= 0.0 and t < best_t:
			best = r
			best_t = t
	if best < 0:
		return false
	var robot: RobotState = robots[best]
	robot.apply_damage(projectile.damage)
	var direction: Vector3 = projectile.velocity.normalized()
	_hit_events.append(SimEvent.new(SimEvent.Kind.ROBOT_HIT, projectile.owner_index,
		projectile.damage, direction))
	if not robot.is_alive():
		_hit_events.append(SimEvent.new(SimEvent.Kind.ROBOT_DESTROYED, projectile.owner_index))
		_killers[best] = projectile.owner_index
	return true


## As `_hit_robot`, for a robot's shot against the live ships (hull above
## zero), within each ship's `radius`: the damage goes through
## `ShipState.apply_damage`, shield first, and a SHIP_HIT event names the ship.
func _hit_ship(projectile: Projectile, from: Vector3) -> bool:
	var best: int = -1
	var best_t: float = INF
	for i: int in ships.size():
		var ship: ShipState = ships[i]
		if ship.hull <= 0.0:
			continue
		var t: float = Projectile.segment_entry(from, projectile.position, ship.position, ship.radius)
		if t >= 0.0 and t < best_t:
			best = i
			best_t = t
	if best < 0:
		return false
	ships[best].apply_damage(projectile.damage)
	_hit_events.append(SimEvent.new(SimEvent.Kind.SHIP_HIT, best, projectile.damage,
		projectile.velocity.normalized()))
	return true


## Fires ship `index`'s primary weapon if it is held and ready. The shot
## leaves the ship's nose at the weapon's speed, without the ship's own
## velocity, so a weapon's range is exactly what its data file says.
func _fire(index: int, held: bool) -> void:
	var ship: ShipState = ships[index]
	var weapon: WeaponDef = ship.fire_primary(held)
	if weapon == null:
		return
	var forward: Vector3 = -ship.orientation.z.normalized()
	projectiles.append(Projectile.new(ship.position, forward * weapon.projectile_speed,
		index, weapon.lifetime_ticks(), weapon.damage))


## Hash of the whole simulation state. Projectiles, robots and salvage join
## only while there are any, so runs recorded before them keep their hashes.
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
	return hash(parts)
