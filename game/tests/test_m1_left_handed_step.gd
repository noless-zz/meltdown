extends RefCounted

## The m1 suite's `right_handed_flight` and `left_handed_flight` steps (#818,
## PLT-5, ARC-2, DEV-6): one flight scripted as raw controller values, flown
## right-handed, and the same flight with every control moved to the other hand
## flown left-handed, both through the scene's `ThumbstickMapping`. Left-handed
## mode swaps the hands (decision record 0004), so both end on the same hash.
##
## Changing either controls file means re-measuring the hash and pasting it
## into both steps; `test_both_steps_expect_the_same_hash` keeps them equal.

const M1_PATH: String = "res://acceptance/suites/m1.json"
const RIGHT_ID: String = "right_handed_flight"
const LEFT_ID: String = "left_handed_flight"
const PLAIN_PATH: String = "res://acceptance/replays/m1_controls.controls.json"
const MIRRORED_PATH: String = "res://acceptance/replays/m1_controls_mirrored.controls.json"
const REPLAY_PATH: String = "res://acceptance/replays/basic_flight.replay"
const FRAME_LIMIT: int = 2000


static func _find(id: String) -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(M1_PATH).steps:
		if step.id == id:
			return step
	return null


static func _suite_text(step_json: String) -> String:
	return "{\"name\": \"x\", \"steps\": [%s]}" % step_json


func test_the_field_parses_and_defaults_to_false() -> String:
	var base: String = "{\"id\": \"a\", \"replay\": \"%s\", \"controls\": \"%s\", \"checks\": [\"final_hash\"], \"expected_hash\": 1%s}"
	var plain: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(base % [REPLAY_PATH, PLAIN_PATH, ""]))
	if plain.error != "" or plain.steps[0].left_handed or plain.steps[0].controls_path != PLAIN_PATH:
		return "without left_handed: %s" % plain.error
	var left: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(
		base % [REPLAY_PATH, PLAIN_PATH, ", \"left_handed\": true"]))
	if left.error != "" or not left.steps[0].left_handed:
		return "with left_handed true: %s" % left.error
	var none: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(
		"{\"id\": \"a\", \"replay\": \"%s\", \"checks\": [\"final_hash\"], \"expected_hash\": 1}" % REPLAY_PATH))
	if none.error != "" or none.steps[0].left_handed or none.steps[0].controls_path != "":
		return "a replay step: %s" % none.error
	return ""


func test_bad_fields_are_refused_naming_them() -> String:
	var checks: String = "\"checks\": [\"no_script_errors\"]"
	var cases: Dictionary = {
		"\"replay\": \"%s\", \"left_handed\": true" % REPLAY_PATH: "left_handed",
		"\"replay\": \"%s\", \"controls\": \"%s\", \"left_handed\": 1" % [REPLAY_PATH, PLAIN_PATH]: "left_handed",
		"\"controls\": \"%s\"" % PLAIN_PATH: "controls",
		"\"replay\": \"%s\", \"controls\": \"res://nowhere.json\"" % REPLAY_PATH: "controls",
	}
	for fields: String in cases:
		var text: String = "{\"id\": \"a\", %s, %s}" % [checks, fields]
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(text))
		if suite.error == "" or not suite.error.contains("steps[0].%s" % cases[fields]):
			return "%s gave '%s'" % [text, suite.error]
	return ""


func test_a_bad_controls_file_names_the_field() -> String:
	var cases: Dictionary = {
		"{\"segments\": []}": "segments",
		"{\"segments\": [{\"ticks\": 0}]}": "segments[0].ticks",
		"{\"segments\": [{\"ticks\": 5, \"left_stick\": [0, 2]}]}": "segments[0].left_stick",
		"{\"segments\": [{\"ticks\": 5, \"right_grip\": -0.5}]}": "segments[0].right_grip",
		"{\"segments\": [{\"ticks\": 5}, {\"ticks\": 5, \"buttons\": [\"menu\"]}]}": "segments[1].buttons",
		"{\"segments\": [{\"ticks\": 5, \"thumb\": 1}]}": "segments[0].thumb",
	}
	for text: String in cases:
		var script: AcceptanceControlsScript = AcceptanceControlsScript.from_json(text)
		if script.error == "" or not script.error.contains(cases[text]):
			return "%s gave '%s'" % [text, script.error]
	var good: AcceptanceControlsScript = AcceptanceControlsScript.from_json(
		"{\"segments\": [{\"ticks\": 2, \"left_stick\": [0, 1], \"buttons\": [\"right_button_lower\"]}, {\"ticks\": 3}]}")
	if good.error != "" or good.frames.size() != 5:
		return "a good file: %s, %d frames" % [good.error, good.frames.size()]
	if good.frames[0]["left_stick"] != Vector2(0, 1) or not good.frames[1]["buttons"].get("right_button_lower", false) \
			or not (good.frames[2]["buttons"] as Dictionary).is_empty():
		return "frames %s" % [good.frames]
	return ""


