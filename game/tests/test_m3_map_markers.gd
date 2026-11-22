extends RefCounted

## The `map_markers` acceptance check (#913, MAP-1, MAP-2, RUN-2, DEV-7) and the
## four generated m3 replays flown with it: from the tick the reactor dies the
## held map marks it, and the exit is marked throughout. `m3.json` lists the
## check on all four (#912).

const SeedPick := preload("res://tests/m3_seed_pick.gd")
const GENERATED_STEPS: Array[String] = ["bot_generated_escape", "bot_generated_door_escape",
	"bot_generated_sight", "bot_generated_fire_escape"]
const M3Run := preload("res://tests/m3_suite_run.gd")


func test_the_check_is_known_judged_and_needs_a_replay() -> String:
	if not AcceptanceStep.KNOWN_CHECKS.has(AcceptanceStep.CHECK_MAP_MARKERS):
		return "map_markers is not a known check"
	if not AcceptanceChecks.new().judged_checks().has(AcceptanceStep.CHECK_MAP_MARKERS):
		return "map_markers has no judge"
	var parsed: AcceptanceSuite = AcceptanceSuite.parse_json(
		'{"name": "t", "steps": [{"id": "s", "checks": ["map_markers"]}]}')
	if not parsed.error.contains("replay: needed by the map_markers check"):
		return "a step without a replay gave '%s'" % parsed.error
	return ""


## The four generated m3 steps list `map_markers` in `m3.json` (#912) and, flown
## by the runner in a main scene holding the map as on the headset, pass it:
## the reactor was marked on every tick after it died. The flights are the
## shared m3 run (`m3_suite_run.gd`, #1139).
func test_the_generated_m3_replays_mark_the_reactor_once_it_dies() -> String:
	for id: String in GENERATED_STEPS:
		var listed: AcceptanceStep = SeedPick.find_step(id)
		if listed == null:
			return "m3 has no step %s" % id
		if not listed.has_check(AcceptanceStep.CHECK_MAP_MARKERS):
			return "%s does not list map_markers: %s" % [id, listed.checks]
		var problem: String = M3Run.step_problem(id)
		if problem != "":
			return problem
		var step: Dictionary = M3Run.step(id)
		var measured: Dictionary = step["measurements"]
		var dead: int = int(measured.get("map_markers_dead_ticks", 0))
		if dead < 1 or int(measured.get("map_markers_reactor_shown_dead_ticks", -1)) != dead \
				or not str(step["message"]).contains("map_markers: exit marked"):
			return "%s measured %s: %s" % [id, measured, step["message"]]
	return ""


func test_a_clean_hand_fed_run_passes() -> String:
	var measured: Dictionary = {}
	var result: Array = AcceptanceMapMarkersCheck.judge(_run_samples(), measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "a clean run failed: %s" % result[1]
	if int(measured["map_markers_dead_ticks"]) != 90 or int(measured["map_markers_reactor_shown_dead_ticks"]) != 90:
		return "measured %s" % measured
	if not str(result[1]).contains("from its death on tick 10"):
		return "the message does not name the death: %s" % result[1]
	return ""


func test_a_reactor_missing_after_its_death_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[40]["reactor_shown"] = false
	return _fails_with(taken, "tick 40: the reactor marker is hidden 30 ticks after the reactor died")


func test_a_hidden_exit_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[3]["exit_shown"] = false
	return _fails_with(taken, "tick 3: the exit marker is hidden")


func test_an_unknown_living_reactor_may_stay_hidden() -> String:
	var taken: Array[Dictionary] = _run_samples()
	for i: int in 10:
		taken[i]["reactor_shown"] = false
	var result: Array = AcceptanceMapMarkersCheck.judge(taken, {})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "a reactor not yet found failed the check: %s" % result[1]
	return ""


func test_a_reactor_that_never_dies_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	for sample: Dictionary in taken:
		sample["reactor_dead"] = false
	return _fails_with(taken, "the reactor never died while the replay flew")


func test_no_samples_fail() -> String:
	var result: Array = AcceptanceMapMarkersCheck.judge([] as Array[Dictionary], {})
	if result[0] == AcceptanceReport.RESULT_PASS or not str(result[1]).contains("the scene holds no map"):
		return "no samples gave %s" % [result]
	return ""


## Ticks 0..99: the exit is marked throughout, the reactor dies on tick 10 and
## is marked from then on.
static func _run_samples() -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for tick: int in 100:
		taken.append({"tick": tick, "exit_shown": true, "reactor_dead": tick >= 10, "reactor_shown": tick >= 10})
	return taken


static func _fails_with(taken: Array[Dictionary], text: String) -> String:
	var result: Array = AcceptanceMapMarkersCheck.judge(taken, {})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]) != text:
		return "wanted '%s', got %s" % [text, result]
	return ""
