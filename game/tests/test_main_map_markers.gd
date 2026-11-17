extends RefCounted

## The map's exit and reactor markers in the main scene (#380, MAP-1, RUN-2,
## RUN-3, MP-2): the exit sits where the ship starts, and the reactor shows
## only once the ship has been in a box that holds the reactor's centre.
## The state hash with and without the wiring is compared in
## `test_main_map.gd`, which now runs the marker code too.

const FRAME: float = 1.0 / 90.0
## G2's start room and the shaft down from its far end overlap for z in -40..-36.
const SHAFT_BOX: int = 1
const INTO_SHAFT_Z: float = -38.0
## G2's reactor room, the only box that holds the level's reactor.
const REACTOR_BOX: int = 4
## Inside the shaft but outside the start room, so it is known only once the
## ship has flown into the shaft. Flying to G2's real reactor takes the bot.
const SHAFT_REACTOR_MM: Vector3i = Vector3i(0, -20000, -42000)


func _main(level_name: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if level_name != "":
		main.call("use_level", LevelSwitch.path_for(level_name))
	main.call("_ready")
	return main


func _forward() -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE))


## Flies forward until the ship is in G2's shaft; returns the reactor marker's
## visibility at tick 0 and after, and the ship's final z.
func _fly_into_shaft(main: Node) -> Dictionary:
	var session: LocalSession = main.get("session")
	var hologram: MapHologram = (main.get("map") as MapWiring).hologram
	main.call("advance_frame", 0.0)
	var at_start: bool = hologram.reactor_marker_shown()
	(main.get("input_source") as LatestInputSource).set_input(_forward())
	var frames: int = 0
	while session.current_ship().position.z > INTO_SHAFT_Z and frames < 900:
		main.call("advance_frame", FRAME)
		frames += 1
	return {"at_start": at_start, "after": hologram.reactor_marker_shown(),
		"exit": hologram.exit_marker_shown(), "z": session.current_ship().position.z}


func test_g2_exit_marker_sits_at_the_fitted_start() -> String:
	var main: Node = _main("g2")
	main.call("advance_frame", 0.0)
	var hologram: MapHologram = (main.get("map") as MapWiring).hologram
	var shown: bool = hologram.exit_marker_shown()
	var exit_at: Vector3 = hologram.exit_marker_position()
	var ship_at: Vector3 = hologram.marker_position()
	main.free()
	if not shown:
		return "the exit marker is hidden at tick 0"
	# At tick 0 the ship is at its start, so its marker is the fitted start.
	if not exit_at.is_equal_approx(ship_at):
		return "the exit marker is at %s, the ship's start at %s" % [exit_at, ship_at]
	return ""


func test_the_exit_follows_the_replay_start_line() -> String:
	var main: Node = _main("g2")
	var session: LocalSession = main.get("session")
	var start: Vector3 = Vector3(2.0, 1.0, -5.0)
	session.replay.set_start_pose(0, start, Vector3(0.0, 0.0, -1.0))
	main.call("advance_frame", 0.0)
	var hologram: MapHologram = (main.get("map") as MapWiring).hologram
	var fit: Transform3D = hologram.get("_fit")
	var exit_at: Vector3 = hologram.exit_marker_position()
	main.free()
	if not exit_at.is_equal_approx(fit * start):
		return "the exit marker is at %s, the fitted start line at %s" % [exit_at, fit * start]
	return ""


func test_g2_reactor_is_known_only_through_its_own_box() -> String:
	var main: Node = _main("g2")
	main.call("advance_frame", 0.0)
	var wiring: MapWiring = main.get("map")
	var boxes: Array[int] = wiring.get("_reactor_boxes")
	var shown: bool = wiring.hologram.reactor_marker_shown()
	main.free()
	if boxes != [REACTOR_BOX]:
		return "G2's reactor is in boxes %s, expected [%d]" % [boxes, REACTOR_BOX]
	if shown:
		return "G2's reactor is marked before its box was explored"
	return ""


func test_the_reactor_shows_once_the_ship_flies_into_its_box() -> String:
	var main: Node = _main("g2")
	var session: LocalSession = main.get("session")
	var reactor: ReactorState = session.replay.reactor.fresh_copy()
	reactor.position_mm = SHAFT_REACTOR_MM
	session.replay.reactor = reactor
	var seen: Dictionary = _fly_into_shaft(main)
	var explored: Array[int] = (main.get("map") as MapWiring).explored.explored()
	var hologram: MapHologram = (main.get("map") as MapWiring).hologram
	var fit: Transform3D = hologram.get("_fit")
	var reactor_at: Vector3 = hologram.reactor_marker_position()
	main.free()
	var want: Vector3 = fit * (Vector3(SHAFT_REACTOR_MM) / float(RobotSpawn.SCALE))
	if float(seen["z"]) > INTO_SHAFT_Z or not explored.has(SHAFT_BOX):
		return "the ship only reached z %.1f, explored %s" % [seen["z"], explored]
	if seen["at_start"]:
		return "the reactor is marked at tick 0"
	if not seen["after"]:
		return "the reactor is not marked after flying into its box"
	if not reactor_at.is_equal_approx(want):
		return "the reactor marker is at %s, the fitted reactor at %s" % [reactor_at, want]
	return ""


func test_without_a_reactor_only_the_exit_shows() -> String:
	var main: Node = _main("g2")
	(main.get("session") as LocalSession).replay.reactor = null
	var seen: Dictionary = _fly_into_shaft(main)
	main.free()
	if float(seen["z"]) > INTO_SHAFT_Z:
		return "the ship only reached z %.1f" % seen["z"]
	if not seen["exit"]:
		return "the exit marker is hidden"
	if seen["at_start"] or seen["after"]:
		return "a session without a reactor marks one"
	return ""


func test_the_test_tunnel_shows_the_exit_only() -> String:
	var main: Node = _main()
	main.call("advance_frame", 0.0)
	(main.get("input_source") as LatestInputSource).set_input(_forward())
	for frame: int in 60:
		main.call("advance_frame", FRAME)
	var hologram: MapHologram = (main.get("map") as MapWiring).hologram
	var exit_shown: bool = hologram.exit_marker_shown()
	var reactor_shown: bool = hologram.reactor_marker_shown()
	var reactor: ReactorState = (main.get("session") as LocalSession).replay.reactor
	main.free()
	if reactor != null:
		return "the test tunnel has a reactor"
	if not exit_shown:
		return "the tunnel's exit marker is hidden"
	if reactor_shown:
		return "the tunnel marks a reactor"
	return ""