## The shipped mirrored file is the plain one with every control on the other
## hand, segment by segment, so the two steps fly the same flight.
func test_the_mirrored_file_moves_every_control_to_the_other_hand() -> String:
	var plain: AcceptanceControlsScript = AcceptanceControlsScript.load_file(PLAIN_PATH)
	var mirrored: AcceptanceControlsScript = AcceptanceControlsScript.load_file(MIRRORED_PATH)
	if plain.error != "" or mirrored.error != "" or plain.frames.size() != mirrored.frames.size():
		return "files: %s / %s" % [plain.error, mirrored.error]
	var pressed: Dictionary = {}
	for tick: int in plain.frames.size():
		var a: Dictionary = plain.frames[tick]
		var b: Dictionary = mirrored.frames[tick]
		for hand: Array in [["left", "right"], ["right", "left"]]:
			for part: String in ["_stick", "_trigger", "_grip"]:
				if a[hand[0] + part] != b[hand[1] + part]:
					return "tick %d: %s%s %s, mirrored %s%s %s" % [tick, hand[0], part, a[hand[0] + part],
						hand[1], part, b[hand[1] + part]]
		var swapped: Dictionary = {}
		for button: String in a["buttons"]:
			swapped[button.replace("left_", "x_").replace("right_", "left_").replace("x_", "right_")] = true
			pressed[button] = true
		if swapped != b["buttons"]:
			return "tick %d: buttons %s, mirrored %s" % [tick, a["buttons"], b["buttons"]]
	# Sticks, grips, a trigger and both kinds of face button are all exercised.
	for button: String in ["left_button_upper", "right_button_upper", "right_button_lower"]:
		if not pressed.has(button):
			return "the flight never presses %s" % button
	return ""


func test_both_steps_are_listed_with_their_checks_and_the_same_hash() -> String:
	var right: AcceptanceStep = _find(RIGHT_ID)
	var left: AcceptanceStep = _find(LEFT_ID)
	if right == null or left == null:
		return "m1 lacks a step: right %s, left %s" % [right != null, left != null]
	if right.left_handed or not left.left_handed:
		return "hands: right %s, left %s" % [right.left_handed, left.left_handed]
	if right.controls_path != PLAIN_PATH or left.controls_path != MIRRORED_PATH:
		return "controls: %s, %s" % [right.controls_path, left.controls_path]
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]
	if right.checks != wanted or left.checks != wanted:
		return "checks: %s, %s" % [right.checks, left.checks]
	if right.expected_hash == AcceptanceStep.NO_HASH or right.expected_hash != left.expected_hash:
		return "hashes: %d, %d" % [right.expected_hash, left.expected_hash]
	# The controls fly, not the replay's own inputs.
	if right.expected_hash == Replay.load_file(REPLAY_PATH).expected_hash:
		return "the step expects the replay's own hash %d" % right.expected_hash
	return ""


## The mirrored flight left-handed and the plain flight right-handed both pass
## in the main scene, ending on the one hash both steps expect.
func test_the_mirrored_flight_left_handed_equals_the_plain_flight_right_handed() -> String:
	var right: Array = _run_step(_find(RIGHT_ID), false)
	var left: Array = _run_step(_find(LEFT_ID), false)
	if right[0] != AcceptanceRunner.EXIT_PASS or left[0] != AcceptanceRunner.EXIT_PASS:
		return "right exit %d: %s\nleft exit %d: %s" % [right[0], right[1], left[0], left[1]]
	if right[2] != left[2]:
		return "hashes %d and %d" % [right[2], left[2]]
	return ""


## Left-handed mode must matter: the plain, unmirrored flight left-handed
## ends somewhere else and fails the hash.
func test_the_unmirrored_flight_left_handed_ends_elsewhere() -> String:
	var step: AcceptanceStep = _find(RIGHT_ID)
	step.left_handed = true
	var report: Array = _run_step(step, false)
	if report[0] == AcceptanceRunner.EXIT_PASS or report[2] == step.expected_hash:
		return "the unmirrored flight left-handed ended on %d: %s" % [report[2], report[1]]
	return ""


## After a left-handed step the scene's mapping is back as it was: right-handed
## for a right-handed player, and with a player's inverted pitch kept.
func test_the_mapping_is_right_handed_again_after_the_step() -> String:
	var after: Array = _run_step(_find(LEFT_ID), false)
	if after[3] != [false, false]:
		return "after the step the mapping is left-handed %s, inverted %s" % after[3]
	var inverted: Array = _run_step(_find(LEFT_ID), true)
	if inverted[0] != AcceptanceRunner.EXIT_PASS:
		return "a player's inverted pitch changed the step: %s" % inverted[1]
	if inverted[3] != [false, true]:
		return "an inverted player's mapping came back left-handed %s, inverted %s" % inverted[3]
	return ""


## [exit code, messages and results, final hash, [left_handed, invert_pitch]
## of the scene's mapping afterwards] of the runner flying `step` alone in the
## main scene; `inverted` sets the player's inverted pitch first.
func _run_step(step: AcceptanceStep, inverted: bool) -> Array:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var mapping: ThumbstickMapping = main.get("mapping")
	mapping.left_handed = false
	mapping.invert_pitch = inverted
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var code: int = runner.exit_code if runner.finished else -1
	var text: String = "\n".join(runner.messages)
	var final_hash: int = AcceptanceStep.NO_HASH
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			text += "\n%s: %s" % [entry["result"], entry["message"]]
			final_hash = int(entry["measurements"].get("final_hash", AcceptanceStep.NO_HASH))
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var hands: Array = [mapping.left_handed, mapping.invert_pitch]
	runner.main.free()
	runner.free()
	return [code, text, final_hash, hands]
