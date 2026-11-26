extends RefCounted

## The `launch_fade` check (#1396, CRW-2, CMF-1, CMF-3, CMF-8, ARC-3), lane-a's
## file under `acceptance/checks/`. In `suites/m6/ship.json`:
##
##     {"id": "launch_fade", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "launch_fade"]}
##
## After the replay the ship is lost and the end screen's restart pressed, as a
## lost run opens the base (`hub_room`'s `judge_open_room`), with the profile
## and fitting kept in scratch files. The room must fade in and never brighten
## back. Then the pilot takes the launch station and presses its launch row,
## all through the scene's own `apply_controls` and `advance_frame`. From the
## press the cradle ship's engine glow must rise and the launch sound start,
## the room's fade must only rise, and the next level must start on a frame on
## which the view is fully dark; then the mine fades in and the view clears.
## The camera's tracked transform must not change at any frame of it, nor its
## place in the world while the pilot is in the base (CMF-1, CMF-8). It moves
## the run on, so it is the step's last check. How it feels stays human-checked
## in the headset.

const CHECK: String = "launch_fade"
const ROOM_CHECK: GDScript = preload("res://acceptance/checks/hub_room_check.gd")
const PROFILE_FILE: String = "user://meltdown_acceptance_launch_fade_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_launch_fade_fitting.json"
const FRAME: float = 1.0 / 72.0
## Longer than any launch fade file allows for each part (`LaunchFade.RANGES`).
const MAX_SECONDS: float = 7.0
const STICK_DOWN: Vector2 = Vector2(0.0, -1.0)
const STICK_UP: Vector2 = Vector2(0.0, 1.0)
const A: Dictionary = {DestroyedWiring.RESTART_BUTTON: true}


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or hub == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = ROOM_CHECK.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = judge_launch(main, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


## With the hub just opened in the room: waits out the arrival, launches from
## the launch station and judges every frame until the mine has faded in.
static func judge_launch(main: Node, hub: HubWiring, measurements: Dictionary) -> Array:
	var camera: Node3D = main.get_node_or_null("XRRig/Camera") as Node3D
	var launch: HubLaunch = hub.launching
	if camera == null or launch.room_overlay == null or hub.room.ship() == null:
		return [AcceptanceReport.RESULT_FAIL, "the base has no camera, room fade or cradle ship"]
	var tracked: Transform3D = camera.transform
	var problem: String = _arrive(main, launch)
	if problem == "":
		problem = _select_launch(main, hub)
	if problem != "":
		return [AcceptanceReport.RESULT_FAIL, problem]
	var placed: Transform3D = camera.global_transform
	var ended: LocalSession = main.get("session")
	_frame(main, {}, Vector2.ZERO)
	_frame(main, A, Vector2.ZERO)
	var seen: Dictionary = {"glow_peak": 0.0, "glow_before_dark": false, "frames": 0, "last_room_alpha": 0.0}
	while main.get("session") == ended and seen["frames"] < ceili(MAX_SECONDS / FRAME):
		var room_alpha: float = launch.room_overlay.get_alpha()
		if room_alpha < float(seen["last_room_alpha"]):
			return [AcceptanceReport.RESULT_FAIL, "the base brightened during the launch's fade out"]
		var glow: float = hub.room.ship().thrust()
		seen["glow_peak"] = maxf(seen["glow_peak"], glow)
		seen["glow_before_dark"] = seen["glow_before_dark"] or (glow > 0.5 and room_alpha == 0.0)
		seen["last_room_alpha"] = room_alpha
		if not camera.transform.is_equal_approx(tracked) or not camera.global_transform.is_equal_approx(placed):
			return [AcceptanceReport.RESULT_FAIL, "the camera moved in the base during the launch"]
		_frame(main, {}, Vector2.ZERO)
		seen["frames"] += 1
	measurements["launch_seconds"] = snappedf(int(seen["frames"]) * FRAME, 0.01)
	measurements["glow_peak"] = snappedf(seen["glow_peak"], 0.01)
	measurements["launch_sounds"] = launch.sound.played if launch.sound != null else 0
	if main.get("session") == ended or hub.is_open():
		return [AcceptanceReport.RESULT_FAIL, "pressing launch did not leave the base for the level"]
	if not seen["glow_before_dark"] or measurements["launch_sounds"] != 1:
		return [AcceptanceReport.RESULT_FAIL, "the engine glow did not rise with one launch sound before the fade"]
	var dark: float = (main.get("fade_overlay") as FadeOverlay).get_alpha()
	measurements["dark_at_level_start"] = dark
	if dark < 1.0 or launch.room_overlay.get_alpha() < 1.0:
		return [AcceptanceReport.RESULT_FAIL, "the level started before the view was dark (%.2f)" % dark]
	return _fade_in(main, camera, tracked, measurements)


## The room fades in after opening and never brightens back.
static func _arrive(main: Node, launch: HubLaunch) -> String:
	var last: float = launch.room_overlay.get_alpha()
	if last <= 0.0:
		return "the base did not fade in on arriving"
	for i: int in ceili(MAX_SECONDS / FRAME):
		_frame(main, {}, Vector2.ZERO)
		var now: float = launch.room_overlay.get_alpha()
		if now > last:
			return "the base darkened again while fading in"
		last = now
		if now == 0.0:
			return ""
	return "the base never finished fading in"


## Takes the launch station and moves to its launch row, without pressing it.
static func _select_launch(main: Node, hub: HubWiring) -> String:
	if hub.stations == null or not AcceptanceCraftAndFitCheck.choose_station(main, hub, "launch"):
		return "the launch station cannot be taken into use"
	for i: int in AcceptanceCraftAndFitCheck.MAX_MOVES:
		var before: int = hub.text.selected_line()
		_tap(main, STICK_UP)
		if hub.text.selected_line() == before:
			break
	for i: int in AcceptanceCraftAndFitCheck.MAX_MOVES:
		if hub.text.selected() == {"action": HubText.ACTION_LAUNCH}:
			return ""
		var line: int = hub.text.selected_line()
		_tap(main, STICK_DOWN)
		if hub.text.selected_line() == line:
			break
	return "the launch station has no launch row"


## The mine fades in from full dark to clear and never darkens back, with the
## camera's tracked transform unchanged.
static func _fade_in(main: Node, camera: Node3D, tracked: Transform3D, measurements: Dictionary) -> Array:
	var fade: FadeOverlay = main.get("fade_overlay") as FadeOverlay
	var last: float = fade.get_alpha()
	for i: int in ceili(MAX_SECONDS / FRAME):
		_frame(main, {}, Vector2.ZERO)
		if not camera.transform.is_equal_approx(tracked):
			return [AcceptanceReport.RESULT_FAIL, "the camera's tracked transform moved during the fade in"]
		if fade.get_alpha() > last:
			return [AcceptanceReport.RESULT_FAIL, "the mine darkened again while fading in"]
		last = fade.get_alpha()
		if last == 0.0:
			measurements["fade_in_seconds"] = snappedf((i + 1) * FRAME, 0.01)
			return [AcceptanceReport.RESULT_PASS, "glow and sound, dark after %.2f s, the level loaded dark and faded in over %.2f s; camera still" %
				[measurements["launch_seconds"], measurements["fade_in_seconds"]]]
	return [AcceptanceReport.RESULT_FAIL, "the mine never finished fading in after the launch"]


static func _tap(main: Node, stick: Vector2) -> void:
	_frame(main, {}, Vector2.ZERO)
	_frame(main, {}, stick)


static func _frame(main: Node, buttons: Dictionary, stick: Vector2) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	values["right_stick"] = stick
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
