extends RefCounted

## The escape's end screen (#751, RUN-3, RUN-7, CMF-8, ARC-4): ESCAPED, the
## meltdown time left and the prompt once the run is escaped, a restart after
## the hold on a fresh press, the destroyed screen kept for a meltdown loss,
## and its data file.

const FRAME: float = 1.0 / 90.0
const G2: String = "res://data/levels/g2_level.json"


static func _g2_session() -> LocalSession:
	var level: LevelDef = LevelSwitch.load_level(G2)
	return LocalSession.for_level(level, 0, null, LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))


## The reactor destroyed with `seconds` of meltdown left and ship 0 escaped,
## so the outcome is ESCAPED.
static func _escape(session: LocalSession, seconds: int) -> void:
	session.sim.reactor.destroyed = true
	session.sim.reactor.meltdown_ticks_left = seconds * ReactorState.TICKS_PER_SECOND
	session.sim.ships[0].escaped = true


static func _run(wiring: EscapeEndWiring, session: LocalSession, seconds: float, held: bool) -> int:
	var restarts: int = 0
	for i: int in ceili(seconds / FRAME):
		if wiring.update(session, FRAME, held, Transform3D.IDENTITY, true):
			restarts += 1
	return restarts


func test_escaped_with_38_seconds_left_shows_the_line_time_and_prompt() -> String:
	var rig: Node3D = Node3D.new()
	var result: String = _check_shown(rig)
	rig.free()
	return result


func _check_shown(rig: Node3D) -> String:
	var wiring: EscapeEndWiring = EscapeEndWiring.new()
	wiring.attach(rig)
	wiring.attach(rig)
	if rig.get_child_count() != 2 or wiring.screen.get_parent() != rig or wiring.choice.panel.get_parent() != rig:
		return "attach did not hang one screen and one shaft panel (#990) under the rig"
	var session: LocalSession = _g2_session()
	_run(wiring, session, 0.5, false)
	if session.sim.outcome() != ExitRule.Outcome.RUNNING or wiring.screen.line_visible() \
			or wiring.fade_alpha() != 0.0:
		return "the escape screen shows while the run is RUNNING"
	_escape(session, 38)
	_run(wiring, session, 1.2, false)
	if not wiring.screen.line_visible() or wiring.screen.line_text() != "ESCAPED":
		return "ESCAPED is not shown: '%s'" % wiring.screen.line_text()
	if not wiring.screen.time_text().contains("0:38"):
		return "the time left reads '%s', not 0:38" % wiring.screen.time_text()
	if wiring.fade_alpha() < 0.99:
		return "the view is not faded dark (alpha %.2f)" % wiring.fade_alpha()
	if wiring.screen.prompt_visible():
		return "the prompt shows before the hold"
	_run(wiring, session, 2.0, false)
	if not wiring.screen.prompt_visible() or wiring.screen.prompt_text() != "Press A to fly again":
		return "the headset prompt is not shown after the hold: '%s'" % wiring.screen.prompt_text()
	wiring.update(session, FRAME, false, Transform3D.IDENTITY, false)
	if not wiring.screen.prompt_text().contains("Enter"):
		return "the flat build's prompt does not name Enter: '%s'" % wiring.screen.prompt_text()
	return ""


func test_the_restart_comes_once_after_the_hold_on_a_fresh_press() -> String:
	var wiring: EscapeEndWiring = EscapeEndWiring.new()
	var session: LocalSession = _g2_session()
	_escape(session, 38)
	var hold: float = wiring.sequence.hold_seconds
	if _run(wiring, session, hold - 0.2, true) != 0:
		return "holding the button before the delay restarted"
	if _run(wiring, session, 0.5, true) != 0:
		return "a button held since before the delay restarted without a fresh press"
	_run(wiring, session, FRAME, false)
	if _run(wiring, session, 2.0, true) != 1:
		return "holding the button after the delay did not restart exactly once"
	return ""


