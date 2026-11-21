class_name AcceptanceComponentsBankCheck
extends RefCounted

## The `components_bank` check of a run step (#1028, CRF-1, CRF-2, DEV-6,
## decision record 0005). In a suite:
##
##     {"id": "components_bank", "run": 12345, "replay": "res://...",
##      "checks": ["final_hash", "outcome", "components_bank"],
##      "expected_banked": {"cell_salts": 1}}
##
## Only a step with this check flies its run's level with component drops and
## miner rescue on (`RunWiring.level_rules`), as `--run` flies it; every other
## run step keeps them off, so its pinned hashes stand. After the replay
## escapes, the check presses on as the escape screen's restart does, which
## banks the sim's `collected` counts through `RunWiring.after_level`, and
## compares the run's profile, kept in memory only, with `expected_banked`.
## Like run_advances it swaps the scene's session, so it is the step's last
## check; a step lists one of the three.

const KEY: String = "expected_banked"


## Reads `expected_banked` into `step`; "" or the problem, with the field named.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var where: String = "%s.%s" % [field, KEY]
	if not step.has_check(AcceptanceStep.CHECK_COMPONENTS_BANK):
		return "%s: only used by the %s check, which the step does not list" % [where,
			AcceptanceStep.CHECK_COMPONENTS_BANK] if data.has(KEY) else ""
	if not data.has(KEY):
		return "%s: needed by the %s check" % [where, AcceptanceStep.CHECK_COMPONENTS_BANK]
	var value: Variant = data[KEY]
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).is_empty():
		return "%s: must be an object of component id to count" % where
	var counts: Dictionary[String, int] = {}
	for kind: Variant in value:
		var count: Variant = value[kind]
		if not AcceptanceStepParser.is_whole(count) or float(count) < 1.0 \
				or float(count) > AcceptanceStepParser.MAX_EXACT_INT:
			return "%s.%s: must be a whole number from 1" % [where, str(kind)]
		counts[str(kind)] = int(count)
	step.expected_banked = counts
	return ""


## [result, message]; `measurements` gets the collected and banked counts.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if level_start == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var ended: LocalSession = main.get("session")
	if ended.sim.component_rules == null:
		return [AcceptanceReport.RESULT_FAIL, "the run's level flew without component drops"]
	measurements["collected"] = JSON.stringify(ended.sim.collected, "", true)
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's level ended %s, not escaped" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome())]
	var run: RunWiring = level_start.run
	main.call("restart_level")
	var banked: Dictionary[String, int] = run.profile.banked
	measurements["banked"] = JSON.stringify(banked, "", true)
	if run.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the escape did not bank: %s" % run.error]
	if banked != step.expected_banked:
		return [AcceptanceReport.RESULT_FAIL, "banked %s, expected %s" % [measurements["banked"],
			JSON.stringify(step.expected_banked, "", true)]]
	return [AcceptanceReport.RESULT_PASS, "the escape banked %s" % measurements["banked"]]
