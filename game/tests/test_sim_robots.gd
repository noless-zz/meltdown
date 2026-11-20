extends RefCounted

## Robots in the simulation: spawned from data, hovering, part of the hash
## (CMB-3, MP-2, ARC-1, ARC-2, ARC-4, #204).

const DRONE: String = "res://data/robots/drone.json"
## `Sim.state_hash()` after `_fly_reference` on `main` before robots existed
## (commit 2c68c89). A sim with no robots must still give exactly this, so
## every recorded replay hash stays valid.
## Re-measured after #603 retuned the pulse cannon the flight fires.
const REFERENCE_HASH: int = 4114825600


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _tunnel() -> BoxBounds:
	return BoxBounds.new(Vector3(-10.0, -10.0, -200.0), Vector3(10.0, 10.0, 10.0))


## Flies one armed ship forward, turning and firing, inside the tunnel. Uses
## walls, weapons and projectiles so the reference covers every hashed part.
func _fly_reference(sim: Sim) -> void:
	sim.ships[0].primary_slots[0] = WeaponDef.parse_json(
		FileAccess.get_file_as_string("res://data/weapons/pulse_cannon.json"))
	var input: ShipInput = ShipInput.new(
		Vector3i(300, -200, -1000), Vector3i(100, -150, 50), false, false, true)
	for i: int in 100:
		sim.step([input])


func test_drone_file_parses_for_spawning() -> String:
	if _drone().error != "":
		return "drone.json rejected: %s" % _drone().error
	return ""


func test_spawn_returns_index_and_sets_state() -> String:
	var sim: Sim = Sim.new(3, 1)
	var drone: RobotDef = _drone()
	var turned: Basis = Basis(Vector3.UP, 0.5)
	var first: int = sim.spawn_robot(drone, Vector3(1.0, 2.0, -30.0), turned)
	var second: int = sim.spawn_robot(drone, Vector3(-1.0, 0.0, -40.0), Basis.IDENTITY)
	if first != 0 or second != 1 or sim.robots.size() != 2:
		return "spawn indices %d, %d with %d robots" % [first, second, sim.robots.size()]
	var robot: RobotState = sim.robots[0]
	if robot.def != drone or robot.position != Vector3(1.0, 2.0, -30.0) or robot.orientation != turned:
		return "spawned robot does not hold its definition and pose"
	if robot.hull != drone.hull or robot.velocity != Vector3.ZERO:
		return "spawned robot starts with hull %s and velocity %s" % [robot.hull, robot.velocity]
	return ""


func test_drone_keeps_its_position_for_600_ticks() -> String:
	var sim: Sim = Sim.new(3, 1, _tunnel())
	var spawn: Vector3 = Vector3(2.0, -1.0, -50.0)
	sim.spawn_robot(_drone(), spawn, Basis.IDENTITY)
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO)
	for i: int in 600:
		sim.step([input])
		if sim.robots[0].position != spawn:
			return "drone moved to %s at tick %d" % [sim.robots[0].position, sim.tick]
	return ""


func test_hover_damps_velocity_at_acceleration() -> String:
	var sim: Sim = Sim.new(3, 1)
	var drone: RobotDef = _drone()
	sim.spawn_robot(drone, Vector3.ZERO, Basis.IDENTITY)
	sim.robots[0].velocity = Vector3(4.0, 0.0, 0.0)
	sim.step([ShipInput.new()])
	var expected: float = 4.0 - drone.acceleration * ShipState.TICK_DT
	if not is_equal_approx(sim.robots[0].velocity.x, expected):
		return "after one tick speed %s, expected %s" % [sim.robots[0].velocity.x, expected]
	for i: int in 60:
		sim.step([ShipInput.new()])
	if sim.robots[0].velocity != Vector3.ZERO:
		return "velocity %s not damped to zero" % sim.robots[0].velocity
	return ""


func test_robot_never_leaves_the_box() -> String:
	var bounds: BoxBounds = _tunnel()
	var sim: Sim = Sim.new(3, 1, bounds)
	sim.spawn_robot(_drone(), Vector3(9.0, 0.0, -20.0), Basis.IDENTITY)
	sim.robots[0].velocity = Vector3(200.0, -200.0, 200.0)
	for i: int in 120:
		sim.step([ShipInput.new()])
		if not bounds.holds(sim.robots[0].position, sim.robots[0].def.radius):
			return "robot left the box at %s on tick %d" % [sim.robots[0].position, sim.tick]
	return ""


func test_same_spawns_and_inputs_give_same_hash_every_tick() -> String:
	var a: Sim = Sim.new(9, 1, _tunnel())
	var b: Sim = Sim.new(9, 1, _tunnel())
	for sim: Sim in [a, b]:
		sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -40.0), Basis.IDENTITY)
		sim.spawn_robot(_drone(), Vector3(3.0, 2.0, -60.0), Basis(Vector3.UP, 1.0))
		sim.robots[1].velocity = Vector3(1.0, -2.0, 3.0)
	var input: ShipInput = ShipInput.new(Vector3i(200, 0, -1000), Vector3i(0, 300, 0))
	for i: int in 300:
		a.step([input])
		b.step([input])
		if a.state_hash() != b.state_hash():
			return "hashes differ at tick %d" % a.tick
	return ""


func test_robot_changes_the_hash() -> String:
	var with_robot: Sim = Sim.new(9, 1)
	var without: Sim = Sim.new(9, 1)
	with_robot.spawn_robot(_drone(), Vector3(0.0, 0.0, -40.0), Basis.IDENTITY)
	if with_robot.state_hash() == without.state_hash():
		return "a sim with a robot hashes like one without"
	with_robot.step([ShipInput.new()])
	without.step([ShipInput.new()])
	if with_robot.state_hash() == without.state_hash():
		return "after a tick a sim with a robot hashes like one without"
	var hurt: Sim = Sim.new(9, 1)
	hurt.spawn_robot(_drone(), Vector3(0.0, 0.0, -40.0), Basis.IDENTITY)
	hurt.step([ShipInput.new()])
	hurt.robots[0].hull -= 1.0
	if hurt.state_hash() == with_robot.state_hash():
		return "hull is not part of the robot hash"
	return ""


func test_no_robots_hashes_exactly_as_before() -> String:
	var sim: Sim = Sim.new(11, 1, _tunnel())
	_fly_reference(sim)
	if sim.projectiles.is_empty():
		return "the reference flight should leave projectiles in flight"
	if sim.state_hash() != REFERENCE_HASH:
		return "hash %d differs from %d recorded on main" % [sim.state_hash(), REFERENCE_HASH]
	return ""