func test_a_paused_session_holds_the_screen_still() -> String:
	var wiring: EscapeEndWiring = EscapeEndWiring.new()
	var session: LocalSession = _g2_session()
	_escape(session, 38)
	_run(wiring, session, 0.3, false)
	var alpha: float = wiring.fade_alpha()
	session.paused = true
	_run(wiring, session, 5.0, false)
	if wiring.fade_alpha() != alpha or wiring.sequence.prompt_shown():
		return "the escape screen ran on while paused"
	return ""


func test_the_shipped_file_matches_the_fallback() -> String:
	var look: Dictionary = EscapeScreenLook.parse(FileAccess.get_file_as_string(EscapeScreenLook.DEFAULT_FILE))
	if look.has("error"):
		return "shipped file rejected: %s" % look["error"]
	for key: String in EscapeScreenLook.FALLBACK:
		if str(look[key]) != str(EscapeScreenLook.FALLBACK[key]):
			return "\"%s\" is %s in the file and %s built in" % [key, look[key], EscapeScreenLook.FALLBACK[key]]
	var words: Dictionary = EscapeScreenLook.parse(FileAccess.get_file_as_string(EscapeScreenLook.DEFAULT_FILE)
		.replace("\"ESCAPED\"", "\"OUT\""))
	var screen: EscapeScreen = EscapeScreen.new(words)
	var line: String = screen.line_text()
	screen.free()
	if line != "OUT":
		return "the screen does not take its words from the look"
	return ""


func test_a_missing_or_bad_file_falls_back_to_built_in_words() -> String:
	if EscapeScreenLook.load_file("res://no_such_escape_screen.json") != EscapeScreenLook.FALLBACK:
		return "a missing file did not give the built-in look"
	var path: String = "user://t751_bad_escape_screen.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	var look: Dictionary = EscapeScreenLook.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if look != EscapeScreenLook.FALLBACK:
		return "a bad file did not give the built-in look"
	var screen: EscapeScreen = EscapeScreen.new(look)
	screen.show_state(true, true, 38.0, true)
	var shown: String = screen.time_text()
	screen.free()
	if shown != "0:38 left":
		return "the built-in look shows '%s'" % shown
	return ""


func test_bad_values_are_rejected_naming_the_field() -> String:
	var shipped: String = FileAccess.get_file_as_string(EscapeScreenLook.DEFAULT_FILE)
	var cases: Dictionary = {
		shipped.replace("\"{time} left\"", "\"left\""): "time_text",
		shipped.replace("\"ESCAPED\"", "\" \""): "line_text",
		shipped.replace("\"hold_seconds\": 3.0", "\"hold_seconds\": true"): "hold_seconds",
		shipped.replace("\"fade_seconds\": 1.0", "\"fade_seconds\": 11"): "fade_seconds",
		shipped.replace("[0.0, 0.1, -1.5]", "[0.0, 0.1, 1.5]"): "line_position_m",
		shipped.replace("[0.35, 1.0, 0.45]", "[0.35, 2.0, 0.45]"): "line_color",
		shipped.replace("\"pixel_size\": 0.001", "\"pixel_size\": 0.001, \"size\": 1"): "size",
		shipped.replace("\"prompt_flat\": \"Press Enter to fly again\",", ""): "prompt_flat",
		"[]": "object",
	}
	for text: String in cases:
		var look: Dictionary = EscapeScreenLook.parse(text)
		if not look.has("error") or not (look["error"] as String).contains(cases[text]):
			return "a file wrong in %s gave %s" % [cases[text], look]
	return ""


func test_the_clock_reads_minutes_and_seconds() -> String:
	var cases: Dictionary = {38.0: "0:38", 38.9: "0:38", 0.0: "0:00", -2.0: "0:00", 125.0: "2:05"}
	for seconds: float in cases:
		if EscapeScreenLook.clock_text(seconds) != cases[seconds]:
			return "%s s reads %s" % [seconds, EscapeScreenLook.clock_text(seconds)]
	return ""
