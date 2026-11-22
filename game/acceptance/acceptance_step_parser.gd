class_name AcceptanceStepParser
extends RefCounted

## Reads and checks one step of an acceptance suite file (DEV-6, ARC-4), kept
## apart from `AcceptanceSuite`, which reads the file and its list of steps, so
## that file stays short as checks add fields (#817).
##
## `level` names a level file the scene switches to before the replay flies.
## `seed` (#460) instead names a generated level: a whole number from 0 up,
## built by `SeedLevel` from the shipped data files exactly as `--seed=<n>`
## builds it, so its replay holds only the inputs and the level is never stored
## in it. A step lists at most one of the two, and either needs a replay.
## `expected_level_hash` goes with the `level_hash` check, as `expected_hash`
## goes with `final_hash`, and pins the level a seed builds. The
## `frame_budget` check needs `settle_seconds`, `measure_seconds`,
## `max_over_budget_share` and `budget_slack_ms` (`AcceptanceFrameBudgetCheck`).
## `screenshot_at_ticks` and `screenshot_at_end` save screenshots while the
## replay flies (`AcceptanceScreenshots`). `view_not_flat` needs `view_seconds`.
## `preset_changes` (#777) lists `{"tick": <n>, "preset": <1..4>}` in rising
## tick order, each inside the replay: the preset changes mid-flight there
## (`AcceptancePresetChanges`), after starting on `preset`.
## `pause_at_tick` and `pause_seconds` (#804) take the headset off at that tick
## for that long, for the held_while_paused check (`AcceptancePauseCheck`).
## `custom_file` (#836) names a shipped custom comfort file the step flies in
## the custom mode of, in place of `preset` (`AcceptanceCustomComfort`).
## `loop_replay` (#788, default false) restarts the replay from its first tick
## each time it ends until those seconds pass; it needs frame_budget, not
## final_hash (`AcceptanceLoopReplay`).
## `controls` (#818) flies a file of raw controller values through the scene's
## mapping in place of the replay's inputs, left-handed when `left_handed` is
## true (`AcceptanceControlsScript`).
## `refresh_120` (#851) turns the pilot's 120 Hz option on for the step only,
## with a numbered preset and a refresh_rate or frame_budget check
## (`AcceptanceRefresh120`).
## `run` (#989) flies a run's first level in place of `seed` or `level`, and
## `expected_next_level_hash` goes with the run_advances or shaft_choice check
## (`AcceptanceRunStep`, `AcceptanceShaftChoiceCheck`). `expected_banked`
## goes with the components_bank check (`AcceptanceComponentsBankCheck`, #1028).
## `shaft` and `next_replay` (#1065) fly a run step on into a chosen shaft's
## level (`AcceptanceShaftStep`); `expected_collected` goes with the collected
## check (`AcceptanceCollectedCheck`). `profile` and `fitting` (#1057) point a
## run step at scratch stores (`AcceptanceFittedStart`).
## `expected_crew` goes with the crew_joins check (`AcceptanceCrewJoinsCheck`, #1084).
##
## A field a step does not know, a check not in `AcceptanceStep.KNOWN_CHECKS` or
## a bad value is answered with the field named, as `steps[<n>].<key>: ...`.

const STEP_KEYS: Array[String] = ["id", "replay", "preset", "checks", "expected_hash", "required",
	"level", "expected_outcome", "seed", "expected_level_hash", AcceptanceLoopReplay.KEY, "settle_seconds",
	"measure_seconds", "max_over_budget_share", "budget_slack_ms", AcceptanceScreenshots.KEY_TICKS,
	AcceptanceScreenshots.KEY_END,
	AcceptanceViewFlatCheck.KEY_SECONDS, "flight_test_answers", "expected_preset",
	AcceptancePresetChanges.KEY, AcceptancePauseCheck.KEY_TICK, AcceptancePauseCheck.KEY_SECONDS,
	AcceptancePauseCheck.KEY_BY,
	AcceptanceControlsScript.KEY_CONTROLS, AcceptanceControlsScript.KEY_LEFT_HANDED,
	AcceptanceCustomComfort.KEY, AcceptanceRefresh120.KEY, AcceptanceRunStep.KEY_RUN,
	AcceptanceRunStep.KEY_NEXT_HASH, AcceptanceComponentsBankCheck.KEY, AcceptanceShaftStep.KEY_SHAFT,
	AcceptanceShaftStep.KEY_NEXT_REPLAY, AcceptanceCollectedCheck.KEY, AcceptanceFittedStart.KEY_PROFILE,
	AcceptanceFittedStart.KEY_FITTING,
	AcceptanceCrewJoinsCheck.KEY]
