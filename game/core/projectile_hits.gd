class_name ProjectileHits
extends RefCounted

## Moving projectiles and finding what they hit (CMB-1, CMB-2). Kept out of
## `Sim` so the tick there stays short; `Sim.step` calls `advance` once per
## tick, before the ships move, and `fire` for each ship after it moves.


## Moves every projectile in `sim.projectiles` one tick and removes those that
## hit a robot or the reactor (ship shots) or a ship (robot shots, which pass
## through the reactor), whose lifetime is over or
## that have left the walls. The hit test runs on the whole segment flown this
## tick, before the other two, so a shot on its last tick or leaving through a
## wall still hits what it passed on the way. Hit events go to `hit_events`;
## each robot destroyed is recorded in `killers` as robot index to the ship
## whose shot destroyed it.
static func advance(sim: Sim, hit_events: Array[SimEvent], killers: Dictionary) -> void:
	var kept: Array[Projectile] = []
	for projectile: Projectile in sim.projectiles:
		var from: Vector3 = projectile.position
		var alive: bool = projectile.advance()
		var hit: bool = (_hit_ship(sim, projectile, from, hit_events)
			if projectile.is_robot_owned()
			else _hit_robot(sim, projectile, from, hit_events, killers))
		if hit:
			continue
		if not alive:
			continue
		if sim.walls != null and not sim.walls.holds(projectile.position, 0.0):
			continue
		kept.append(projectile)
	sim.projectiles = kept


## Fires ship `index`'s primary weapon if it is held and ready. The shot
## leaves the ship's nose at the weapon's speed, without the ship's own
## velocity, so a weapon's range is exactly what its data file says.
static func fire(sim: Sim, index: int, held: bool) -> void:
	var ship: ShipState = sim.ships[index]
	var weapon: WeaponDef = ship.fire_primary(held)
	if weapon == null:
		return
	var forward: Vector3 = -ship.orientation.z.normalized()
	sim.projectiles.append(Projectile.new(ship.position, forward * weapon.projectile_speed,
		index, weapon.lifetime_ticks(), weapon.damage))


## Applies `projectile`'s damage to the first live robot or intact reactor its
## segment from `from` to its current position passes within reach of, and
## records the events. Returns whether it hit, so the caller removes it: one
## shot never hits two targets. Robots are tested in index order, then the
## reactor, and only a strictly nearer entry replaces the best, so ties go to
## the lower index and robots win ties with the reactor.
static func _hit_robot(sim: Sim, projectile: Projectile, from: Vector3,
		hit_events: Array[SimEvent], killers: Dictionary) -> bool:
	var best: int = -1
	var best_t: float = INF
	for r: int in sim.robots.size():
		if not sim.robots[r].is_alive():
			continue
		var t: float = sim.robots[r].segment_entry(from, projectile.position)
		if t >= 0.0 and t < best_t:
			best = r
			best_t = t
	if sim.reactor != null:
		var reactor_t: float = sim.reactor.segment_entry(from, projectile.position)
		if reactor_t >= 0.0 and reactor_t < best_t:
			if sim.reactor.apply_damage(projectile.damage):
				if sim.reactor.scales_with_path:
					sim.reactor.meltdown_ticks_left = sim.reactor.meltdown_ticks_for_path(
						EscapePath.longest_for_ships(sim))
				hit_events.append(SimEvent.new(SimEvent.Kind.REACTOR_DESTROYED,
					projectile.owner_index, 0.0, sim.reactor.position()))
			return true
	if best < 0:
		return false
	var robot: RobotState = sim.robots[best]
	robot.apply_damage(projectile.damage)
	var direction: Vector3 = projectile.velocity.normalized()
	hit_events.append(SimEvent.new(SimEvent.Kind.ROBOT_HIT, projectile.owner_index,
		projectile.damage, direction))
	if not robot.is_alive():
		hit_events.append(SimEvent.new(SimEvent.Kind.ROBOT_DESTROYED, projectile.owner_index))
		killers[best] = projectile.owner_index
	return true


## As `_hit_robot`, for a robot's shot against the live ships (hull above
## zero, not escaped: an escaped ship has left the level), within each ship's `radius`: the damage goes through
## `ShipState.apply_damage`, shield first, and a SHIP_HIT event names the ship.
static func _hit_ship(sim: Sim, projectile: Projectile, from: Vector3,
		hit_events: Array[SimEvent]) -> bool:
	var best: int = -1
	var best_t: float = INF
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.hull <= 0.0 or ship.escaped:
			continue
		var t: float = Projectile.segment_entry(from, projectile.position, ship.position, ship.radius)
		if t >= 0.0 and t < best_t:
			best = i
			best_t = t
	if best < 0:
		return false
	sim.ships[best].apply_damage(projectile.damage)
	hit_events.append(SimEvent.new(SimEvent.Kind.SHIP_HIT, best, projectile.damage,
		projectile.velocity.normalized()))
	return true
