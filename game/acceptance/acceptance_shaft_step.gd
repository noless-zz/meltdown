class_name AcceptanceShaftStep
extends RefCounted

## A run step that flies a second level (#1065, RUN-1, CRF-7, DEV-6, decision
## record 0005). In a suite:
##
##     {"id": "shaft_rewards", "run": 12345, "replay": "res://...",
##      "shaft": 0, "next_replay": "res://...",
##      "checks": ["outcome", "collected"], "expected_collected": {...}}
##
## The step's `replay` flies the run's first level as any run step does. Once
## it ends, the step takes shaft `shaft` (an index into the run's offer after
## level 1) through the shaft panel's own path: `ShaftChoiceWiring.open` moves
## the run on and banks, `RunWiring.choose` takes the shaft, and the scene's
## `restart_level` flies the chosen shaft's level. `next_replay` (inputs only)
## then flies that level, built by `LevelStart.session_for` exactly as the
## game builds it, with the shaft's robot scale and reward weights. Every check
## the step lists judges the end of that second level.
##
## Both levels fly with component drops and miner rescue on
## (`RunWiring.level_rules`), as `--run` flies them. A step without `shaft`
## and `next_replay` is unchanged. The step moves the scene itself, so it lists
## none of the checks that press on to the next level
## (`AcceptanceRunStep.MOVING_CHECKS`).

const KEY_SHAFT: String = "shaft"
const KEY_NEXT_REPLAY: String = "next_replay"


## Reads `shaft` and `next_replay` into `step`; "" or the problem, naming the
## field and the step. Runs after `AcceptanceRunStep.parse_step`.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has(KEY_SHAFT) and not data.has(KEY_NEXT_REPLAY):
		return ""
	for pair: Array in [[KEY_SHAFT, KEY_NEXT_REPLAY], [KEY_NEXT_REPLAY, KEY_SHAFT]]:
		if not data.has(pair[1]):
			return "%s.%s: needed with %s" % [field, pair[1], pair[0]]
	var value: Variant = data[KEY_NEXT_REPLAY]
	if typeof(value) != TYPE_STRING or str(value) == "":
		return "%s.%s: must be a non-empty path" % [field, KEY_NEXT_REPLAY]
	if step.run_seed == AcceptanceStep.NO_SEED:
		return "%s.%s: only used by a run step, which names %s" % [field, KEY_SHAFT, AcceptanceRunStep.KEY_RUN]
	var moving: String = AcceptanceRunStep.moving_check(step)
	if moving != "":
		return "%s.checks: %s presses on to the next level, which %s already flies; a step lists one" % [
			field, moving, KEY_NEXT_REPLAY]
	var index: Variant = data[KEY_SHAFT]
	if not AcceptanceStepParser.is_whole(index) or float(index) < 0.0:
		return "%s.%s: must be a whole number from 0" % [field, KEY_SHAFT]
	var offered: Array[String] = offer_for(step.run_seed)
	if float(index) >= offered.size():
		return "%s.%s: step %s picks shaft %d, but run %d offers %d after level 1 (%s)" % [field, KEY_SHAFT,
			step.id, int(index), step.run_seed, offered.size(), ", ".join(offered)]
	step.shaft_index = int(index)
	step.next_replay_path = value
	return ""


## The shafts run `run_seed` offers after its first level, in the panel's
## order, from the shipped run and shaft files; empty when either is rejected.
static func offer_for(run_seed: int) -> Array[String]:
	var plan: RunPlan = AcceptanceRunStep.plan_for(run_seed)
	var shafts: ShaftOffer = ShaftOffer.build(FileAccess.get_file_as_string(RunWiring.SHAFTS_FILE))
	if plan.error != "" or shafts.error != "" or plan.level_count() < 2:
		return []
	var state: RunState = RunState.new(plan, shafts)
	state.advance({})
	return state.offer()


## Called by `runner` once the step's current replay ends: true, with the
## runner flying `next_replay`, the first time for a step that has one. A
## problem goes to `runner.level_problem`, and the step is then recorded.
static func flies_on(runner: AcceptanceRunner, step: AcceptanceStep, checks: AcceptanceChecks) -> bool:
	if step.next_replay_path == "" or checks.next_started or runner.level_problem != "":
		return false
	checks.next_started = true
	var next: Array = fly_next(runner.main, step)
	runner.level_problem = next[0]
	if next[1] == null:
		return false
	runner.replay_source = next[1]
	return true


## After the step's first replay: takes the step's shaft and gives `main` a
## session on its level fed by `next_replay`. Returns [problem, source]: "" and
## the source flying it, or why it cannot fly and null.
static func fly_next(main: Node, step: AcceptanceStep) -> Array:
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if level_start == null or destroyed == null or level_start.run == null or not level_start.run.active():
		return ["the scene flies no run", null]
	var ended: LocalSession = main.get("session")
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return ["level 1 ended %s, not escaped, so no shaft was chosen" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome()), null]
	var run: RunWiring = level_start.run
	var choice: ShaftChoiceWiring = destroyed.escape.choice
	if not choice.open(run, ended.sim.collected.duplicate()):
		return ["no shaft choice was due after level 1", null]
	var offered: Array[String] = choice.model.kinds.duplicate()
	if step.shaft_index >= offered.size():
		choice.close()
		return ["%s: shaft %d is outside the %d offered (%s)" % [KEY_SHAFT, step.shaft_index, offered.size(),
			", ".join(offered)], null]
	if not run.choose(offered[step.shaft_index]):
		choice.close()
		return ["the run refused shaft %s" % offered[step.shaft_index], null]
	choice.close()
	main.call("restart_level")
	AcceptanceStepLevel.clear_end_screens(main)
	var replay: Replay = Replay.load_file(step.next_replay_path)
	if replay.error != "":
		return ["%s %s: %s" % [KEY_NEXT_REPLAY, step.next_replay_path, replay.error], null]
	if replay.ship_count != 1:
		return ["%s %s: has %d ships; the scene flies one" % [KEY_NEXT_REPLAY, step.next_replay_path,
			replay.ship_count], null]
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var session: LocalSession = level_start.session_for(main as Node3D, level_start.source, source)
	if session == null:
		return ["the chosen shaft's level %s was rejected" % level_start.source, null]
	main.set("session", session)
	var meltdown: MeltdownWiring = main.get("meltdown") as MeltdownWiring
	if meltdown != null:
		meltdown.attach(main as Node3D, session)
	return ["", source]
