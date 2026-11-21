extends RefCounted

## The m3 acceptance suite (DEV-6, RUN-2, RUN-3, RUN-5, decision record 0005,
## #376): its first step flies a replay of the bot pilot's G2 escape (#360), clearing
## the robots, destroying the reactor and flying out through the entrance, and
## must end on the pinned hash with the outcome ESCAPED. The second step, a
## generated seed's escape (#460), is tested in `test_m3_seed_step.gd`.
##
## Re-recording after an intended change to the simulation, the bot, the ship
## or robot data, or the level (one command, from the repository root):
##
##     MELTDOWN_RECORD_M3=bot_g2_escape godot --headless --path game -s res://tests/run_tests.gd
##
## The switch takes a comma-separated list of step ids and records only those
## (`record_switch.gd`, #560); `MELTDOWN_RECORD_M3=1` records every m3 step. It flies the bot as `test_bot_escape.gd` does, overwrites
## `acceptance/replays/bot_g2_escape.replay` and prints the new hash; paste
## that hash into `expected_hash` of the step in `acceptance/suites/m3.json`.

const SUITE_PATH: String = "res://acceptance/suites/m3.json"
const SUITE_NAME: String = "m3"
const STEP_ID: String = "bot_g2_escape"
const REPLAY_PATH: String = "res://acceptance/replays/bot_g2_escape.replay"
const DOCTORED_REPLAY: String = "user://t376_doctored.replay"
const LEVEL: String = "g2"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"
const RecordSwitch := preload("res://tests/record_switch.gd")
## The input line changed in the doctored copy: the first one from here on
## that is not already all zeros, so zeroing it really changes the flight.
const DOCTORED_FROM_TICK: int = 30
const ZERO_INPUT_LINE: String = "0 0 0 0 0 0 0 0 0 0"
## The runner flies one tick per frame; the four steps together take some
## 22,000 ticks since #615 added the line-of-sight step.
const FRAME_LIMIT: int = 40000
const BotEscapeTest := preload("res://tests/test_bot_escape.gd")
## The recorder's flight, shared with the check that the step flies the same
## level (#578).
const G2Setup := preload("res://tests/m3_g2_setup.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot pilot's G2 escape (#360): robots cleared, reactor destroyed, out
# through the entrance. Flown in the m3 suite (#376).
# Re-record this step only from the repository root, then copy the printed hash
# into m3.json:
#     MELTDOWN_RECORD_M3=bot_g2_escape godot --headless --path game -s res://tests/run_tests.gd
"""

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			return found
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var flight: BotEscapeTest.Flight = G2Setup.flight()
	var session: LocalSession = flight.session
	if session.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "the bot did not escape, nothing recorded: %s" % BotEscapeTest.describe(flight)
	session.replay.expected_hash = session.sim.state_hash()
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(REPLAY_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(REPLAY_HEADER + session.replay.to_text())
	file.close()
	print("Meltdown: recorded %s: %s, hash %d; put the hash in %s" % [
		REPLAY_PATH, BotEscapeTest.describe(flight), session.replay.expected_hash, SUITE_PATH])
	return ""


func test_m3_suite_loads_with_the_escape_step() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	# The G2 escape stays first; the generated seed's step follows it (#460),
	# then the blast-door seed's (#516), then the line-of-sight seed's (#615),
	# then the fire seed's (#517).
	if suite.name != SUITE_NAME or suite.steps.size() != 5:
		return "suite %s has %d steps" % [suite.name, suite.steps.size()]
	var escape: AcceptanceStep = suite.steps[0]
	if escape.id != STEP_ID or escape.replay_path != REPLAY_PATH or escape.level != LEVEL:
		return "the step is %s, flying %s on level '%s'" % [escape.id, escape.replay_path, escape.level]
	if not escape.has_check(AcceptanceStep.CHECK_FINAL_HASH) or not escape.has_check(AcceptanceStep.CHECK_OUTCOME):
		return "%s checks %s" % [STEP_ID, escape.checks]
	if escape.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects outcome %d" % [STEP_ID, escape.expected_outcome]
	return ""


## `--acceptance=m3` loads just this suite; `--acceptance=all` loads it too,
## every suite still in name order.
func test_m3_and_all_both_load_the_suite() -> String:
	var named: Array[AcceptanceSuite] = AcceptanceSuite.load_named(SUITE_NAME)
	if named.size() != 1 or named[0].name != SUITE_NAME or named[0].error != "":
		return "--acceptance=m3 loaded %d suites" % named.size()
	var names: Array[String] = []
	for suite: AcceptanceSuite in AcceptanceSuite.load_named(AcceptanceSuite.ALL):
		if suite.error != "":
			return suite.error
		names.append(suite.name)
	var sorted: Array[String] = names.duplicate()
	sorted.sort()
	if not names.has(SUITE_NAME) or names != sorted:
		return "--acceptance=all loaded %s" % [names]
	return ""


## Read from the file and run twice: both end on the suite's and the replay's
## hash, with the ship escaped.
func test_replay_ends_on_its_hash_escaped() -> String:
	var escape: AcceptanceStep = step()
	if escape == null:
		return "m3 has no step %s" % STEP_ID
	for attempt: int in 2:
		var replay: Replay = Replay.load_file(REPLAY_PATH)
		if replay.error != "":
			return replay.error
		if replay.reactor == null:
			return "the replay has no reactor"
		var sim: Sim = replay.run()
		if sim == null:
			return replay.run_error
		var actual: int = sim.state_hash()
		if actual != escape.expected_hash or actual != replay.expected_hash:
			return "run %d flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" % [
				attempt + 1, actual, escape.expected_hash, replay.expected_hash]
		if sim.outcome() != ExitRule.Outcome.ESCAPED:
			return "run %d ends on outcome %s, not ESCAPED" % [
				attempt + 1, AcceptanceStateChecks.outcome_name(sim.outcome())]
	return ""


## The suite as `--acceptance=m3` runs it, in the flat main scene: every
## check of both steps passes and the report measures the outcome.
func test_the_runner_passes_m3() -> String:
	var runner: AcceptanceRunner = _run(AcceptanceSuite.load_named(SUITE_NAME))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("outcome") != "ESCAPED":
			problem = "measured %s" % measured
	_done(runner)
	return problem


## A copy of the replay with one input line changed flies a different run:
## the step fails, and the report and log name it.
func test_a_changed_input_line_fails_the_step_naming_it() -> String:
	var problem: String = _write_doctored_replay()
	if problem != "":
		return problem
	var escape: AcceptanceStep = step()
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(JSON.stringify({
		"name": SUITE_NAME,
		"steps": [{"id": STEP_ID, "level": LEVEL, "replay": DOCTORED_REPLAY,
			"checks": ["final_hash", "outcome"], "expected_hash": escape.expected_hash,
			"expected_outcome": "ESCAPED"}],
	}))
	if suite.error != "":
		DirAccess.remove_absolute(DOCTORED_REPLAY)
		return suite.error
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = _run(suites)
	var step_report: Dictionary = runner.reports[0].steps[0] if not runner.reports.is_empty() else {}
	if runner.exit_code != AcceptanceRunner.EXIT_FAIL:
		problem = "exit %d with a changed input line" % runner.exit_code
	elif step_report.get("id") != STEP_ID or step_report.get("result") != AcceptanceReport.RESULT_FAIL:
		problem = "the report says %s" % step_report
	elif not str(step_report.get("message")).contains("final_hash: final hash"):
		problem = "the message does not give the hash: '%s'" % step_report.get("message")
	elif not "\n".join(runner.messages).contains("step %s %s" % [STEP_ID, AcceptanceReport.RESULT_FAIL]):
		problem = "the log does not name the failed step: %s" % "\n".join(runner.messages)
	_done(runner)
	DirAccess.remove_absolute(DOCTORED_REPLAY)
	return problem


func test_expected_outcome_is_checked_when_read() -> String:
	var cases: Dictionary[String, String] = {
		"\"checks\": [\"outcome\"]": "steps[0].expected_outcome: needed",
		"\"checks\": [\"final_hash\"], \"expected_hash\": 1, \"expected_outcome\": \"ESCAPED\"":
			"steps[0].expected_outcome: only used",
		"\"checks\": [\"outcome\"], \"expected_outcome\": \"escaped\"": "must be one of",
		"\"checks\": [\"outcome\"], \"expected_outcome\": 1": "must be one of",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"r\", %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	var lost: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"r\", \"checks\": [\"outcome\"], "
		+ "\"expected_outcome\": \"LOST\"}]}")
	if lost.error != "" or lost.steps[0].expected_outcome != ExitRule.Outcome.LOST:
		return "LOST read as %d: %s" % [lost.steps[0].expected_outcome if lost.error == "" else -1, lost.error]
	return ""


## The replay's text with one input line, from DOCTORED_FROM_TICK on, zeroed.
func _write_doctored_replay() -> String:
	var lines: PackedStringArray = FileAccess.get_file_as_string(REPLAY_PATH).split("\n")
	var first_input: int = lines.find("inputs") + 1
	if first_input == 0:
		return "%s has no inputs line" % REPLAY_PATH
	var changed: int = -1
	for index: int in range(first_input + DOCTORED_FROM_TICK, lines.size()):
		if lines[index].strip_edges() != "" and lines[index] != ZERO_INPUT_LINE:
			changed = index
			break
	if changed < 0:
		return "no input line to change"
	lines[changed] = ZERO_INPUT_LINE
	var file: FileAccess = FileAccess.open(DOCTORED_REPLAY, FileAccess.WRITE)
	if file == null:
		return "could not write %s: %s" % [DOCTORED_REPLAY, error_string(FileAccess.get_open_error())]
	file.store_string("\n".join(lines))
	file.close()
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run(suites: Array[AcceptanceSuite]) -> AcceptanceRunner:
	_quit_codes.clear()
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	# Built and readied as on the headset, so the map in the hand that
	# `map_route` reads is there (#884).
	var main: Node = scene.instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
