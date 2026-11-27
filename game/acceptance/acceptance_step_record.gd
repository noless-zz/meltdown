class_name AcceptanceStepRecord
extends RefCounted

## Records a finished step's result in its suite's report (DEV-6): from its checks once it ends,
## or as failed when it runs past its time limit (#1444, `AcceptanceTimeLimit`). Kept apart from
## `AcceptanceRunner` so the runner stays short.


## Runs the step's checks, puts back what the step changed in the scene (#851) and adds the
## step to `report`. Returns the step's result.
static func record(runner: AcceptanceRunner, step: AcceptanceStep, checks: AcceptanceChecks,
		report: AcceptanceReport) -> String:
	var outcomes: Array[String] = []
	var notes: PackedStringArray = PackedStringArray()
	var measurements: Dictionary = {}
	var problem: String = runner.level_problem if runner.level_problem != "" \
		else AcceptanceStepLevel.replay_problem(step, runner.replay_source)
	if problem != "":
		outcomes.append(AcceptanceReport.RESULT_FAIL)
		notes.append(problem)
	for check: String in step.checks:
		var outcome: Array = checks.run(check, step, runner, measurements)
		outcomes.append(outcome[0])
		notes.append("%s: %s" % [check, outcome[1]])
	checks.end_step(runner.main)
	var result: String = AcceptanceReport.combine(outcomes)
	report.add_step(step.id, result, "; ".join(notes), measurements, runner.screenshots.finish_step())
	return result


## Fails `step`, stuck past `limit_seconds`, with the tick it reached, and puts back what it
## changed, so the runner can go on to the next step. Its checks are not run: a stuck step's
## state proves nothing. Returns the failure message.
static func time_out(runner: AcceptanceRunner, step: AcceptanceStep, checks: AcceptanceChecks,
		report: AcceptanceReport, limit_seconds: float) -> String:
	var session: Variant = runner.main.get("session") if runner.main != null else null
	var tick: int = (session as LocalSession).sim.tick if session is LocalSession else 0
	if runner.replay_source != null:
		runner.replay_source.finish()
		runner.replay_source = null
	if runner.main != null:
		runner.main.set_process(true)  # The runner switched it off while the replay flew.
	checks.end_step(runner.main)
	var text: String = AcceptanceTimeLimit.message(limit_seconds, tick)
	report.add_step(step.id, AcceptanceReport.RESULT_FAIL, text, {}, runner.screenshots.finish_step())
	return text
