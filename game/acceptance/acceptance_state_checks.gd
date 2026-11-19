class_name AcceptanceStateChecks
extends RefCounted

## The acceptance checks that read the state a step's replay ended in (DEV-6):
## the final hash, whether every robot is destroyed and whether the ship
## survived (gate G2, #334), how the run ended (#376) and whether any debris
## came down and the level was the pinned one (#460), and whether a blast door
## did (#516), and whether any robot fired at the ship from behind a wall
## (#615). Kept apart from `AcceptanceRunner`, which drives
## the frames, so that file stays short. Each check only reads the session.

## The record switch a changed level hash names. Only the m3 suite pins level
## hashes (#494), so its switch is the one.
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"


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
		AcceptanceStep.CHECK_DOOR_FALLEN:
			return door_fallen(step.id, session.sim, measurements)
		AcceptanceStep.CHECK_NO_HIDDEN_HITS:
			return no_hidden_hits(session.replay, measurements)
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


## Counts box entries (blast doors) that are solid. A door the route guard held
## back never came down, so the escape did not have to get past it. The failure
## names the step, since a suite may fly several generated seeds.
static func door_fallen(step_id: String, sim: Sim, measurements: Dictionary) -> Array:
	var doors: int = 0
	var fallen: int = 0
	var count: int = sim.debris.size() if sim.debris != null else 0
	for index: int in count:
		if sim.debris.is_box(index) and not sim.debris.is_fire(index):
			doors += 1
			if sim.debris.is_solid(index):
				fallen += 1
	measurements["doors"] = doors
	measurements["doors_fallen"] = fallen
	if fallen == 0:
		return [AcceptanceReport.RESULT_FAIL, "step %s: none of %d doors fell" % [step_id, doors]]
	return [AcceptanceReport.RESULT_PASS, "%d of %d doors fell" % [fallen, doors]]


## The command, from the repository root, that re-records only step `step_id`
## after an intended data change (#576). `MELTDOWN_RECORD_M3=1` would re-record
## every m3 step, including ones whose recorder no longer reproduces the stored
## flight (#560), so a failure names just the step that failed.
static func record_command(step_id: String) -> String:
	return "%s=%s godot --headless --path game -s res://tests/run_tests.gd" % [RECORD_SWITCH, step_id]


static func level_hash(step: AcceptanceStep, replay: Replay, measurements: Dictionary) -> Array:
	var actual: int = AcceptanceStepLevel.level_hash(replay)
	measurements["level_hash"] = actual
	measurements["expected_level_hash"] = step.expected_level_hash
	if actual != step.expected_level_hash:
		return [AcceptanceReport.RESULT_FAIL, "level hash %d, expected %d: the level's data changed; if intended, re-record from the repository root with %s" % [
			actual, step.expected_level_hash, record_command(step.id)]]
	return [AcceptanceReport.RESULT_PASS, "level hash %d" % actual]


## Flies `replay` again from its header, tick by tick, and fails on the first
## robot shot fired with no clear line (`LineOfSight`) from the robot to the
## ship it fired at, or that crossed a wall on its way (#615). The final state
## cannot tell, so this re-flies; the hash check already pins the flight.
static func no_hidden_hits(replay: Replay, measurements: Dictionary) -> Array:
	# `Replay.run` with no frames is the sim set up from the header, before its
	# first tick; the frames are put back at once and stepped here.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	var shots: int = 0
	var hits: int = 0
	var last: Dictionary[Projectile, Vector3] = {}
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_HIT:
				hits += 1
		var now: Dictionary[Projectile, Vector3] = {}
		for projectile: Projectile in sim.projectiles:
			if not projectile.is_robot_owned():
				continue
			now[projectile] = projectile.position
			if last.has(projectile):
				if not LineOfSight.clear(sim.walls, last[projectile], projectile.position):
					return [AcceptanceReport.RESULT_FAIL, "tick %d: a robot shot crossed a wall" % sim.tick]
				continue
			# Fired this tick, from the robot's centre, at the nearest live ship.
			shots += 1
			var target: ShipState = sim.nearest_live_ship(projectile.position)
			if target != null and not LineOfSight.clear(sim.walls, projectile.position, target.position):
				return [AcceptanceReport.RESULT_FAIL, "tick %d: a robot fired with no line to the ship" % sim.tick]
		last = now
	measurements["robot_shots"] = shots
	measurements["ship_hits"] = hits
	return [AcceptanceReport.RESULT_PASS, "%d robot shots, %d hits, none from behind a wall" % [shots, hits]]
