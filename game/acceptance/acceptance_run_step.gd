class_name AcceptanceRunStep
extends RefCounted

## A step that flies a run (#989, RUN-1, DEV-6, decision record 0005): `run`
## names the run seed. The step's replay flies the run's first level, started
## through the scene's `RunWiring` exactly as `--run=<n>` starts it, so the
## level is `RunPlan`'s first seed built by `SeedLevel`. The `run_advances`
## check then presses restart as the pilot does on the escape screen and checks
## that the scene now flies the plan's second level: its seed, and its level
## hash against `expected_next_level_hash`.
##
## One step covers one level change. Whether each escape reads as progress in
## the headset stays a human check on the gate (#950).

const KEY_RUN: String = "run"
const KEY_NEXT_LEVEL_HASH: String = "expected_next_level_hash"
## Re-records the m4 run step (`test_m4_run_step.gd`).
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"


## Reads `run` and `expected_next_level_hash` into `step`; "" or the problem,
## naming the field. A run step builds its own levels, so it names no level
## file and no seed.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wants_hash: bool = step.has_check(AcceptanceStep.CHECK_RUN_ADVANCES)
	if data.has(KEY_RUN):
		var value: Variant = data[KEY_RUN]
		if not AcceptanceStepParser.is_whole(value) or float(value) < 0.0 \
				or float(value) > AcceptanceStepParser.MAX_EXACT_INT:
			return "%s.%s: must be a whole number from 0" % [field, KEY_RUN]
		if not data.has("replay"):
			return "%s.%s: only used with a replay, which the step does not list" % [field, KEY_RUN]
		if data.has("level") or data.has("seed"):
			return "%s.%s: a step flies a level file, a seed or a run, not two" % [field, KEY_RUN]
		step.run_seed = int(value)
	elif wants_hash:
		return "%s.%s: needed by the %s check" % [field, KEY_RUN, AcceptanceStep.CHECK_RUN_ADVANCES]
	if not data.has(KEY_NEXT_LEVEL_HASH):
		return "%s.%s: needed by the %s check" % [field, KEY_NEXT_LEVEL_HASH,
			AcceptanceStep.CHECK_RUN_ADVANCES] if wants_hash else ""
	if not wants_hash:
		return "%s.%s: only used by the %s check, which the step does not list" % [field, KEY_NEXT_LEVEL_HASH,
			AcceptanceStep.CHECK_RUN_ADVANCES]
	var hash: Variant = data[KEY_NEXT_LEVEL_HASH]
	if not AcceptanceStepParser.is_whole(hash) or float(hash) < 0.0 or float(hash) > AcceptanceStepParser.MAX_EXACT_INT:
		return "%s.%s: must be a whole number from 0" % [field, KEY_NEXT_LEVEL_HASH]
	step.expected_next_level_hash = int(hash)
	return ""


## The seed the step's replay flies: its `seed`, or for a run step the run's
## first level, starting the run in `main` (`start`).
static func level_seed(main: Node, step: AcceptanceStep) -> int:
	return start(main, step) if step.run_seed != AcceptanceStep.NO_SEED else step.level_seed


## Builds `level_seed`'s level for the replay (`AcceptanceStepLevel.fly_seed`);
## "" or why it cannot fly, naming the run when it did not start.
static func fly(main: Node, step: AcceptanceStep, p_level_seed: int, replay: Replay, source: ReplayInputSource,
		overrides: Dictionary) -> String:
	if p_level_seed == AcceptanceStep.NO_SEED:
		return "run %d: the scene could not start it" % step.run_seed
	return AcceptanceStepLevel.fly_seed(main, p_level_seed, replay, source, overrides)


## Starts `step`'s run in `main` and gives the first level's seed, or
## `AcceptanceStep.NO_SEED` when the scene has no run wiring or the run did not
## start.
static func start(main: Node, step: AcceptanceStep) -> int:
	var wiring: RunWiring = main.get("run") as RunWiring
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if wiring == null or level_start == null:
		return AcceptanceStep.NO_SEED
	level_start.source = wiring.begin(LevelSwitch.RUN_PREFIX + str(step.run_seed),
		destroyed.escape if destroyed != null else null)
	if not level_start.source.begins_with(LevelSwitch.SEED_PREFIX):
		return AcceptanceStep.NO_SEED
	return LevelSwitch.seed_from(level_start.source.substr(LevelSwitch.SEED_PREFIX.length()))


## The `run_advances` check: after the replay escaped the run's first level,
## the restart press flies the plan's second level. The scene is left flying
## no run, as before the step.
static func run_advances(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var wiring: RunWiring = main.get("run") as RunWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if wiring == null or level_start == null or not wiring.is_active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var session: LocalSession = main.get("session")
	if session.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's first level ended %s, not ESCAPED" %
			AcceptanceStateChecks.outcome_name(session.sim.outcome())]
	var plan: RunPlan = wiring.state.plan
	main.call("restart_level")  # What the escape screen's restart press does.
	var wanted: String = LevelSwitch.SEED_PREFIX + str(plan.level_seed(1))
	var source: String = level_start.source
	var depth: int = wiring.state.current_depth()
	var next: LocalSession = main.get("session")
	var hash: int = AcceptanceStepLevel.level_hash(next.replay)
	measurements["run_next_source"] = source
	measurements["run_next_level_hash"] = hash
	wiring.state = null
	level_start.source = ""
	if source != wanted or depth != 2:
		return [AcceptanceReport.RESULT_FAIL, "the restart flew '%s' at depth %d, expected %s at depth 2" % [
			source, depth, wanted]]
	if hash != step.expected_next_level_hash:
		return [AcceptanceReport.RESULT_FAIL, "level 2 hash %d, expected %d: the level's data changed; if intended, re-record from the repository root with %s=%s godot --headless --path game -s res://tests/run_tests.gd" % [
			hash, step.expected_next_level_hash, RECORD_SWITCH, step.id]]
	return [AcceptanceReport.RESULT_PASS, "run %d level 2 is %s, level hash %d" % [plan.run_seed, source, hash]]
