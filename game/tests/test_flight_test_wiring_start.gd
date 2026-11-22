extends RefCounted

## The first-launch flight test in the game (CMF-4, CMF-6, CMF-8, ARC-3, #715):
## when it runs, that paused time does not count, and how the answers file is
## read. How answers and the skip hold drive it, that the ship is held while an
## answer is due, and that the result and later switches are saved are in
## `test_flight_test_wiring_answers.gd`, which shares the fixtures below.

const SCRATCH_DIR: String = "user://test_flight_test_wiring"
const FRAME: float = 1.0 / 90.0
const A: String = "right_button_lower"
const B: String = "right_button_upper"
const Y: String = "left_button_upper"
const X: String = "left_button_lower"


static func scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


static func write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func comfort() -> ComfortWiring:
	return ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())


## A wiring begun as `start` with the choice at `choice_path`, applying presets to `p_comfort`.
static func wiring(start: FlightTestWiring.Start, choice_path: String, p_comfort: ComfortWiring) -> FlightTestWiring:
	var wired: FlightTestWiring = FlightTestWiring.new()
	wired.choice_path = choice_path
	wired.begin(start, p_comfort, p_comfort.set_preset)
	return wired


## One frame as `main.gd` runs it: buttons, then the frame's update.
static func frame(wired: FlightTestWiring, buttons: Dictionary = {}, menu: bool = false,
		delta: float = FRAME, paused: bool = false) -> Dictionary:
	var rest: Dictionary = wired.read_buttons(buttons, menu)
	wired.update(delta, paused)
	return rest


## Flies the current segment to its end, then taps `button`.
static func answer_with(wired: FlightTestWiring, button: String) -> void:
	frame(wired, {}, false, 60.0)
	frame(wired, {button: true})
	frame(wired, {})


static func saved(path: String) -> ComfortChoice:
	var choice: ComfortChoice = ComfortChoice.new()
	choice.load_from(path)
	return choice


static func free_panel(wired: FlightTestWiring) -> void:
	if wired.panel != null:
		wired.panel.free()
		wired.panel = null


static func moving() -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, 1000), Vector3i(0, 500, 0), true, false, false)


func test_first_launch_starts_the_test_with_its_first_preset() -> String:
	var c: ComfortWiring = comfort()
	var wired: FlightTestWiring = wiring(FlightTestWiring.Start.TUNNEL, scratch("first.json"), c)
	frame(wired)
	var message: String = ""
	if not wired.running():
		message = "no test on first launch"
	elif c.number != wired.test.current_segment().preset or c.number != 1:
		message = "preset %d during the first segment, expected 1" % c.number
	elif wired.panel == null or not wired.panel.visible:
		message = "the panel does not show"
	elif wired.panel.shown()["main"] != wired.panel.instruction("snap_yaw") \
			or not str(wired.panel.shown()["detail"]).contains("15"):
		message = "panel shows %s" % wired.panel.shown()
	elif FileAccess.file_exists(wired.choice_path):
		message = "the choice was saved before the test ended"
	free_panel(wired)
	return message


func test_a_saved_choice_skips_the_test_and_applies_its_preset() -> String:
	var path: String = scratch("saved.json")
	write(path, "{\"preset\": 3, \"flight_test_done\": true}")
	var c: ComfortWiring = comfort()
	var wired: FlightTestWiring = wiring(FlightTestWiring.Start.TUNNEL, path, c)
	frame(wired)
	if wired.running() or wired.test != null or wired.panel != null:
		return "the test ran although it was done"
	if c.number != 3:
		return "preset %d, the saved choice is 3" % c.number
	return ""


