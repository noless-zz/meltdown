extends RefCounted

## The `escape_cue` acceptance check and the m3 `bot_generated_escape` step that
## lists it (#885, RUN-2, RUN-5, MAP-2, CMF-8): the cockpit's countdown and
## arrow, judged tick by tick in the running game. The step's hashes are those
## it had before the check, because the check only reads.

const STEP_ID: String = "bot_generated_escape"
const EXPECTED_HASH: int = 3709902663
## The replay header written as format version 17 since #922.
const EXPECTED_LEVEL_HASH: int = 1931884533
const SeedPick := preload("res://tests/m3_seed_pick.gd")
const M3Run := preload("res://tests/m3_suite_run.gd")


func test_the_step_lists_escape_cue_and_keeps_its_hashes() -> String:
	var step: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if step == null:
		return "m3 has no step %s" % STEP_ID
	if not step.has_check(AcceptanceStep.CHECK_ESCAPE_CUE):
		return "%s checks %s" % [STEP_ID, step.checks]
	if step.expected_hash != EXPECTED_HASH or step.expected_level_hash != EXPECTED_LEVEL_HASH:
		return "%s expects hash %d and level hash %d" % [STEP_ID, step.expected_hash, step.expected_level_hash]
	return ""


func test_the_check_is_known_and_needs_a_replay() -> String:
	if not AcceptanceStep.KNOWN_CHECKS.has(AcceptanceStep.CHECK_ESCAPE_CUE):
		return "escape_cue is not a known check"
	var parsed: AcceptanceSuite = AcceptanceSuite.parse_json(
		'{"name": "t", "steps": [{"id": "s", "checks": ["escape_cue"]}]}')
	if not parsed.error.contains("replay: needed by the escape_cue check"):
		return "a step without a replay gave '%s'" % parsed.error
	return ""


## The shipped step, flown in the shared m3 run (`m3_suite_run.gd`, #1139) by
## the runner in a main scene built as on the
## headset: every check passes, and the countdown and arrow were seen.
func test_the_runner_passes_the_step_with_the_cue() -> String:
	var problem: String = M3Run.step_problem(STEP_ID)
	if problem == "":
		var step: Dictionary = M3Run.step(STEP_ID)
		var measured: Dictionary = step["measurements"]
		if int(measured.get("escape_cue_countdown_ticks", 0)) < 60 \
				or int(measured.get("escape_cue_arrow_ticks", 0)) < 60 \
				or not str(step["message"]).contains("escape_cue: countdown shown on"):
			problem = "measured %s: %s" % [measured, step["message"]]
	return problem


func test_a_clean_hand_fed_run_passes() -> String:
	var measured: Dictionary = {}
	var result: Array = AcceptanceEscapeCueCheck.judge(_run_samples(), measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "a clean run failed: %s" % result[1]
	if int(measured["escape_cue_meltdown_ticks"]) != 80 or int(measured["escape_cue_arrow_ticks"]) != 80:
		return "measured %s" % measured
	return ""


func test_a_rising_countdown_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[40]["countdown_seconds"] = int(taken[39]["countdown_seconds"]) + 1
	return _fails_with(taken, "tick 40: the countdown went up from 51 s to 52 s")


func test_a_countdown_far_from_the_simulation_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	for i: int in range(30, taken.size()):
		if bool(taken[i]["countdown_shown"]):
			taken[i]["countdown_seconds"] = int(taken[i]["countdown_seconds"]) - 3
	return _fails_with(taken, "tick 30: the countdown shows 57 s with 60.00 s of the meltdown left")


func test_a_countdown_hidden_while_due_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[12]["countdown_shown"] = false
	taken[12]["countdown_seconds"] = -1
	return _fails_with(taken, "tick 12: the countdown is hidden while it is due")


func test_an_arrow_off_by_twenty_degrees_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[50]["arrow_degrees"] = 20.0
	return _fails_with(taken, "tick 50: the arrow is 20.0 degrees off the route's next point")


func test_a_hidden_arrow_with_a_route_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[51]["arrow_shown"] = false
	return _fails_with(taken, "tick 51: the arrow is hidden while the map has a route")


func test_a_cue_before_the_reactor_dies_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[3]["cue_shown"] = true
	return _fails_with(taken, "tick 3: a cue shows before the reactor died")


func test_a_cue_left_after_the_escape_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[95]["cue_shown"] = true
	return _fails_with(taken, "tick 95: a cue still shows after the escape")


func test_a_run_that_never_escapes_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken.resize(90)
	var result: Array = AcceptanceEscapeCueCheck.judge(taken, {})
	if result[0] == AcceptanceReport.RESULT_PASS or not str(result[1]).contains("never escaped"):
		return "a run cut before the escape gave %s" % [result]
	return ""


func test_no_samples_fail() -> String:
	var result: Array = AcceptanceEscapeCueCheck.judge([] as Array[Dictionary], {})
	if result[0] == AcceptanceReport.RESULT_PASS or not str(result[1]).contains("no cockpit for the meltdown cue"):
		return "no samples gave %s" % [result]
	return ""


func test_countdown_text_reads_as_seconds() -> String:
	var cases: Dictionary = {"1:05": 65, "0:00": 0, "12:30": 750, "": -1, "1:x": -1, "65": -1}
	for text: String in cases:
		if AcceptanceEscapeCueCheck.read_seconds(text) != int(cases[text]):
			return "'%s' read as %d" % [text, AcceptanceEscapeCueCheck.read_seconds(text)]
	return ""


## Ticks 0..99: the reactor dies on tick 10 with 80 s left (counted here at one
## second a tick), the run escapes on tick 90, the countdown and the arrow show
## through the meltdown and nothing shows outside it.
static func _run_samples() -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for tick: int in 100:
		var dead: bool = tick >= 10
		var meltdown: bool = dead and tick < 90
		var left: float = 80.0 - float(tick - 10) if dead else -1.0
		taken.append({
			"tick": tick, "reactor_dead": dead, "running": tick < 90, "escaped": tick >= 90,
			"cue_shown": meltdown, "countdown_due": meltdown, "countdown_shown": meltdown,
			"countdown_seconds": floori(left) if meltdown else -1, "seconds_left": left,
			"has_route": meltdown, "arrow_shown": meltdown, "arrow_degrees": 1.0 if meltdown else -1.0,
		})
	return taken


static func _fails_with(taken: Array[Dictionary], text: String) -> String:
	var result: Array = AcceptanceEscapeCueCheck.judge(taken, {})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]) != text:
		return "wanted '%s', got %s" % [text, result]
	return ""