## Largest whole number a JSON double holds exactly; a hash above it could not
## be compared reliably.
const MAX_EXACT_INT: float = 9007199254740992.0


## Fills `step` from `raw`, the step at `field` (`steps[<n>]`), and returns
## "" or the first problem, naming its field.
static func parse(raw: Variant, field: String, step: AcceptanceStep) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "%s: must be a JSON object" % field
	var data: Dictionary = raw
	var problem: String = unknown_key(data, STEP_KEYS, field + ".")
	if problem != "":
		return problem
	if typeof(data.get("id")) != TYPE_STRING or str(data["id"]) == "":
		return "%s.id: must be a non-empty string" % field
	step.id = data["id"]
	if data.has("replay"):
		if typeof(data["replay"]) != TYPE_STRING or str(data["replay"]) == "":
			return "%s.replay: must be a non-empty path" % field
		step.replay_path = data["replay"]
	if data.has("preset"):
		if not is_whole(data["preset"]):
			return "%s.preset: must be a whole number" % field
		step.preset = int(data["preset"])
		if step.preset < AcceptanceStep.MIN_PRESET or step.preset > AcceptanceStep.MAX_PRESET:
			return "%s.preset: %d is outside %d..%d" % [
				field, step.preset, AcceptanceStep.MIN_PRESET, AcceptanceStep.MAX_PRESET]
	if data.has("level"):
		if typeof(data["level"]) != TYPE_STRING or LevelSwitch.path_for(str(data["level"])) == "":
			return "%s.level: must be a level name of a-z, 0-9 and '_'" % field
		if not data.has("replay"):
			return "%s.level: only used with a replay, which the step does not list" % field
		step.level = data["level"]
	problem = _parse_seed(data, field, step)
	if problem != "":
		return problem
	if data.has("required"):
		if typeof(data["required"]) != TYPE_BOOL:
			return "%s.required: must be true or false" % field
		step.required = data["required"]
	problem = _parse_checks(data.get("checks"), field + ".checks", step)
	if problem != "":
		return problem
	for check: String in step.checks:
		if (AcceptanceStep.REPLAY_CHECKS.has(check) or check == AcceptanceStep.CHECK_COMFORT_MOTION
				or check == AcceptanceStep.CHECK_HIT_VIEW_MOTION or check == AcceptanceStep.CHECK_ESCAPE_SCREEN
				or check == AcceptanceStep.CHECK_MAP_ROUTE or check == AcceptanceStep.CHECK_ESCAPE_CUE
				or check == AcceptanceStep.CHECK_MAP_MARKERS or check == AcceptanceStep.CHECK_VIGNETTE
				or check == AcceptanceStep.CHECK_RUN_ADVANCES or check == AcceptanceStep.CHECK_SHAFT_CHOICE
				or check == AcceptanceStep.CHECK_COMPONENTS_BANK or check == AcceptanceStep.CHECK_COLLECTED \
				or check == AcceptanceStep.CHECK_CREW_JOINS or check == AcceptanceStep.CHECK_CRAFT_AND_FIT \
				or check == AcceptanceStep.CHECK_SUSPEND_RESUME or check == AcceptanceStep.CHECK_ABANDON_RUN) \
				and step.replay_path == "":
			return "%s.replay: needed by the %s check" % [field, check]
	problem = _parse_expected_hash(data, field, step)
	if problem == "":
		problem = _parse_expected_level_hash(data, field, step)
	if problem == "":
		problem = AcceptanceFrameBudgetCheck.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceLoopReplay.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceScreenshots.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceViewFlatCheck.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceFlightTestCheck.parse_step(data, field, step)
	if problem == "":
		problem = AcceptancePresetChanges.parse_step(data, field, step)
	if problem == "":
		problem = AcceptancePauseCheck.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceControlsScript.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceCustomComfort.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceRefresh120.parse_step(data, field, step)
	if problem == "":
		problem = AcceptanceRunStep.parse_step(data, field, step)  # #989.
	if problem == "":
		problem = AcceptanceComponentsBankCheck.parse_step(data, field, step)  # #1028.
	if problem == "":
		problem = AcceptanceShaftStep.parse_step(data, field, step)  # #1065.
	if problem == "":
		problem = AcceptanceCollectedCheck.parse_step(data, field, step)  # #1065.
	if problem == "":
		problem = AcceptanceFittedStart.parse_step(data, field, step)  # #1057.
	if problem == "":
		problem = AcceptanceCrewJoinsCheck.parse_step(data, field, step)  # #1084.
	if problem == "":
		problem = AcceptanceCraftAndFitCheck.parse_step(field, step)  # #1093.
	return problem if problem != "" else _parse_expected_outcome(data, field, step)


