extends RefCounted

## The test tunnel's walls reach the simulation in the main scene (FLT-3,
## MP-2, CMF-8): one box for drawing and colliding, the ship starts inside it,
## and full thrust down the tunnel bounces off the far end without escaping.

const FRAME_RATE: int = 90


func _instantiate(path: String) -> Node:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


## Inner faces of the drawn shell: each wall's centre moved half a wall
## thickness towards the inside.
func _drawn_interior(tunnel: Node) -> BoxBounds:
	var shell: Node = tunnel.get_node("Shell")
	var left: MeshInstance3D = shell.get_node("LeftWall") as MeshInstance3D
	var right: MeshInstance3D = shell.get_node("RightWall") as MeshInstance3D
	var floor_box: MeshInstance3D = shell.get_node("Floor") as MeshInstance3D
	var ceiling: MeshInstance3D = shell.get_node("Ceiling") as MeshInstance3D
	var far_end: MeshInstance3D = shell.get_node("FarEnd") as MeshInstance3D
	var near_end: MeshInstance3D = shell.get_node("NearEnd") as MeshInstance3D
	var low: Vector3 = Vector3(
		left.position.x + _size(left).x / 2.0,
		floor_box.position.y + _size(floor_box).y / 2.0,
		far_end.position.z + _size(far_end).z / 2.0)
	var high: Vector3 = Vector3(
		right.position.x - _size(right).x / 2.0,
		ceiling.position.y - _size(ceiling).y / 2.0,
		near_end.position.z - _size(near_end).z / 2.0)
	return BoxBounds.new(low, high)


func _size(wall: MeshInstance3D) -> Vector3:
	return (wall.mesh as BoxMesh).size


func test_box_matches_the_drawn_walls_minus_thickness() -> String:
	var tunnel: Node = _instantiate("res://view/test_tunnel.tscn")
	if tunnel == null:
		return "test_tunnel.tscn did not load"
	tunnel.call("build")
	var drawn: BoxBounds = _drawn_interior(tunnel)
	tunnel.free()
	var box: BoxBounds = TestTunnel.interior_box()
	if not box.min_corner.is_equal_approx(drawn.min_corner):
		return "box min corner %s, drawn walls give %s" % [box.min_corner, drawn.min_corner]
	if not box.max_corner.is_equal_approx(drawn.max_corner):
		return "box max corner %s, drawn walls give %s" % [box.max_corner, drawn.max_corner]
	var size: Vector3 = box.max_corner - box.min_corner
	if not size.is_equal_approx(Vector3(TestTunnel.WIDTH, TestTunnel.HEIGHT, TestTunnel.LENGTH)):
		return "box size %s is not the tunnel's inside" % size
	return ""


func test_offset_moves_the_box_with_the_tunnel() -> String:
	var offset: Vector3 = Vector3(0.5, -1.0, 3.0)
	var plain: BoxBounds = TestTunnel.interior_box()
	var moved: BoxBounds = TestTunnel.interior_box(offset)
	if not moved.min_corner.is_equal_approx(plain.min_corner + offset) \
			or not moved.max_corner.is_equal_approx(plain.max_corner + offset):
		return "offset box %s..%s" % [moved.min_corner, moved.max_corner]
	return ""


func test_main_session_flies_inside_the_drawn_tunnel() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	main.call("place_tunnel")
	main.call("place_rig")
	var tunnel_position: Vector3 = (main.get_node("TestTunnel") as Node3D).position
	var rig_position: Vector3 = (main.get_node("XRRig") as Node3D).position
	var session: LocalSession = main.get("session")
	var ship: ShipState = session.current_ship()
	var walls: BoxBounds = session.sim.bounds
	main.free()
	if walls == null:
		return "the main scene's simulation has no walls"
	var expected: BoxBounds = TestTunnel.interior_box(tunnel_position)
	if not walls.min_corner.is_equal_approx(expected.min_corner) \
			or not walls.max_corner.is_equal_approx(expected.max_corner):
		return "sim walls %s..%s, drawn tunnel interior %s..%s" % [
			walls.min_corner, walls.max_corner, expected.min_corner, expected.max_corner]
	if not walls.holds(ship.position, ship.radius):
		return "ship starts at %s, outside the walls" % ship.position
	if not walls.holds(rig_position, ship.radius):
		return "rig starts at %s, outside the walls" % rig_position
	return ""


func test_twenty_seconds_of_full_thrust_stay_inside_and_moving() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	var session: LocalSession = main.get("session")
	# About the walls, not survival: since #601 a ship the tunnel's robots or
	# twenty seconds of wall hits destroy stops, so it gets a hull they cannot.
	session.sim.ships[0].max_hull *= 100.0
	session.sim.ships[0].hull = session.sim.ships[0].max_hull
	(main.get("input_source") as LatestInputSource).set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	# The drawn tunnel, not the session's own walls: a session without walls
	# must fail here too.
	main.call("place_tunnel")
	var walls: BoxBounds = TestTunnel.interior_box((main.get_node("TestTunnel") as Node3D).position)
	var problem: String = ""
	var hit_far_end: bool = false
	for frame: int in FRAME_RATE * 20:
		main.call("advance_frame", 1.0 / FRAME_RATE)
		var ship: ShipState = session.current_ship()
		if not walls.holds(ship.position, ship.radius):
			problem = "frame %d: ship at %s is outside the walls" % [frame, ship.position]
			break
		if frame >= FRAME_RATE and ship.velocity.length() < 0.01:
			problem = "frame %d: ship stopped at %s" % [frame, ship.position]
			break
		if ship.velocity.z > 0.0:
			hit_far_end = true
	var ticks: int = session.sim.tick
	main.free()
	if problem != "":
		return problem
	if ticks != 20 * ShipState.TICK_RATE:
		return "20 seconds of frames ran %d ticks" % ticks
	if not hit_far_end:
		return "the ship never bounced back off the far end"
	return ""


func test_replay_of_a_walled_session_reproduces_it() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(5, source, TestTunnel.interior_box(Vector3(0.0, -1.0, 0.0)))
	source.set_input(ShipInput.new(Vector3i(300, 200, -1000), Vector3i(0, 400, 0), true))
	for frame: int in FRAME_RATE * 5:
		session.advance(1.0 / FRAME_RATE)
	if not session.replay.has_box:
		return "the replay did not record the walls"
	var reloaded: Replay = Replay.from_text(session.replay.to_text())
	var replayed: Sim = reloaded.run()
	if replayed == null:
		return "replay did not run: %s" % reloaded.run_error
	if replayed.state_hash() != session.sim.state_hash():
		return "the saved replay does not reproduce the walled session"
	return ""
