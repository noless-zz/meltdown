extends RefCounted

## The main scene flies the G2 level with `--level=g2` and the test tunnel
## without it (#291, GEN-5, CMB-3, MP-2, ARC-4). Scenes are instantiated
## outside the tree, so `_ready` does not run; the tests call `use_level` as
## `_ready` does with the switch's path.

const G2_FILE: String = "res://data/levels/g2_level.json"
const SCRATCH_DIR: String = "user://test_main_level"
const ROBOT_TYPES: Array[String] = ["drone", "glider", "hauler", "needler", "skimmer", "warden"]
const FLIGHT_TICKS: int = 90


func _main() -> Node:
	return (load("res://main.tscn") as PackedScene).instantiate()


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE))


## Writes `text` to a scratch level file and returns its path.
func _scratch_level(file_name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR.path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_switch_reads_the_argument_then_the_intent_extra() -> String:
	var none: PackedStringArray = PackedStringArray()
	var cases: Array[Array] = [
		[none, "", ""],
		[none, " g2 ", "g2"],
		[PackedStringArray(["--level=g2"]), "", "g2"],
		[PackedStringArray(["--level=g1", "--level=g2"]), "", "g2"],
		[PackedStringArray(["--level=g2"]), "other", "g2"],
		[PackedStringArray(["--acceptance=all"]), "", ""],
	]
	for case: Array in cases:
		var got: String = LevelSwitch.requested(case[0], case[1])
		if got != case[2]:
			return "args %s, intent \"%s\": got \"%s\", expected \"%s\"" % [case[0], case[1], got, case[2]]
	return ""


func test_a_name_picks_a_file_in_the_levels_folder_only() -> String:
	if LevelSwitch.path_for("g2") != G2_FILE:
		return "g2 maps to %s" % LevelSwitch.path_for("g2")
	for bad: String in ["", "../ships/default_ship", "G2", "g2.json", "res://x", "g 2"]:
		if LevelSwitch.path_for(bad) != "":
			return "\"%s\" maps to %s" % [bad, LevelSwitch.path_for(bad)]
	# The test runner is started without the switch.
	if LevelSwitch.requested_path() != "":
		return "a run without --level asks for %s" % LevelSwitch.requested_path()
	return ""


func test_g2_session_has_the_level_walls_start_and_robots() -> String:
	var main: Node = _main()
	var flown: bool = main.call("use_level", LevelSwitch.path_for("g2"))
	var session: LocalSession = main.get("session")
	var level: LevelDef = _g2()
	var problem: String = ""
	if not flown:
		problem = "use_level refused the G2 file"
	elif session.sim.walls == null or session.sim.walls.boxes.size() != 6:
		problem = "session walls are not the level's six boxes"
	elif session.replay.box_mins_mm.size() != 6:
		problem = "the replay records %d boxes" % session.replay.box_mins_mm.size()
	if problem == "":
		for index: int in 6:
			var want: BoxBounds = level.union.boxes[index]
			var got: BoxBounds = session.sim.walls.boxes[index]
			if not got.min_corner.is_equal_approx(want.min_corner) \
					or not got.max_corner.is_equal_approx(want.max_corner):
				problem = "box %d is %s..%s, level says %s..%s" % [index, got.min_corner,
					got.max_corner, want.min_corner, want.max_corner]
				break
	var ship: ShipState = session.current_ship()
	if problem == "" and not ship.position.is_equal_approx(level.start_position()):
		problem = "ship starts at %s, level says %s" % [ship.position, level.start_position()]
	var forward: Vector3 = -ship.orientation.z
	if problem == "" and not forward.is_equal_approx(level.start_facing()):
		problem = "ship faces %s, level says %s" % [forward, level.start_facing()]
	if problem == "":
		var ids: Array[String] = []
		for robot: RobotState in session.sim.robots:
			ids.append(robot.def.id)
			if robot.weapon == null:
				problem = "%s spawned unarmed" % robot.def.id
		ids.sort()
		if problem == "" and ids != ROBOT_TYPES:
			problem = "robots %s, expected one of each of %s" % [ids, ROBOT_TYPES]
	main.free()
	return problem


func test_g2_replaces_the_tunnel_with_the_level_drawing() -> String:
	var main: Node = _main()
	main.call("use_level", G2_FILE)
	var tunnel_gone: bool = main.get_node_or_null("TestTunnel") == null
	# Read before `main.free()`, which frees the view with it.
	var view: LevelView = main.get_node_or_null(LevelView.NODE_NAME) as LevelView
	var has_view: bool = view != null
	var quads: int = view.quads().size() if has_view else 0
	var rig_ok: bool = main.get_node_or_null("XRRig") != null
	main.free()
	if not tunnel_gone:
		return "the test tunnel is still drawn"
	if not has_view:
		return "no LevelView in the main scene"
	if quads == 0:
		return "the level view drew no walls"
	if not rig_ok:
		return "the rig went missing"
	return ""


func test_g2_rig_follows_the_ship_from_the_start() -> String:
	var main: Node = _main()
	main.call("use_level", G2_FILE)
	main.call("place_rig")
	var session: LocalSession = main.get("session")
	var rig: Node3D = main.get_node("XRRig") as Node3D
	var distance: float = rig.position.distance_to(session.current_ship().position)
	main.free()
	# The rig sits at the ship's centre minus the head offset, under a metre away.
	if distance > 2.0:
		return "rig is %s m from the ship at the start" % distance
	return ""


func test_a_short_g2_flight_replays_to_the_session_hash() -> String:
	var main: Node = _main()
	main.call("use_level", G2_FILE)
	var session: LocalSession = main.get("session")
	var source: LatestInputSource = main.get("input_source")
	# Forward with a slow yaw and the primary held, so walls, robots and shots
	# all get a part in the hash.
	var input: ShipInput = ShipInput.from_floats(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.2, 0.0))
	input.fire_primary = true
	source.set_input(input)
	for frame: int in FLIGHT_TICKS:
		main.call("advance_frame", ShipState.TICK_DT)
	var live_hash: int = session.sim.state_hash()
	var ticks: int = session.sim.tick
	var text: String = session.replay.to_text()
	main.free()
	var replay: Replay = Replay.from_text(text)
	if replay.error != "":
		return "saved replay does not read back: %s" % replay.error
	var sim: Sim = replay.run()
	if sim == null:
		return "replay did not run: %s" % replay.run_error
	if ticks < FLIGHT_TICKS - 2:
		return "only %d ticks flown" % ticks
	if sim.walls == null or sim.walls.boxes.size() != 6:
		return "the replay does not fly the level's six boxes"
	if sim.state_hash() != live_hash:
		return "replay ends on %d, the session on %d" % [sim.state_hash(), live_hash]
	return ""