## A generated level is built from its seed alone, so a step cannot also name
## a level file for it.
static func _parse_seed(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has("seed"):
		return ""
	var value: Variant = data["seed"]
	if not is_whole(value) or float(value) < 0.0 or float(value) > MAX_EXACT_INT:
		return "%s.seed: must be a whole number from 0 to %d" % [field, int(MAX_EXACT_INT)]
	if not data.has("replay"):
		return "%s.seed: only used with a replay, which the step does not list" % field
	if data.has("level"):
		return "%s.seed: a step flies a level file or a seed, not both" % field
	step.level_seed = int(value)
	return ""


static func _parse_checks(raw: Variant, field: String, step: AcceptanceStep) -> String:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return "%s: must be a list of at least one check" % field
	var raw_checks: Array = raw
	for index: int in raw_checks.size():
		var check: Variant = raw_checks[index]
		if typeof(check) != TYPE_STRING or not AcceptanceStep.KNOWN_CHECKS.has(check):
			return "%s[%d]: unknown check '%s', known: %s" % [
				field, index, str(check), ", ".join(AcceptanceStep.KNOWN_CHECKS)]
		if step.checks.has(check):
			return "%s[%d]: '%s' is listed twice" % [field, index, check]
		step.checks.append(check)
	return ""


## The final_hash check needs both a replay to fly and the hash it must end
## with; a hash without the check would be read and then never compared.
static func _parse_expected_hash(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wants_hash: bool = step.has_check(AcceptanceStep.CHECK_FINAL_HASH)
	if not data.has("expected_hash"):
		return "%s.expected_hash: needed by the final_hash check" % field if wants_hash else ""
	if not wants_hash:
		return "%s.expected_hash: only used by the final_hash check, which the step does not list" % field
	var value: Variant = data["expected_hash"]
	if not is_whole(value) or float(value) < 0.0 or float(value) > MAX_EXACT_INT:
		return "%s.expected_hash: must be a whole number from 0 to %d" % [field, int(MAX_EXACT_INT)]
	if step.replay_path == "":
		return "%s.replay: needed by the final_hash check" % field
	step.expected_hash = int(value)
	return ""


## Like the final hash: the level_hash check and its value come together.
static func _parse_expected_level_hash(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wants_hash: bool = step.has_check(AcceptanceStep.CHECK_LEVEL_HASH)
	if not data.has("expected_level_hash"):
		return "%s.expected_level_hash: needed by the level_hash check" % field if wants_hash else ""
	if not wants_hash:
		return "%s.expected_level_hash: only used by the level_hash check, which the step does not list" % field
	var value: Variant = data["expected_level_hash"]
	if not is_whole(value) or float(value) < 0.0 or float(value) > MAX_EXACT_INT:
		return "%s.expected_level_hash: must be a whole number from 0 to %d" % [field, int(MAX_EXACT_INT)]
	step.expected_level_hash = int(value)
	return ""


## Like the hash: the outcome check and `expected_outcome` come together, and
## the outcome is named, so a suite reads "ESCAPED" rather than an enum number.
static func _parse_expected_outcome(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wants_outcome: bool = step.has_check(AcceptanceStep.CHECK_OUTCOME)
	if not data.has("expected_outcome"):
		return "%s.expected_outcome: needed by the outcome check" % field if wants_outcome else ""
	if not wants_outcome:
		return "%s.expected_outcome: only used by the outcome check, which the step does not list" % field
	var value: Variant = data["expected_outcome"]
	if typeof(value) != TYPE_STRING or not ExitRule.Outcome.has(str(value)):
		return "%s.expected_outcome: must be one of %s" % [field, ", ".join(ExitRule.Outcome.keys())]
	step.expected_outcome = ExitRule.Outcome[str(value)]
	return ""


## The first key of `data` not in `allowed`, named after `prefix`, or "".
static func unknown_key(data: Dictionary, allowed: Array[String], prefix: String) -> String:
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return "%s%s: unknown key" % [prefix, str(key)]
	return ""


## JSON numbers arrive as floats. A bool must not pass as 0 or 1.
static func is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and float(value) == floorf(value)
