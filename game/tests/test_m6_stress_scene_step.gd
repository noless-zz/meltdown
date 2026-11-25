extends RefCounted

## The m6 `stress_scene` step (#1288, PRF-1 to PRF-3, PRF-8, G6): lane-a's perf
## part flies the stress level with ship 0's script, measures frame times with
## the frame_budget check (skipped off the headset) and judges the scene with
## the stress_scene check. Flown here through the runner in the main scene, so
## CI sees the step pass everywhere but the headset's frame times.

const PART_PATH: String = "res://acceptance/suites/m6/perf.json"
const STEP_ID: String = "stress_scene"
## The replay is 5,600 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 8000


static func _shipped_step() -> AcceptanceStep:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return null
	for step: AcceptanceStep in found[0].steps:
		if step.id == STEP_ID:
			return step
	return null


func test_the_step_measures_the_stress_level_for_60_seconds() -> String:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return "%s does not hold the %s step" % [PART_PATH, STEP_ID]
	var step: AcceptanceStep = _shipped_step()
	if step == null:
		return "m6 has no %s step" % STEP_ID
	if step.level != "stress" or step.measure_seconds != 60.0:
		return "the step flies level \"%s\" for %s s" % [step.level, step.measure_seconds]
	for check: String in ["frame_budget", "stress_scene", "final_hash", "no_script_errors"]:
		if not step.checks.has(check):
			return "the step does not list %s" % check
	return ""


func test_the_shipped_step_passes_in_the_main_scene() -> String:
	var step: AcceptanceStep = _shipped_step()
	if step == null:
		return "m6 has no %s step" % STEP_ID
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = "m6"
	suite.steps.append(step)
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var text: String = "\n".join(runner.messages)
	var report: AcceptanceReport = runner.reports[0] if not runner.reports.is_empty() else null
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var code: int = runner.exit_code if runner.finished else -1
	if runner.main != null:
		runner.main.free()
	runner.free()
	if code != AcceptanceRunner.EXIT_PASS or report == null:
		return "the step did not pass (exit %d): %s" % [code, text]
	if not text.contains("stress_scene: 20 robots") or not text.contains("frame_budget: not on the headset"):
		return "the step's report lacks the scene or the skipped frame budget: %s" % text
	return ""
