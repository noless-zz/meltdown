class_name AcceptanceRunStep
extends RefCounted

## A step that flies a run (#989, RUN-1, DEV-6, decision record 0005). In a suite:
##
##     {"id": "run_advances", "run": 12345, "replay": "res://...",
##      "checks": ["final_hash", "level_hash", "outcome", "run_advances"],
##      "expected_next_level_hash": 123, ...}
##
## `run` names the run seed. The step's replay flies the run's first level,
## built from `RunPlan`'s level 1 seed as `seed` would build it, so the
## `level_hash`, `final_hash` and `outcome` checks work as on a seed step. A
## step lists `run`, `seed` or `level`, not two of them.
##
## The `run_advances` check then does what the escape screen's restart press
## does (`main.gd`'s `restart_level`) and judges the level the run flies next:
## its source must be `RunPlan`'s level 2 seed and its level hash
## `expected_next_level_hash`. It swaps the scene's session, so it must be the
## step's last check: the checks before it read the flown level's end.
##
## It also judges the run's profile statistics (#1092, CRW-2): after the
## press they must count the one run started and the level escaped, and no
## loss or win (`STATS_AFTER_ESCAPE`).
##
## A level change in one step is all this adds; the press itself (fade, hold,
## A button) stays human-checked in the headset (#950). The `shaft_choice`
## check (#990, `AcceptanceShaftChoiceCheck`) takes the same fields and goes
## through the shaft panel instead; a step lists one of the two.

const KEY_RUN: String = "run"
const KEY_NEXT_HASH: String = "expected_next_level_hash"
## The statistics a run's profile holds once its first level was escaped (#1092).
const STATS_AFTER_ESCAPE: Dictionary = {"runs_started": 1, "levels_escaped": 1, "deepest_level": 1,
	"runs_won": 0, "runs_lost": 0}
## The check file's check that opens the shaft choice to look at it (#1320).
const CHECK_SHAFT_CHOICE_LOOK: String = "shaft_choice_look"
## The check file's check that hears the shaft choice's sounds (#1455).
const CHECK_SHAFT_SOUNDS: String = "shaft_sounds"
## The check file's check that opens the dev menu at the shaft choice (#1450).
const CHECK_MENU_AT_SHAFT: String = "menu_at_shaft"
## The checks that press on to the run's next level; a step lists at most one.
const MOVING_CHECKS: Array[String] = [AcceptanceStep.CHECK_RUN_ADVANCES, AcceptanceStep.CHECK_SHAFT_CHOICE,
	AcceptanceStep.CHECK_COMPONENTS_BANK, AcceptanceStep.CHECK_CREW_JOINS,
	AcceptanceStep.CHECK_CRAFT_AND_FIT, AcceptanceStep.CHECK_SUSPEND_RESUME, AcceptanceStep.CHECK_ABANDON_RUN]
## The moving checks that fly the level with drops and rescue on and judge the
## profile, not the next level's hash (#1028, #1084, #1246).
const RULES_CHECKS: Array[String] = [AcceptanceStep.CHECK_COMPONENTS_BANK, AcceptanceStep.CHECK_CREW_JOINS,
	AcceptanceStep.CHECK_ABANDON_RUN]


## Reads `run` and `expected_next_level_hash` into `step`; "" or the problem,
## with the field named. Runs after the step's replay, seed, level and checks are read.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var moves: String = moving_check(step)
	# components_bank and crew_joins move on too, but judge the profile, and
	# craft_and_fit the loadout, not the next level's hash (#1028, #1084, #1093).
	var wants: bool = moves != "" and not RULES_CHECKS.has(moves) and moves != AcceptanceStep.CHECK_CRAFT_AND_FIT
	var moving: Array[String] = []
	for check: String in MOVING_CHECKS:
		if step.has_check(check):
			moving.append(check)
	if moving.size() > 1:
		return "%s.checks: %s both move the scene to the next level; a step lists one" % [field,
			" and ".join(moving)]
	if moves != "" and step.checks[-1] != moves:
		return "%s.checks: %s must be the last check; it moves the scene to the next level" % [field, moves]
	if not data.has(KEY_RUN):
		if moves != "":
			return "%s.%s: needed by the %s check" % [field, KEY_RUN, moves]
		if data.has(KEY_NEXT_HASH):
			return "%s.%s: only used by a run step" % [field, KEY_NEXT_HASH]
		return ""
	var where: String = "%s.%s" % [field, KEY_RUN]
	var value: Variant = data[KEY_RUN]
	if not AcceptanceStepParser.is_whole(value) or float(value) < 0.0 \
			or float(value) > AcceptanceStepParser.MAX_EXACT_INT:
		return "%s: must be a whole number from 0 to %d" % [where, int(AcceptanceStepParser.MAX_EXACT_INT)]
	if step.replay_path == "":
		return "%s: only used with a replay, which the step does not list" % where
	if data.has("seed") or data.has("level"):
		return "%s: a step flies a run, a seed or a level file, not two of them" % where
	var plan: RunPlan = plan_for(int(value))
	if plan.error != "":
		return "%s: %s" % [where, plan.error]
	step.run_seed = int(value)
	step.level_seed = plan.level_seed(0)
	if wants:
		if not data.has(KEY_NEXT_HASH):
			return "%s.%s: needed by the %s check" % [field, KEY_NEXT_HASH, moves]
		var next: Variant = data[KEY_NEXT_HASH]
		if not AcceptanceStepParser.is_whole(next) or float(next) < 0.0 \
				or float(next) > AcceptanceStepParser.MAX_EXACT_INT:
			return "%s.%s: must be a whole number from 0 to %d" % [field, KEY_NEXT_HASH,
				int(AcceptanceStepParser.MAX_EXACT_INT)]
		step.expected_next_level_hash = int(next)
	elif data.has(KEY_NEXT_HASH):
		return "%s.%s: only used by the %s check, which the step does not list" % [field, KEY_NEXT_HASH,
			AcceptanceStep.CHECK_RUN_ADVANCES]
	return ""


