extends RefCounted

## Robots behind a wall can neither see nor hit the ship (#615, CMB-2, CMB-3,
## ARC-1, ARC-2): robots fire only with a clear line through open space, shots
## end where they leave it, and a robot that loses the line for long enough
## aims afresh before its next shot.

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## Ten seconds at 60 Hz.
const TEN_SECONDS: int = 600
const ROBOT_AT: Vector3 = Vector3(20.0, 3.0, 3.0)
const SHIP_AT: Vector3 = Vector3(20.0, 3.0, 11.0)
## Facing +Z, from the robot towards the ship.
const FACING_PLUS_Z: Basis = Basis(Vector3.UP, PI)


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


## Two corridors along x, side by side on z, `gap` metres of wall between
## them; with `connector`, a box overlapping both opens a window at x 18..22.
func _boxes(gap: float, connector: bool) -> Array[BoxBounds]:
	var near: BoxBounds = BoxBounds.new(Vector3(0.0, 0.0, 0.0), Vector3(40.0, 6.0, 6.0))
	var far: BoxBounds = BoxBounds.new(Vector3(0.0, 0.0, 6.0 + gap), Vector3(40.0, 6.0, 14.0))
	var boxes: Array[BoxBounds] = [near, far]
	if connector:
		boxes.append(BoxBounds.new(Vector3(18.0, 0.0, 4.0), Vector3(22.0, 6.0, 6.0 + gap + 2.0)))
	return boxes


## A drone in the near corridor facing the ship, which sits still in the far
## one, facing the drone, with a shield that does not recharge.
func _sim(boxes: Array[BoxBounds]) -> Sim:
	var sim: Sim = Sim.new(615, 1)
	sim.set_walls(BoxUnion.new(boxes))
	sim.set_start_pose(0, SHIP_AT, Basis.IDENTITY)
	sim.ships[0].shield_recharge = 0.0
	sim.spawn_robot(_drone(), ROBOT_AT, FACING_PLUS_Z, _cannon())
	return sim


func _step(sim: Sim, fire: bool = false) -> void:
	var inputs: Array[ShipInput] = [ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, fire)]
	sim.step(inputs)


func _health(ship: ShipState) -> float:
	return ship.shield + ship.hull


## Flies `ticks` and returns "" if no robot shot was ever seen and no damage was
## done to the ship, or what went wrong.
func _robot_holds_fire(sim: Sim, ticks: int) -> String:
	var start: float = _health(sim.ships[0])
	for i: int in ticks:
		_step(sim)
		for projectile: Projectile in sim.projectiles:
			if projectile.is_robot_owned():
				return "tick %d: the robot fired with no line to the ship (shot at %s)" % [
					sim.tick, projectile.position]
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_HIT:
				return "tick %d: the ship was hit through the wall" % sim.tick
	if _health(sim.ships[0]) != start:
		return "the ship lost %f through the wall" % (start - _health(sim.ships[0]))
	return ""


func test_a_robot_behind_a_wall_never_fires_or_hurts_the_ship() -> String:
	return _robot_holds_fire(_sim(_boxes(2.0, false)), TEN_SECONDS)


## Generated levels put boxes face to face; there is a wall there too.
func test_a_robot_behind_a_face_to_face_wall_never_fires() -> String:
	var problem: String = _robot_holds_fire(_sim(_boxes(0.0, false)), TEN_SECONDS)
	return "" if problem == "" else "face to face: " + problem


func test_through_a_real_opening_the_robot_still_hits() -> String:
	var sim: Sim = _sim(_boxes(2.0, true))
	var start: float = _health(sim.ships[0])
	for i: int in TEN_SECONDS:
		_step(sim)
	if _health(sim.ships[0]) >= start:
		return "a robot with a clear line through the opening never hit the ship"
	return ""


