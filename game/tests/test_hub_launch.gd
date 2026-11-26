extends RefCounted

## Leaving the home base and arriving at it (#1396, CRW-2, CMF-1, CMF-3,
## CMF-8, ARC-3, MP-2): the room gets a fade quad on its own layer, the launch
## glows the cradle ship and sounds once, the fade's colour is the look's, and
## in the main scene the launch row runs the unchanged launch only once the
## view is dark, ignores presses meanwhile, holds the ship while the mine
## fades in, and a resume fades the mine in too.

const FRAME: float = 1.0 / 72.0
const PROFILE_PATH: String = "user://t1396_profile.json"
const FITTING_PATH: String = "user://t1396_fitting.json"
const ROOM_CHECK: GDScript = preload("res://acceptance/checks/hub_room_check.gd")


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


## A camera carrying the scene's fade quad, as `RigViews.add_fade_overlay` hangs it.
func _camera() -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.add_child(FadeOverlay.new())
	return camera


func test_the_room_fade_draws_on_the_room_layer_only() -> String:
	var camera: Camera3D = _camera()
	var room: HubRoom = HubRoom.new()
	var launch: HubLaunch = HubLaunch.new()
	launch.attach(camera, room)
	launch.attach(camera, room)
	var problem: String = ""
	var quads: int = 0
	for child: Node in camera.get_children():
		quads += 1 if child is FadeOverlay else 0
	if launch.room_overlay == null or launch.room_overlay.layers != HubRoom.LAYER_BIT:
		problem = "the room's fade quad is not on the room's layer alone"
	elif quads != 2 or launch.view_overlay == null or launch.view_overlay.layers == HubRoom.LAYER_BIT:
		problem = "expected the scene's quad and one room quad on the camera, found %d" % quads
	elif launch.sound == null or launch.sound.get_parent() != room.ship():
		problem = "the launch sound is not at the cradle ship"
	camera.free()
	room.free()
	return problem


func test_a_launch_glows_the_cradle_ship_and_sounds_once() -> String:
	var room: HubRoom = HubRoom.new()
	var launch: HubLaunch = HubLaunch.new()
	launch.attach(null, room)
	launch.sound.enabled = false
	var problem: String = ""
	if not launch.start() or launch.start():
		problem = "a launch did not start, or a second press started another"
	launch.advance(launch.fade.glow_seconds * 0.5)
	if problem == "" and absf(room.ship().thrust() - 0.5) > 0.01:
		problem = "half way through the glow the engine is at %.2f" % room.ship().thrust()
	launch.advance(launch.fade.glow_seconds * 0.5)
	if problem == "" and (room.ship().thrust() != 1.0 or launch.sound.played != 1):
		problem = "the glow ended at %.2f with %d sounds" % [room.ship().thrust(), launch.sound.played]
	launch.advance(launch.fade.fade_out_seconds + launch.fade.fade_in_seconds + 0.1)
	launch.arrive()
	if problem == "" and room.ship().thrust() != 0.0:
		problem = "arriving back the engine is not at idle"
	room.free()
	return problem


func test_the_fade_shows_the_look_colour_and_the_scene_quad_goes_back_to_black() -> String:
	var camera: Camera3D = _camera()
	var launch: HubLaunch = HubLaunch.new()
	launch.fade = LaunchFade.new({"glow_seconds": 0.0, "fade_out_seconds": 0.5, "fade_in_seconds": 0.5,
		"color": Color(0.1, 0.0, 0.2)})
	launch.attach(camera, null)
	launch.start()
	launch.advance(0.25)
	var problem: String = ""
	if not launch.room_overlay.get_color().is_equal_approx(Color(0.1, 0.0, 0.2)) \
			or absf(launch.room_overlay.get_alpha() - 0.5) > 0.01:
		problem = "the room fades to %s at %.2f" % [launch.room_overlay.get_color(), launch.room_overlay.get_alpha()]
	elif not launch.view_overlay.get_color().is_equal_approx(Color(0.1, 0.0, 0.2)):
		problem = "the scene's quad does not show the launch colour while it fades"
	launch.advance(1.0)  # Due: dark, the fade in begins.
	launch.advance(1.0)
	if problem == "" and (launch.view_overlay.get_color() != Color.BLACK or launch.alpha() != 0.0):
		problem = "after the fade the scene's quad is %s, not black" % launch.view_overlay.get_color()
	camera.free()
	return problem


