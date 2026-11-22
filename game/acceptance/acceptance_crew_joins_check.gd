class_name AcceptanceCrewJoinsCheck
extends RefCounted

## The `crew_joins` check of a run step (#1084, CRW-1, SLV-3, DEV-6, decision
## record 0005). In a suite:
##
##     {"id": "crew_joins", "run": 12345, "replay": "res://...",
##      "checks": ["final_hash", "outcome", "crew_joins"], "expected_crew": 1}
##
## Like `AcceptanceComponentsBankCheck`, a step with this check flies its run's
## level with component drops and miner rescue on (`RunWiring.level_rules`),
## as `--run` flies it. Its replay is the bot pilot's flight with a rescue goal
## (`BotRescue`): it holds at a trapped miner before shooting the reactor and
## escapes. The check then presses on as the escape screen's restart does,
## which adds the rescued miners to the run's profile through
## `RunWiring.after_level`, and compares the crew's size, kept in memory only,
## with `expected_crew`. It swaps the scene's session, so it is the step's last
## check; a step lists one of the moving checks (`AcceptanceRunStep`).

const KEY: String = "expected_crew"
## Above any crew a run could rescue; only a guard against a mistyped number.
const MAX_CREW: int = 1000


## Reads `expected_crew` into `step`; "" or the problem, with the field named.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var where: String = "%s.%s" % [field, KEY]
	if not step.has_check(AcceptanceStep.CHECK_CREW_JOINS):
		return "%s: only used by the %s check, which the step does not list" % [where,
			AcceptanceStep.CHECK_CREW_JOINS] if data.has(KEY) else ""
	if not data.has(KEY):
		return "%s: needed by the %s check" % [where, AcceptanceStep.CHECK_CREW_JOINS]
	var value: Variant = data[KEY]
	if not AcceptanceStepParser.is_whole(value) or float(value) < 1.0 or float(value) > MAX_CREW:
		return "%s: must be a whole number from 1 to %d" % [where, MAX_CREW]
	step.expected_crew = int(value)
	return ""


## [result, message]; `measurements` gets the rescued count and the crew size.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if level_start == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var ended: LocalSession = main.get("session")
	if ended.sim.rescue == null:
		return [AcceptanceReport.RESULT_FAIL, "the run's level flew without miner rescue"]
	measurements["rescued"] = RunWiring.rescued_in(ended.sim)
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's level ended %s, not escaped" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome())]
	var run: RunWiring = level_start.run
	main.call("restart_level")
	var crew: int = run.profile.crew.size()
	measurements["crew"] = crew
	if run.error != "" or run.crew_error != "":
		return [AcceptanceReport.RESULT_FAIL, "the escape added no crew: %s" %
			(run.error if run.error != "" else run.crew_error)]
	return judge(crew, measurements["rescued"], step.expected_crew)


## [result, message] for a crew of `crew` after an escape that rescued `rescued`.
static func judge(crew: int, rescued: int, expected: int) -> Array:
	if crew != expected:
		return [AcceptanceReport.RESULT_FAIL, "crew %d after the escape (%d rescued), expected %d" % [
			crew, rescued, expected]]
	return [AcceptanceReport.RESULT_PASS, "%d rescued, the crew is %d" % [rescued, crew]]