## The check of `step` that moves the scene to the run's next level, or "".
static func moving_check(step: AcceptanceStep) -> String:
	for check: String in MOVING_CHECKS:
		if step.has_check(check):
			return check
	return ""


## The plan for `run_seed` from the shipped run file.
static func plan_for(run_seed: int) -> RunPlan:
	return RunPlan.build(run_seed, FileAccess.get_file_as_string(RunWiring.RUN_FILE))


## Before a step flies: a run step's run becomes the scene's, kept in memory
## only (no profile is read or saved); any other step flies without a run.
## The run has the shipped shafts only for a shaft_choice, suspend_resume,
## shaft_choice_look, shaft_sounds or menu_at_shaft step (#990, #1107, #1320,
## #1455, #1450); the
## run_advances step pins the run's own level order, as a run without a shaft
## file flies it. A step with `next_replay` (#1065) has the shafts and flies
## with drops on, as does a step with the collected check.
static func begin(main: Node, step: AcceptanceStep) -> void:
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if level_start == null:
		return
	var flies_on: bool = step.next_replay_path != ""  # Into a chosen shaft's level (#1065).
	level_start.run = RunWiring.new(step.run_seed, null, Callable(), "",
		step.has_check(AcceptanceStep.CHECK_SHAFT_CHOICE) or step.has_check(AcceptanceStep.CHECK_SUSPEND_RESUME)
		or step.has_check(CHECK_SHAFT_CHOICE_LOOK) or step.has_check(CHECK_SHAFT_SOUNDS)
		or step.has_check(CHECK_MENU_AT_SHAFT) or flies_on) \
		if step.run_seed != AcceptanceStep.NO_SEED else null
	if level_start.run != null:
		level_start.run.level_rules = RULES_CHECKS.has(moving_check(step)) \
			or step.has_check(AcceptanceStep.CHECK_COLLECTED) or flies_on  # #1028, #1065, #1084.
		AcceptanceFittedStart.begin(level_start.run, step)  # Scratch stores or the plain ship (#1057).
		level_start.source = level_start.run.level_source()
	if destroyed != null:
		destroyed.escape.run = level_start.run


## [result, message] for the run_advances check: presses on from the flown
## level as the escape screen's restart does and judges the level loaded.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if level_start == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var ended: LocalSession = main.get("session")
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's level ended %s, not escaped" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome())]
	var run: RunWiring = level_start.run
	main.call("restart_level")
	var stats: Dictionary = run.profile.stats.to_dict()
	measurements["stats"] = JSON.stringify(stats, "", true)
	for key: String in STATS_AFTER_ESCAPE:
		if stats[key] != STATS_AFTER_ESCAPE[key]:
			return [AcceptanceReport.RESULT_FAIL, "the statistics count %s %d, expected %d" % [key, stats[key],
				STATS_AFTER_ESCAPE[key]]]
	var want: String = LevelSwitch.SEED_PREFIX + str(plan_for(step.run_seed).level_seed(1))
	var session: LocalSession = main.get("session")
	var actual: int = AcceptanceStepLevel.level_hash(session.replay)
	measurements["next_level_source"] = level_start.source
	measurements["next_level_hash"] = actual
	if level_start.source != want:
		return [AcceptanceReport.RESULT_FAIL, "the run flies %s next, expected %s" % [level_start.source, want]]
	if actual != step.expected_next_level_hash:
		return [AcceptanceReport.RESULT_FAIL, "next level hash %d, expected %d: the level's data changed" % [
			actual, step.expected_next_level_hash]]
	return [AcceptanceReport.RESULT_PASS, "level 2 flies %s, level hash %d; the statistics count it" % [
		want, actual]]