func test_without_the_switch_the_tunnel_stays() -> String:
	var main: Node = _main()
	var before: LocalSession = main.get("session")
	var flown: bool = main.call("use_level", "")
	var after: LocalSession = main.get("session")
	var tunnel_ok: bool = main.get_node_or_null("TestTunnel") != null
	var no_view: bool = main.get_node_or_null(LevelView.NODE_NAME) == null
	var boxes: int = after.sim.walls.boxes.size() if after.sim.walls != null else 0
	main.free()
	if flown or before != after:
		return "an empty path replaced the session"
	if not tunnel_ok or not no_view:
		return "the test tunnel was replaced without the switch"
	if boxes != 1:
		return "the tunnel session has %d boxes" % boxes
	return ""


func test_a_broken_level_file_falls_back_to_the_tunnel() -> String:
	var paths: Array[String] = [
		_scratch_level("broken_level.json", "{\"boxes\": ["),
		_scratch_level("cut_level.json", JSON.stringify({
			"boxes": [{"min": [-5, -5, -5], "max": [5, 5, 5]}, {"min": [50, 50, 50], "max": [60, 60, 60]}],
			"start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []})),
		SCRATCH_DIR.path_join("missing_level.json"),
	]
	for path: String in paths:
		var main: Node = _main()
		var before: LocalSession = main.get("session")
		var flown: bool = main.call("use_level", path)
		var same: bool = before == main.get("session")
		var tunnel_ok: bool = main.get_node_or_null("TestTunnel") != null
		main.free()
		if flown or not same:
			return "%s replaced the session" % path
		if not tunnel_ok:
			return "%s removed the test tunnel" % path
	return ""
