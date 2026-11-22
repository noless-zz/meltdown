class_name AcceptanceCollectedCheck
extends RefCounted

## The `collected` check (#1065, CRF-7, DEV-6, decision record 0005): the
## sim's `collected` component counts when the step's last replay ends are
## exactly `expected_collected`, an object of component id to count (`{}`
## pins that nothing was picked up). On a step with `next_replay`
## (`AcceptanceShaftStep`) that is the chosen shaft's level, so two steps that
## fly the same level 1 into different shafts pin how the shaft's reward
## weights shaped the drops. The level must fly with component drops on.

const KEY: String = "expected_collected"


## Reads `expected_collected` into `step`; "" or the problem, with the field named.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var where: String = "%s.%s" % [field, KEY]
	if not step.has_check(AcceptanceStep.CHECK_COLLECTED):
		return "%s: only used by the %s check, which the step does not list" % [where,
			AcceptanceStep.CHECK_COLLECTED] if data.has(KEY) else ""
	if not data.has(KEY):
		return "%s: needed by the %s check" % [where, AcceptanceStep.CHECK_COLLECTED]
	var value: Variant = data[KEY]
	if typeof(value) != TYPE_DICTIONARY:
		return "%s: must be an object of component id to count" % where
	var counts: Dictionary[String, int] = {}
	for kind: Variant in value:
		var count: Variant = value[kind]
		if not AcceptanceStepParser.is_whole(count) or float(count) < 1.0 \
				or float(count) > AcceptanceStepParser.MAX_EXACT_INT:
			return "%s.%s: must be a whole number from 1" % [where, str(kind)]
		counts[str(kind)] = int(count)
	step.expected_collected = counts
	return ""


## [result, message]; `measurements` gets the counts and, on a run, the level and shaft flown.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var session: LocalSession = main.get("session")
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if level_start != null and level_start.run != null and level_start.run.active():
		measurements["level_source"] = level_start.source
		measurements["shaft"] = level_start.run.state.current_shaft()
	if session.sim.component_rules == null:
		return [AcceptanceReport.RESULT_FAIL, "the level flew without component drops"]
	var actual: Dictionary[String, int] = counts_of(session.sim.collected)
	measurements["collected"] = JSON.stringify(actual, "", true)
	if actual != step.expected_collected:
		return [AcceptanceReport.RESULT_FAIL, "collected %s, expected %s" % [measurements["collected"],
			JSON.stringify(step.expected_collected, "", true)]]
	return [AcceptanceReport.RESULT_PASS, "collected %s" % measurements["collected"]]


## `collected` as typed counts, leaving out ids at zero, so it compares with a pinned object.
static func counts_of(collected: Dictionary) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for kind: Variant in collected:
		if int(collected[kind]) > 0:
			counts[str(kind)] = int(collected[kind])
	return counts
