extends RefCounted

## The base checks wait out the room's arrival fade before a picture (#1425,
## DEV-6, CMF-8, decision record 0005): arriving fades the room in from dark
## (#1396), so a picture taken on the frames after the hub opens is near black.
## `hub_room_check.gd`'s wait flies frames until the room quad is clear, gives
## up naming the fade after the look's `fade_in_seconds` plus a few frames, and
## only reads the fade.

const ROOM_CHECK: GDScript = preload("res://acceptance/checks/hub_room_check.gd")
const FRAME: float = 1.0 / 72.0
const PROFILE_PATH: String = "user://t1425_profile.json"
const FITTING_PATH: String = "user://t1425_fitting.json"


func test_the_wait_flies_frames_until_the_fade_is_clear() -> String:
	var launch: HubLaunch = HubLaunch.new()
	launch.arrive()
	var seen: Array[float] = []
	var fly: Callable = func() -> void:
		seen.append(ROOM_CHECK.room_fade(launch))
		launch.advance(FRAME)
	var problem: String = ROOM_CHECK.wait_until_clear(launch, fly)
	if problem != "":
		return "a fade that clears was refused: %s" % problem
	if ROOM_CHECK.room_fade(launch) != 0.0:
		return "the wait ended with the room still at %.2f" % ROOM_CHECK.room_fade(launch)
	var expected: int = ceili(launch.fade.fade_in_seconds / FRAME)
	if absi(seen.size() - expected) > 1:
		return "flew %d frames for a %.2f s fade, expected about %d" % [seen.size(), launch.fade.fade_in_seconds, expected]
	for shown: float in seen:
		if shown <= 0.0:
			return "a frame was flown after the room was already clear"
	return ""


func test_a_clear_room_is_not_waited_on() -> String:
	var launch: HubLaunch = HubLaunch.new()
	var flown: Array[int] = [0]
	var problem: String = ROOM_CHECK.wait_until_clear(launch, func() -> void: flown[0] += 1)
	if problem != "" or flown[0] != 0:
		return "a clear room was waited on for %d frames: %s" % [flown[0], problem]
	return ""


func test_a_fade_that_never_clears_fails_naming_it_at_the_cap() -> String:
	var launch: HubLaunch = HubLaunch.new()
	launch.arrive()
	var flown: Array[int] = [0]
	var problem: String = ROOM_CHECK.wait_until_clear(launch, func() -> void: flown[0] += 1)
	var cap: int = ceili(launch.fade.fade_in_seconds / FRAME) + ROOM_CHECK.ARRIVAL_SLACK_FRAMES
	if problem == "":
		return "a fade that never clears was accepted"
	if not "arrival fade" in problem or not "fade_in_seconds" in problem:
		return "the failure does not name the fade: %s" % problem
	if flown[0] != cap:
		return "gave up after %d frames, the cap is %d" % [flown[0], cap]
	return ""


func test_in_the_scene_the_room_is_dark_on_opening_and_lit_after_the_wait() -> String:
	var main: Node = _run_main()
	var result: String = _check_scene(main)
	main.free()
	_clean()
	return result


func _check_scene(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var verdict: Array = ROOM_CHECK.judge_open_room(main, hub, {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "opening: %s" % verdict[1]
	if hub.launching.room_overlay == null:
		return "the scene's room has no fade quad"
	var at_open: float = ROOM_CHECK.room_fade(hub.launching)
	if at_open <= 0.5:
		return "the room was already %.2f clear on opening; the wait is not exercised" % at_open
	var profile_before: String = hub.text.model.profile.to_json() if hub.text != null else ""
	var problem: String = ROOM_CHECK.wait_for_arrival(main, hub)
	if problem != "":
		return "the scene's arrival never cleared: %s" % problem
	if hub.launching.room_overlay.get_alpha() != 0.0:
		return "the wait ended with the room quad at %.2f" % hub.launching.room_overlay.get_alpha()
	if not hub.is_open() or not hub.room.visible:
		return "waiting closed the hub or hid the room"
	if hub.text != null and hub.text.model.profile.to_json() != profile_before:
		return "waiting changed the profile"
	return ""


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


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
