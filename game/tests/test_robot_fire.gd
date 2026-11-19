extends RefCounted

## Robots firing their weapon at the ship: range, facing cone, fire interval,
## robot-owned shots hitting ships and never robots (CMB-2, CMB-3, MP-2,
## ARC-2, #225).

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## A robot turned half a turn about the vertical faces +Z, towards a ship
## sitting at the origin when the robot is further along -Z.
const FACING_PLUS_Z: Basis = Basis(Vector3.UP, PI)


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


## One ship at rest at the origin whose shield does not recharge, so every
## point of damage shows exactly.
func _sim() -> Sim:
	var sim: Sim = Sim.new(9, 1)
	sim.ships[0].shield_recharge = 0.0
	return sim


func _step(sim: Sim, fire: bool = false) -> void:
	var inputs: Array[ShipInput] = [ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, fire)]
	sim.step(inputs)


func _events(sim: Sim, kind: SimEvent.Kind) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == kind:
			found.append(event)
	return found


func _robot_shots(sim: Sim) -> int:
	var count: int = 0
	for projectile: Projectile in sim.projectiles:
		if projectile.is_robot_owned():
			count += 1
	return count


func test_a_drone_facing_the_ship_fires_at_its_interval_shield_then_hull() -> String:
	var sim: Sim = _sim()
	var cannon: WeaponDef = _cannon()
	sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z, cannon)
	var ship: ShipState = sim.ships[0]
	var start_shield: float = ship.shield
	var start_hull: float = ship.hull
	# Enough hits to empty the shield and take one bite of the hull.
	var wanted: int = int(ceilf(start_shield / cannon.damage))
	var hit_ticks: Array[int] = []
	var limit: int = (wanted + 2) * cannon.fire_interval_ticks
	while hit_ticks.size() < wanted and sim.tick < limit:
		var tick: int = sim.tick
		_step(sim)
		for event: SimEvent in _events(sim, SimEvent.Kind.SHIP_HIT):
			if event.ship != 0 or event.magnitude != cannon.damage:
				return "hit event %s, expected ship 0 and damage %f" % [event, cannon.damage]
			if event.vector.dot(Vector3.BACK) < 0.99:
				return "hit direction %s, expected the shot's flight along +Z" % event.vector
			hit_ticks.append(tick)
			var hits: int = hit_ticks.size()
			var expected_shield: float = maxf(start_shield - cannon.damage * hits, 0.0)
			var expected_hull: float = start_hull - maxf(cannon.damage * hits - start_shield, 0.0)
			if ship.shield != expected_shield or ship.hull != expected_hull:
				return "after %d hits shield %f hull %f, expected %f and %f" % [
					hits, ship.shield, ship.hull, expected_shield, expected_hull]
	if hit_ticks.size() < wanted:
		return "only %d hits in %d ticks, expected %d" % [hit_ticks.size(), sim.tick, wanted]
	for i: int in range(1, hit_ticks.size()):
		if hit_ticks[i] - hit_ticks[i - 1] != cannon.fire_interval_ticks:
			return "hits on ticks %s, expected every %d ticks" % [hit_ticks, cannon.fire_interval_ticks]
	if ship.hull >= start_hull:
		return "the hull never dropped; the test did not reach it"
	return ""


func test_a_ship_behind_the_drone_is_not_fired_at() -> String:
	var sim: Sim = _sim()
	# Facing -Z, away from the ship at the origin. It turns towards the ship
	# at its turn rate, so look only while the ship is still outside the cone.
	var drone: RobotDef = _drone()
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -10.0), Basis.IDENTITY, _cannon())
	var cone: float = deg_to_rad(RobotState.FIRE_CONE_HALF_ANGLE_DEG)
	var ticks: int = int((PI - cone) / deg_to_rad(drone.turn_rate) * ShipState.TICK_RATE) - 1
	for i: int in ticks:
		_step(sim)
		if _robot_shots(sim) != 0:
			return "fired on tick %d at a ship %f rad off its facing" % [
				i, sim.robots[0].forward().angle_to(-sim.robots[0].position)]
	return ""


