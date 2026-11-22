extends RefCounted

## The destroyed ship's screen as a state machine and its data file (#616,
## RUN-7, CMF-8, ARC-4): alive, destroyed, can restart, restarted, alive.

const FRAME: float = 1.0 / 90.0


static func _run(sequence: DestroyedSequence, hull: float, seconds: float, held: bool) -> int:
	var restarts: int = 0
	var frames: int = ceili(seconds / FRAME)
	for i: int in frames:
		if sequence.update(hull, FRAME, held):
			restarts += 1
	return restarts


func test_the_shipped_file_parses_with_the_issue_defaults() -> String:
	var path: String = DestroyedSequence.DEFAULT_FILE
	var values: Dictionary = DestroyedSequence.parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		return "shipped file rejected: %s" % values["error"]
	if not is_equal_approx(values["fade_seconds"], 1.0) or not is_equal_approx(values["hold_seconds"], 3.0):
		return "shipped times are %s, not a 1 s fade and a 3 s hold" % values
	var loaded: DestroyedSequence = DestroyedSequence.load_file()
	if loaded.fade_seconds != values["fade_seconds"] or loaded.hold_seconds != values["hold_seconds"]:
		return "load_file did not take the file's times"
	return ""


func test_bad_files_are_rejected_naming_the_field() -> String:
	var cases: Dictionary = {
		'{"fade_seconds": 1}': "hold_seconds",
		'{"fade_seconds": true, "hold_seconds": 3}': "fade_seconds",
		'{"fade_seconds": -1, "hold_seconds": 3}': "fade_seconds",
		'{"fade_seconds": 1, "hold_seconds": 31}': "hold_seconds",
		'{"fade_seconds": 1, "hold_seconds": 3, "fade": 2}': "fade",
		'[]': "object",
		'{': "JSON",
	}
	for text: String in cases:
		var values: Dictionary = DestroyedSequence.parse(text)
		if not values.has("error") or not String(values["error"]).contains(cases[text]):
			return "%s gave %s, expected an error naming %s" % [text, values, cases[text]]
	var missing: DestroyedSequence = DestroyedSequence.load_file("res://no_such_destroyed.json")
	if missing.fade_seconds != DestroyedSequence.FALLBACK["fade_seconds"]:
		return "a missing file did not fall back"
	return ""


func test_alive_shows_nothing_while_hull_remains() -> String:
	var sequence: DestroyedSequence = DestroyedSequence.new()
	if _run(sequence, 0.01, 5.0, true) != 0:
		return "a ship with hull left asked to restart"
	if sequence.state != DestroyedSequence.State.ALIVE or sequence.fade_alpha() != 0.0 or sequence.line_shown():
		return "a ship with hull left shows the destroyed screen"
	return ""


func test_zero_hull_fades_over_the_fade_time_and_shows_the_line() -> String:
	var sequence: DestroyedSequence = DestroyedSequence.new({"fade_seconds": 1.0, "hold_seconds": 3.0})
	sequence.update(0.0, FRAME, false)
	if sequence.state != DestroyedSequence.State.DESTROYED or not sequence.line_shown():
		return "zero hull did not enter DESTROYED with the line"
	if sequence.prompt_shown():
		return "the restart prompt shows before the hold time"
	_run(sequence, 0.0, 0.5, false)
	var half: float = sequence.fade_alpha()
	if half < 0.4 or half > 0.6:
		return "half way through the fade the alpha is %.2f" % half
	_run(sequence, 0.0, 0.6, false)
	if sequence.fade_alpha() != 1.0:
		return "after the fade time the alpha is %.2f, not 1" % sequence.fade_alpha()
	return ""


func test_the_prompt_waits_for_the_hold_time_and_never_restarts_on_its_own() -> String:
	var sequence: DestroyedSequence = DestroyedSequence.new({"fade_seconds": 1.0, "hold_seconds": 3.0})
	sequence.update(0.0, FRAME, false)
	_run(sequence, 0.0, 2.9, false)
	if sequence.prompt_shown():
		return "the prompt shows before 3 s"
	_run(sequence, 0.0, 0.2, false)
	if sequence.state != DestroyedSequence.State.CAN_RESTART or not sequence.prompt_shown():
		return "the prompt is not shown after 3 s"
	if _run(sequence, 0.0, 60.0, false) != 0 or not sequence.line_shown():
		return "a minute without a press restarted or cleared the line"
	return ""


func test_a_press_restarts_once_then_fades_back_in() -> String:
	var sequence: DestroyedSequence = DestroyedSequence.new({"fade_seconds": 1.0, "hold_seconds": 3.0})
	sequence.update(0.0, FRAME, false)
	_run(sequence, 0.0, 3.1, false)
	if not sequence.update(0.0, FRAME, true):
		return "a press after the hold did not ask for a restart"
	if sequence.state != DestroyedSequence.State.RESTARTED or sequence.line_shown():
		return "after the press the line is still shown"
	if sequence.fade_alpha() < 0.9:
		return "the fade-in did not start from dark"
	if _run(sequence, 1.0, 0.5, true) != 0:
		return "holding the button asked for a second restart"
	var half: float = sequence.fade_alpha()
	if half < 0.4 or half > 0.6:
		return "half way through the fade-in the alpha is %.2f" % half
	_run(sequence, 1.0, 0.6, false)
	if sequence.state != DestroyedSequence.State.ALIVE or sequence.fade_alpha() != 0.0:
		return "after the fade-in the sequence is not ALIVE and clear"
	return ""


func test_a_button_held_since_before_the_prompt_does_not_restart() -> String:
	var sequence: DestroyedSequence = DestroyedSequence.new({"fade_seconds": 1.0, "hold_seconds": 3.0})
	if _run(sequence, 0.0, 5.0, true) != 0:
		return "A held through the death and the hold restarted without a fresh press"
	if _run(sequence, 0.0, FRAME, false) != 0 or not sequence.update(0.0, FRAME, true):
		return "release and press did not restart"
	return ""


func test_paused_frames_hold_the_sequence_still() -> String:
	var sequence: DestroyedSequence = DestroyedSequence.new({"fade_seconds": 1.0, "hold_seconds": 3.0})
	sequence.update(0.0, FRAME, false)
	for i: int in 900:
		sequence.update(0.0, 0.0, false)
	if sequence.prompt_shown() or sequence.fade_alpha() > 0.0:
		return "zero-length frames moved the sequence on"
	return ""


## The fade out is timed from the destruction, not from the prompt (#1228,
## CMF-8): its opacity never goes down until the press, whatever the times.
func test_the_fade_never_goes_down_before_the_press() -> String:
	for times: Dictionary in [{"fade_seconds": 1.0, "hold_seconds": 3.0},
			{"fade_seconds": 2.0, "hold_seconds": 0.5}, {"fade_seconds": 0.0, "hold_seconds": 1.0}]:
		var sequence: DestroyedSequence = DestroyedSequence.new(times)
		var last: float = 0.0
		for i: int in ceili(6.0 / FRAME):
			sequence.update(0.0, FRAME, false)
			var alpha: float = sequence.fade_alpha()
			if alpha < last:
				return "with %s the fade went down from %.3f to %.3f in %s" % [times, last, alpha,
					DestroyedSequence.State.keys()[sequence.state]]
			last = alpha
		if sequence.state != DestroyedSequence.State.CAN_RESTART or last != 1.0:
			return "with %s the view is not dark at the prompt (alpha %.2f)" % [times, last]
	return ""