func _run_main() -> Node:
	_clean()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var level_start: LevelStart = main.get("level_start")
	var run: RunWiring = RunWiring.new(12345, ProfileStore.new(PROFILE_PATH), func() -> int: return 77,
		"{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}", false)
	run.ship.fittings = FittingStore.new(FITTING_PATH)
	level_start.run = run
	level_start.source = run.level_source()
	(main.get("destroyed") as DestroyedWiring).escape.run = run
	main.call("restart_level")
	return main


func _frame(main: Node, buttons: Dictionary = {}) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


func test_the_launch_leaves_only_once_dark_and_holds_the_ship_while_the_mine_fades_in() -> String:
	var main: Node = _run_main()
	var result: String = _check_launch(main)
	main.free()
	_clean()
	return result


func _check_launch(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var verdict: Array = ROOM_CHECK.judge_open_room(main, hub, {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "opening: %s" % verdict[1]
	var ended: LocalSession = main.get("session")
	hub.launching.start()
	var frames: int = 0
	while main.get("session") == ended and frames < 200:
		if not hub.is_open():
			return "the hub closed before the launch was due"
		_frame(main, {} if frames % 2 == 0 else {DestroyedWiring.RESTART_BUTTON: true})  # Presses are ignored.
		frames += 1
	var due_after: float = frames * FRAME
	var want: float = hub.launching.fade.glow_seconds + hub.launching.fade.fade_out_seconds
	if main.get("session") == ended or absf(due_after - want) > 2.0 * FRAME:
		return "the level started after %.2f s, expected %.2f s" % [due_after, want]
	var fade: FadeOverlay = main.get("fade_overlay")
	if hub.is_open() or fade.get_alpha() != 1.0:
		return "the level did not start behind a full fade (alpha %.2f)" % fade.get_alpha()
	if (main.get("destroyed") as DestroyedWiring).fade_alpha() != 0.0:
		return "the end screen's fade still runs under the launch's"
	_frame(main)
	var held: bool = ShipHold.is_held(main.get("dev_menu"), main.get("flight_test"), main.get("session"),
		main.get("destroyed")) or hub.alpha() > 0.0  # As `main.gd` holds it.
	if fade.get_alpha() <= 0.0 or fade.get_alpha() >= 1.0 or not held:
		return "after a frame the mine is not fading in with the ship held (alpha %.2f)" % fade.get_alpha()
	for i: int in ceili(hub.launching.fade.fade_in_seconds / FRAME) + 1:
		_frame(main)
	if fade.get_alpha() != 0.0 or hub.alpha() != 0.0:
		return "the mine did not clear after the fade in (alpha %.2f)" % fade.get_alpha()
	return ""


func test_a_resume_fades_the_mine_in() -> String:
	var hub: HubWiring = HubWiring.new()
	var problem: String = ""
	hub.launching.left()
	if hub.alpha() != 1.0:
		problem = "leaving by a resume does not start dark"
	hub.update(false, Transform3D.IDENTITY, hub.launching.fade.fade_in_seconds * 0.5)
	if problem == "" and absf(hub.alpha() - 0.5) > 0.01:
		problem = "a closed hub did not run the fade in (alpha %.2f)" % hub.alpha()
	hub.update(true, Transform3D.IDENTITY, 10.0)
	if problem == "" and absf(hub.alpha() - 0.5) > 0.01:
		problem = "the fade in ran while paused"
	return problem
