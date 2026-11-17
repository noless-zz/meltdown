class_name AcceptanceStateChecks
extends RefCounted

## The acceptance checks that read the state a step's replay ended in (DEV-6):
## the final hash, whether every robot is destroyed and whether the ship
## survived (gate G2, #334), how the run ended (#376) and whether any debris
## came down and the level was the pinned one (#460). Kept apart from `AcceptanceRunner`, which drives
## the frames, so that file stays short. Each check only reads the session.


## [result, message] for `check`, one of `AcceptanceStep.REPLAY_CHECKS`, on
## `session` after the replay flew, adding its measurements. `flown` is false
## when no replay could be flown; every such check then fails.
static func run(check: String, step: AcceptanceStep, session: LocalSession, flown: bool,
		measurements: Dictionary) -> Array:
	if not flown or session == null:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	match check:
		AcceptanceStep.CHECK_FINAL_HASH:
			return final_hash(step, session.sim, measurements)
		AcceptanceStep.CHECK_ROBOTS_CLEARED:
			return robots_cleared(session.sim, measurements)
		AcceptanceStep.CHECK_SHIP_ALIVE:
			return ship_alive(session.sim, measurements)
		AcceptanceStep.CHECK_OUTCOME:
			return outcome(step, session.sim, measurements)
		AcceptanceStep.CHECK_DEBRIS_FALLEN:
			return debris_fallen(session.sim, measurements)
		AcceptanceStep.CHECK_LEVEL_HASH:
			return level_hash(step, session.replay, measurements)
	return [AcceptanceReport.RESULT_FAIL, "unknown check"]


static func final_hash(step: AcceptanceStep, sim: Sim, measurements: Dictionary) -> Array:
	var actual: int = sim.state_hash()
	measurements["final_hash"] = actual
	measurements["expected_hash"] = step.expected_hash
	measurements["ticks"] = sim.tick
	if actual != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "final hash %d, expected %d" % [actual, step.expected_hash]]
	return [AcceptanceReport.RESULT_PASS, "final hash %d" % actual]


## Fails naming every robot type still alive, in spawn order, so a report
## says which robot the bot could not beat.
static func robots_cleared(sim: Sim, measurements: Dictionary) -> Array:
	var alive: PackedStringArray = PackedStringArray()
	for robot: RobotState in sim.robots:
		if robot.is_alive():
			alive.append(robot.def.id)
	measurements["robots_alive"] = alive.size()
	if not alive.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "%d robots still alive: %s" % [alive.size(), ", ".join(alive)]]
	return [AcceptanceReport.RESULT_PASS, "no robot left"]


static func ship_alive(sim: Sim, measurements: Dictionary) -> Array:
	var hull: float = sim.ships[0].hull if not sim.ships.is_empty() else 0.0
	measurements["hull"] = hull
	if hull <= 0.0:
		return [AcceptanceReport.RESULT_FAIL, "the ship's hull is %.1f" % hull]
	return [AcceptanceReport.RESULT_PASS, "hull %.1f" % hull]


static func outcome(step: AcceptanceStep, sim: Sim, measurements: Dictionary) -> Array:
	var actual: String = outcome_name(sim.outcome())
	var expected: String = outcome_name(step.expected_outcome)
	measurements["outcome"] = actual
	measurements["expected_outcome"] = expected
	if actual != expected:
		return [AcceptanceReport.RESULT_FAIL, "outcome %s, expected %s" % [actual, expected]]
	return [AcceptanceReport.RESULT_PASS, "outcome %s" % actual]


static func outcome_name(value: int) -> String:
	var key: Variant = ExitRule.Outcome.find_key(value)
	return str(key) if key != null else "none"


## Counts entries that fell or were held back: a held entry did come due, the
## guard only kept it from closing the last way out.
static func debris_fallen(sim: Sim, measurements: Dictionary) -> Array:
	var total: int = sim.debris.size() if sim.debris != null else 0
	var fallen: int = 0
	for index: int in total:
		if sim.debris.is_solid(index) or sim.debris.is_skipped(index):
			fallen += 1
	measurements["debris"] = total
	measurements["debris_fallen"] = fallen
	if fallen == 0:
		return [AcceptanceReport.RESULT_FAIL, "none of %d debris entries fell" % total]
	return [AcceptanceReport.RESULT_PASS, "%d of %d debris entries fell" % [fallen, total]]


static func level_hash(step: AcceptanceStep, replay: Replay, measurements: Dictionary) -> Array:
	var actual: int = AcceptanceStepLevel.level_hash(replay)
	measurements["level_hash"] = actual
	measurements["expected_level_hash"] = step.expected_level_hash
	if actual != step.expected_level_hash:
		return [AcceptanceReport.RESULT_FAIL, "level hash %d, expected %d: the level's data changed" % [
			actual, step.expected_level_hash]]
	return [AcceptanceReport.RESULT_PASS, "level hash %d" % actual]