func test_acceptance_and_level_starts_never_run_the_test() -> String:
	if FlightTestWiring.start_for(PackedStringArray(), "m1", "") != FlightTestWiring.Start.OFF:
		return "an acceptance run is not off"
	if FlightTestWiring.start_for(PackedStringArray(["--comfort-preset=4"]), "", "") != FlightTestWiring.Start.OFF:
		return "an explicit preset is not off"
	if FlightTestWiring.start_for(PackedStringArray(), "", "res://data/levels/a_level.json") != FlightTestWiring.Start.SAVED:
		return "a level start is not the saved preset"
	if FlightTestWiring.start_for(PackedStringArray(), "", "seed:42") != FlightTestWiring.Start.SAVED:
		return "a seed start is not the saved preset"
	if FlightTestWiring.start_for(PackedStringArray(["--xr-smoke=10"]), "", "") != FlightTestWiring.Start.TUNNEL:
		return "a plain start is not the tunnel"
	for start: FlightTestWiring.Start in [FlightTestWiring.Start.OFF, FlightTestWiring.Start.SAVED]:
		var path: String = scratch("never.json")
		var c: ComfortWiring = comfort()
		var wired: FlightTestWiring = wiring(start, path, c)
		frame(wired, {X: true})
		if wired.running() or wired.panel != null:
			return "start %d ran the test on first launch" % start
		if start == FlightTestWiring.Start.OFF and FileAccess.file_exists(path):
			return "an acceptance run wrote the comfort choice"
	return ""


func test_paused_time_does_not_count() -> String:
	var wired: FlightTestWiring = wiring(FlightTestWiring.Start.TUNNEL, scratch("paused.json"), comfort())
	frame(wired, {}, false, 60.0, true)
	var left: float = wired.test.seconds_left()
	free_panel(wired)
	return "" if left == 15.0 else "%.1f s left after a paused minute" % left


func test_a_bad_answers_file_is_reported_and_falls_back_to_the_defaults() -> String:
	var cases: Dictionary[String, String] = {
		"not json": "{",
		"not an object": "[1]",
		"unknown answer": "{\"fine\": \"%s\", \"uneasy\": \"%s\", \"stop\": \"%s\", \"maybe\": \"left_stick_click\"}" % [A, B, Y],
		"missing answer": "{\"fine\": \"%s\", \"uneasy\": \"%s\"}" % [A, B],
		"unknown button": "{\"fine\": \"trigger\", \"uneasy\": \"%s\", \"stop\": \"%s\"}" % [B, Y],
		"not a string": "{\"fine\": 1, \"uneasy\": \"%s\", \"stop\": \"%s\"}" % [B, Y],
		"shared button": "{\"fine\": \"%s\", \"uneasy\": \"%s\", \"stop\": \"%s\"}" % [A, A, Y],
	}
	for name: String in cases:
		var path: String = scratch("answers_bad.json")
		write(path, cases[name])
		var answers: FlightTestAnswers = FlightTestAnswers.load_file(path)
		if answers.error == "" or not answers.error.contains(path):
			return "%s was not reported: %s" % [name, answers.error]
		if answers.buttons != FlightTestAnswers.DEFAULTS:
			return "%s did not fall back to the defaults: %s" % [name, answers.buttons]
	var wired: FlightTestWiring = FlightTestWiring.new()
	wired.choice_path = scratch("bad_answers_choice.json")
	wired.answers_path = SCRATCH_DIR + "/answers_bad.json"
	var c: ComfortWiring = comfort()
	wired.begin(FlightTestWiring.Start.TUNNEL, c, c.set_preset)
	var reported: String = wired.answers.error
	answer_with(wired, A)
	var index: int = wired.test.segment_index()
	free_panel(wired)
	if reported == "":
		return "the wiring did not report the bad file"
	return "" if index == 1 else "A did not answer with the default buttons"


func test_the_shipped_answers_are_a_b_and_y() -> String:
	var answers: FlightTestAnswers = FlightTestAnswers.load_file()
	if answers.error != "":
		return answers.error
	if answers.buttons != FlightTestAnswers.DEFAULTS:
		return "shipped answers %s differ from the defaults" % answers.buttons
	if answers.buttons["fine"] != A or answers.buttons["uneasy"] != B or answers.buttons["stop"] != Y:
		return "answers %s" % answers.buttons
	return ""


func test_a_main_scene_readied_outside_the_tree_keeps_the_start_preset() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var wired: FlightTestWiring = main.get("flight_test")
	var number: int = (main.get("comfort") as ComfortWiring).number
	main.free()
	if wired.start != FlightTestWiring.Start.OFF or wired.test != null:
		return "a unit test's main scene started the flight test"
	return "" if number == 2 else "preset %d, expected the start preset 2" % number