func test_a_ship_out_of_range_is_not_fired_at() -> String:
	var sim: Sim = _sim()
	var robot: int = sim.spawn_robot(_drone(), Vector3.ZERO, FACING_PLUS_Z, _cannon())
	var range_m: float = sim.robots[robot].weapon_range()
	sim.robots[robot].position = Vector3(0.0, 0.0, -range_m - 5.0)
	for i: int in 60:
		_step(sim)
		if _robot_shots(sim) != 0:
			return "fired on tick %d at a ship %f m away, range %f m" % [i, range_m + 5.0, range_m]
	return ""


func test_a_robot_shot_passes_through_another_robot() -> String:
	var sim: Sim = _sim()
	var drone: RobotDef = _drone()
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -20.0), FACING_PLUS_Z, _cannon())
	# Unarmed and right in the line of fire.
	var blocker: int = sim.spawn_robot(drone, Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z)
	var ship_hits: int = 0
	for i: int in 30:
		_step(sim)
		ship_hits += _events(sim, SimEvent.Kind.SHIP_HIT).size()
		if not _events(sim, SimEvent.Kind.ROBOT_HIT).is_empty():
			return "a robot's shot hit a robot on tick %d" % i
	if sim.robots[blocker].hull != drone.hull:
		return "the robot in the line of fire lost hull: %f of %f" % [sim.robots[blocker].hull, drone.hull]
	if ship_hits == 0:
		return "the shot did not reach the ship behind the other robot"
	return ""


func test_a_robot_without_a_weapon_never_fires() -> String:
	var sim: Sim = _sim()
	sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z)
	for i: int in 120:
		_step(sim)
		if not sim.projectiles.is_empty():
			return "an unarmed robot fired on tick %d" % i
	var ship: ShipState = sim.ships[0]
	if ship.shield != ship.max_shield or ship.hull != ship.max_hull:
		return "the ship took damage from an unarmed robot"
	return ""


func test_ship_shots_never_hit_their_own_ship() -> String:
	var sim: Sim = _sim()
	sim.ships[0].primary_slots[0] = _cannon()
	for i: int in 60:
		_step(sim, true)
		if not _events(sim, SimEvent.Kind.SHIP_HIT).is_empty():
			return "the ship's own shot hit it on tick %d" % i
	if sim.projectiles.is_empty():
		return "the ship never fired; the test proves nothing"
	if sim.ships[0].shield != sim.ships[0].max_shield:
		return "the ship's shield dropped from its own fire"
	return ""


func test_robot_shots_are_marked_robot_owned() -> String:
	var sim: Sim = _sim()
	sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z, _cannon())
	_step(sim)
	if sim.projectiles.size() != 1:
		return "%d projectiles after the first tick, expected 1" % sim.projectiles.size()
	var shot: Projectile = sim.projectiles[0]
	if shot.owner_index != Projectile.robot_owner(0) or not shot.is_robot_owned():
		return "owner %d, expected %d" % [shot.owner_index, Projectile.robot_owner(0)]
	return ""


func test_armed_robots_are_deterministic() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = Sim.new(4, 1)
		sim.spawn_robot(_drone(), Vector3(2.0, 1.0, -15.0), FACING_PLUS_Z, _cannon())
		sim.spawn_robot(_drone(), Vector3(-3.0, 0.0, -25.0), Basis.IDENTITY, _cannon())
		for i: int in 180:
			_step(sim)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "two identical runs hash %d and %d" % [hashes[0], hashes[1]]
	return ""


func test_a_weapon_changes_the_robot_hash_and_no_weapon_keeps_it() -> String:
	var plain: RobotState = RobotState.new(_drone())
	var before: int = plain.state_hash()
	var armed: RobotState = RobotState.new(_drone())
	armed.weapon = _cannon()
	if armed.state_hash() == before:
		return "an armed robot hashes like an unarmed one"
	var expected: int = hash([
		"def", plain.def.values_hash(),
		"position", plain.position,
		"velocity", plain.velocity,
		"orientation", plain.orientation,
		"hull", plain.hull,
		"strafe_direction", plain.strafe_direction,
	])
	if before != expected:
		return "an unarmed robot's hash changed from the one recorded before weapons"
	return ""
