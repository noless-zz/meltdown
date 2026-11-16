extends RefCounted

## The main scene meets robots from the shipped spawn file and shows the
## ship's shield and hull (#228, CMB-2, CMB-3, MP-2, ARC-2).

const SHIP_FILE: String = "res://data/ships/default_ship.json"
const SPAWN_FILE: String = "res://data/levels/test_tunnel_robots.json"
const ROBOTS_DIR: String = "res://data/robots"
## How far ahead of the start (along -z) every shipped robot must be. The test
## tunnel ends 28 m ahead (`TestTunnel.LENGTH` less `START_Z`), so the spawns
## sit in its far half rather than the 30 m the issue suggested.
const MIN_AHEAD_M: float = 12.0


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, frames: int, input: ShipInput) -> void:
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", 1.0 / 90.0)


func _shipped_ids() -> Array[String]:
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids


func test_main_scene_spawns_one_of_each_robot_type() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var session: LocalSession = main.get("session")
	var robots: Array[RobotState] = session.sim.robots.duplicate()
	var recorded: int = session.replay.robots.size()
	var tick: int = session.sim.tick
	main.free()
	if tick != 0:
		return "the session ran %d ticks before the scene started" % tick
	var ids: Array[String] = []
	for robot: RobotState in robots:
		ids.append(robot.def.id)
	ids.sort()
	if ids != _shipped_ids():
		return "spawned %s, expected one of each of %s" % [ids, _shipped_ids()]
	if recorded != robots.size():
		return "the replay records %d robots for %d spawned" % [recorded, robots.size()]
	var walls: BoxBounds = TestTunnel.interior_box(Vector3(0.0, -1.0, 0.0))
	for robot: RobotState in robots:
		if robot.position.z > -MIN_AHEAD_M:
			return "%s spawns %s m ahead, under %s" % [robot.def.id, -robot.position.z, MIN_AHEAD_M]
		var radius: Vector3 = Vector3.ONE * robot.def.radius
		var low: Vector3 = walls.min_corner + radius
		var high: Vector3 = walls.max_corner - radius
		if robot.position.clamp(low, high) != robot.position:
			return "%s spawns at %s, through the tunnel's walls" % [robot.def.id, robot.position]
		if robot.forward().dot(Vector3.BACK) < 0.999:
			return "%s faces %s, not back towards the start" % [robot.def.id, robot.forward()]
	return ""


func test_the_view_shows_six_robot_meshes() -> String:
	var main: Node = _main()
	_fly(main, 9, ShipInput.new())
	var view: RobotView = main.get_node_or_null(RobotView.NODE_NAME) as RobotView
	var found: bool = view != null and view.get_parent() == main
	var shown: int = 0
	var placed: bool = true
	if found:
		var robots: Array[RobotState] = (main.get("session") as LocalSession).current_robots()
		for index: int in view.node_count():
			var node: MeshInstance3D = view.node(index)
			if node.visible:
				shown += 1
				placed = placed and node.position.distance_to(robots[index].position) < 0.5
	main.free()
	if not found:
		return "no RobotView directly under the main scene"
	if shown != 6:
		return "%d robot meshes shown, expected 6" % shown
	if not placed:
		return "a robot mesh is not where its robot is"
	return ""


func test_the_shield_bar_drops_after_a_wall_hit() -> String:
	var main: Node = _main()
	var panel: StatusPanel = main.get("status_panel")
	_fly(main, 1, ShipInput.new())
	var before: float = panel.shield_bar_scale()
	# Backwards: the start wall is 1 m behind the ship's surface.
	_fly(main, 60, ShipInput.new(Vector3i(0, 0, ShipInput.SCALE)))
	var after: float = panel.shield_bar_scale()
	var shield: float = (main.get("session") as LocalSession).current_ship().shield
	main.free()
	if before != 1.0:
		return "the shield bar starts at %s, not full" % before
	if shield >= 50.0:
		return "the ship's shield is still full after backing into the wall"
	if after >= before or absf(after - shield / 50.0) > 1e-4:
		return "the shield bar went from %s to %s for a shield of %s" % [before, after, shield]
	return ""


func test_showing_robots_leaves_the_simulation_alone() -> String:
	var main: Node = _main()
	_fly(main, 30, ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE)))
	var session: LocalSession = main.get("session")
	var hash_before: int = session.sim.state_hash()
	var copies: Array[RobotState] = session.current_robots()
	copies[0].position += Vector3(3.0, 0.0, 0.0)
	copies[0].hull = 0.0
	main.call("advance_frame", 0.0)
	var hash_after: int = session.sim.state_hash()
	var same: bool = is_same(copies[0], session.sim.robots[0])
	main.free()
	if same:
		return "current_robots() holds the simulation's robot"
	if hash_before != hash_after:
		return "changing a copy or drawing the robots changed the simulation"
	return ""


func test_a_replay_of_120_ticks_with_robots_ends_on_the_session_hash() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(ShipInput.new(Vector3i(200, 0, -ShipInput.SCALE), Vector3i(0, 150, 0), false, false, true))
	var session: LocalSession = LocalSession.new(9, source, TestTunnel.interior_box(Vector3(0.0, -1.0, 0.0)),
		LocalSession.load_tuning(SHIP_FILE), LocalSession.load_spawns(SPAWN_FILE))
	for i: int in 120:
		session.advance(1.0 / 60.0)
	if session.sim.tick != 120:
		return "120 frames ran %d ticks" % session.sim.tick
	if session.sim.robots.is_empty():
		return "no robots in the session"
	var reread: Replay = Replay.from_text(session.replay.to_text())
	if reread.error != "":
		return "the saved replay does not read back: %s" % reread.error
	var replayed: Sim = reread.run()
	if replayed == null:
		return reread.run_error
	if replayed.state_hash() != session.sim.state_hash():
		return "the replay ends on %d, the session on %d" % [replayed.state_hash(), session.sim.state_hash()]
	var without: Replay = Replay.from_text(session.replay.to_text())
	without.robots.clear()
	if without.run().state_hash() == session.sim.state_hash():
		return "the hash does not change without the robots"
	return ""


func test_a_bad_spawn_file_starts_with_no_robots() -> String:
	if not LocalSession.load_spawns("res://data/levels/no_such_file.json").is_empty():
		return "a missing spawn file gave robots"
	var spawns: Array[RobotSpawn] = LocalSession.load_spawns(SPAWN_FILE, "res://data/weapons/")
	if not spawns.is_empty():
		return "a spawn file whose robot types are missing gave %d robots" % spawns.size()
	return ""
