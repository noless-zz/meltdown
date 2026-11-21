extends RefCounted

## The main scene's hologram map (#339, MAP-1, MP-2, CMF-8): it maps the
## session's walls, marks the boxes the ship has been in, rebuilds only when
## that set changes, and never changes the simulation.

const FRAME: float = 1.0 / 90.0
## G2's start room and the shaft down from its far end overlap for z in -40..-36.
const START_BOX: int = 0
const SHAFT_BOX: int = 1
const INTO_SHAFT_Z: float = -38.0


## The main scene with its rig built and `_ready` run, as in play; with
## `level_name`, that level is switched in first, as `--level` does.
func _main(level_name: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if level_name != "":
		main.call("use_level", LevelSwitch.path_for(level_name))
	main.call("_ready")
	return main


func _fly(main: Node, frames: int, input: ShipInput) -> void:
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", FRAME)


func _forward() -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE))


## The problem with the map's lines, or "": they must be exactly the
## wireframe of the explored boxes of the session's walls.
func _lines_problem(main: Node) -> String:
	var wiring: MapWiring = main.get("map")
	var session: LocalSession = main.get("session")
	var want: int = MapWireframe.segments(session.replay.walls(), wiring.explored.explored()).size() / 2
	var got: int = wiring.hologram.segment_count()
	if want == 0 or got != want:
		return "the map draws %d segments, the wireframe of %s has %d" % [got,
			wiring.explored.explored(), want]
	return ""


func test_g2_maps_the_start_box_at_tick_zero() -> String:
	var main: Node = _main("g2")
	main.call("advance_frame", 0.0)
	var session: LocalSession = main.get("session")
	var wiring: MapWiring = main.get("map")
	var tick: int = session.sim.tick
	var explored: Array[int] = wiring.explored.explored() if wiring.explored != null else []
	var problem: String = _lines_problem(main) if explored == [START_BOX] else ""
	var parent: Node = wiring.hologram.get_parent() if wiring.hologram != null else null
	var in_left_hand: bool = parent != null and parent.name == "LeftHand"
	main.free()
	if tick != 0:
		return "a zero frame ran %d ticks" % tick
	if explored != [START_BOX]:
		return "at tick 0 the explored boxes are %s" % [explored]
	if not in_left_hand:
		return "the map is not held in the left hand"
	return problem


func test_flying_into_the_shaft_maps_both_boxes() -> String:
	var main: Node = _main("g2")
	var session: LocalSession = main.get("session")
	var frames: int = 0
	while session.current_ship().position.z > INTO_SHAFT_Z and frames < 900:
		_fly(main, 1, _forward())
		frames += 1
	var z: float = session.current_ship().position.z
	var explored: Array[int] = (main.get("map") as MapWiring).explored.explored()
	var problem: String = _lines_problem(main)
	main.free()
	if z > INTO_SHAFT_Z:
		return "the ship only reached z %.1f in %d frames" % [z, frames]
	if explored != [START_BOX, SHAFT_BOX]:
		return "after flying into the shaft the explored boxes are %s" % [explored]
	return problem


func test_flying_inside_one_box_does_not_rebuild() -> String:
	var main: Node = _main("g2")
	main.call("advance_frame", 0.0)
	var wiring: MapWiring = main.get("map")
	var before: int = wiring.rebuilds
	var marker_before: Vector3 = wiring.hologram.marker_position()
	_fly(main, 30, _forward())
	var session: LocalSession = main.get("session")
	var z: float = session.current_ship().position.z
	var after: int = wiring.rebuilds
	var explored: Array[int] = wiring.explored.explored()
	var marker_moved: bool = not wiring.hologram.marker_position().is_equal_approx(marker_before)
	main.free()
	if z < -30.0 or z > -1.0:
		return "the test flight ended at z %.1f, not well inside the start box" % z
	if explored != [START_BOX]:
		return "flying inside the start box explored %s" % [explored]
	if after != before:
		return "flying inside one box rebuilt the map %d times" % (after - before)
	if not marker_moved:
		return "the ship marker did not move with the ship"
	return ""


func test_the_state_hash_is_the_same_without_the_wiring() -> String:
	var hashes: Array[int] = []
	var attached: Array[bool] = []
	for with_map: bool in [true, false]:
		var main: Node = _main("g2")
		if not with_map:
			var idle: MapWiring = MapWiring.new()
			main.set("map", idle)
		# Hold the map button too, so its reading is part of the run.
		var held: Dictionary = {"buttons": {"left_stick_click": true}}
		for frame: int in 240:
			main.call("apply_controls", held)
			_fly(main, 1, _forward())
		var session: LocalSession = main.get("session")
		hashes.append(session.sim.state_hash())
		attached.append((main.get("map") as MapWiring).hologram != null)
		main.free()
	if attached != [true, false]:
		return "the map was attached %s, expected [true, false]" % [attached]
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the map and %d without" % [hashes[0], hashes[1]]
	return ""


func test_without_a_level_the_test_tunnel_box_is_mapped() -> String:
	var main: Node = _main()
	main.call("advance_frame", 0.0)
	var wiring: MapWiring = main.get("map")
	var session: LocalSession = main.get("session")
	var boxes: int = session.replay.walls().boxes.size()
	var explored: Array[int] = wiring.explored.explored()
	var problem: String = _lines_problem(main)
	main.free()
	if boxes != 1:
		return "the tunnel session has %d boxes" % boxes
	if explored != [0]:
		return "in the tunnel the explored boxes are %s" % [explored]
	return problem


func test_the_wiring_reads_only_session_copies() -> String:
	var text: String = FileAccess.get_file_as_string("res://map_wiring.gd")
	for forbidden: String in ["sim.", "input_source", ".set_input", "hand_input"]:
		if text.contains(forbidden):
			return "map_wiring.gd mentions %s" % forbidden
	return ""