## Even with the robot made to fire at a ship behind the wall, the shot ends
## at the wall and never reaches the other corridor or the ship.
## Face to face as well as with a wall 2 m thick.
func test_a_shot_fired_at_a_wall_ends_at_it() -> String:
	for gap: float in [2.0, 0.0]:
		var sim: Sim = _sim(_boxes(gap, false))
		var start: float = _health(sim.ships[0])
		var cannon: WeaponDef = _cannon()
		sim.projectiles.append(Projectile.new(ROBOT_AT, Vector3.BACK * cannon.projectile_speed,
			Projectile.robot_owner(0), cannon.lifetime_ticks(), cannon.damage))
		for i: int in 120:
			_step(sim)
			for projectile: Projectile in sim.projectiles:
				if projectile.position.z > 6.0 + 1e-4:
					return "gap %f, tick %d: a shot reached z %f, past the wall at 6" % [
						gap, sim.tick, projectile.position.z]
		if _health(sim.ships[0]) != start:
			return "gap %f: the ship lost %f to a shot through the wall" % [
				gap, start - _health(sim.ships[0])]
	return ""


## The same holds for the ship's own shots: nothing behind the wall is hit.
func test_a_ship_shot_does_not_hurt_a_robot_behind_the_wall() -> String:
	var sim: Sim = _sim(_boxes(2.0, false))
	var cannon: WeaponDef = _cannon()
	var robot_hull: float = sim.robots[0].hull
	for i: int in 120:
		# Straight at the robot, along -z; every shot must stop at the wall at z 8.
		if i % 20 == 0:
			sim.projectiles.append(Projectile.new(SHIP_AT, Vector3.FORWARD * cannon.projectile_speed,
				0, cannon.lifetime_ticks(), cannon.damage))
		_step(sim)
		for projectile: Projectile in sim.projectiles:
			if not projectile.is_robot_owned() and projectile.position.z < 8.0 - 1e-4:
				return "tick %d: a ship shot reached z %f, past the wall at 8" % [
					sim.tick, projectile.position.z]
	if sim.robots.is_empty() or sim.robots[0].hull != robot_hull:
		return "the robot behind the wall was hurt"
	return ""


func test_a_robot_that_loses_the_line_briefly_fires_at_once_when_it_returns() -> String:
	var robot: RobotState = RobotState.new(_drone(), Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z)
	robot.weapon = _cannon()
	var ship: ShipState = ShipState.new()
	var short: int = robot.def.lose_target_ticks() - 1
	for i: int in short:
		if robot.fire_at(ship, false) != null:
			return "fired with no line"
	if robot.fire_at(ship, true) == null:
		return "did not fire at once after %d ticks without a line" % short
	if robot.unseen_ticks != 0:
		return "unseen ticks %d after seeing the ship" % robot.unseen_ticks
	return ""


func test_a_robot_that_drops_its_target_waits_a_fire_interval() -> String:
	var robot: RobotState = RobotState.new(_drone(), Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z)
	robot.weapon = _cannon()
	var ship: ShipState = ShipState.new()
	var lose: int = robot.def.lose_target_ticks()
	if lose != 120:
		return "the default drop time is %d ticks, expected 2 s = 120" % lose
	for i: int in lose + 30:
		robot.fire_at(ship, false)
	if robot.unseen_ticks != lose:
		return "unseen ticks %d, expected to stop at %d" % [robot.unseen_ticks, lose]
	var waited: int = 0
	while robot.fire_at(ship, true) == null:
		waited += 1
		if waited > 1000:
			return "never fired again"
	# The first call re-aims and sets the interval; it counts down from the next.
	if waited != robot.weapon.fire_interval_ticks:
		return "fired after %d ticks, expected the fire interval %d" % [
			waited, robot.weapon.fire_interval_ticks]
	return ""


func test_the_drop_time_is_read_from_the_robot_file() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DRONE))
	data["lose_target_seconds"] = 0.5
	var def: RobotDef = RobotDef.parse_json(JSON.stringify(data))
	if def.error != "":
		return def.error
	if def.lose_target_ticks() != 30:
		return "0.5 s gave %d ticks" % def.lose_target_ticks()
	return ""


## Same seed, same level, same inputs: the same hash, wall or not (ARC-2).
func test_runs_behind_a_wall_are_deterministic() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = _sim(_boxes(2.0, false))
		for i: int in 300:
			_step(sim, i % 7 == 0)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "two identical runs gave %d and %d" % hashes
	return ""
