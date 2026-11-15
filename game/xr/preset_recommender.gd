class_name PresetRecommender
extends RefCounted

## Turns the player's answers to the first-launch flight test into a comfort
## preset (CMF-4). The rule: the preset of the last segment answered `fine`
## before the first `uneasy` or `stop`; no `fine` at all gives preset 1, the
## safest. `stop` ends the test, so nothing may follow it. Fewer answers than
## segments is a test stopped early and is fine.
##
## Unknown answers are an error, not a guess: a wrong guess here would put a
## player who felt sick on a stronger preset.

const FINE: String = "fine"
const UNEASY: String = "uneasy"
const STOP: String = "stop"
const ANSWERS: Array[String] = [FINE, UNEASY, STOP]
## Returned by `recommend` when the plan or answers are invalid.
const INVALID: int = 0


## The recommended preset, 1..4, or `INVALID` when `check` reports a problem.
static func recommend(plan: FlightTestPlan, answers: Array[String]) -> int:
	if check(plan, answers) != "":
		return INVALID
	var recommended: int = FlightTestPlan.MIN_PRESET
	for index: int in answers.size():
		if answers[index] != FINE:
			break
		recommended = plan.segments[index].preset
	return recommended


## Empty when `answers` can be scored against `plan`; otherwise names the
## problem, so the caller can log it instead of silently picking a preset.
static func check(plan: FlightTestPlan, answers: Array[String]) -> String:
	if plan == null:
		return "no plan"
	if plan.error != "":
		return "plan was rejected: %s" % plan.error
	if plan.segments.is_empty():
		return "plan has no segments"
	if answers.size() > plan.segments.size():
		return "%d answers for %d segments" % [answers.size(), plan.segments.size()]
	for index: int in answers.size():
		var answer: String = answers[index]
		if not ANSWERS.has(answer):
			return "answer %d is \"%s\", must be one of %s" % [index, answer, ", ".join(PackedStringArray(ANSWERS))]
		if answer == STOP and index < answers.size() - 1:
			return "answer %d is \"stop\" but %d answers follow it" % [index, answers.size() - 1 - index]
	return ""
