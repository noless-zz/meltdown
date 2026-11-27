extends RefCounted

## The m6 `render_scale` step (#1417, GFX-7, PRF-2, decision record 0005):
## run through the acceptance runner in the main scene, the shipped table has
## scaling off (#1503), the scripted slow and fast frames leave the scale at
## 1.0, and the flat scene's own render scale stays 1.0.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const STEP_ID: String = "render_scale"
## No replay flies: the step is judged within a few frames.
const FRAME_LIMIT: int = 2000

var _quit_codes: Array[int] = []


func test_the_step_holds_the_scale_at_full_while_off() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.reports.is_empty() or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif runner.reports[0].steps.size() != 1:
		problem = "the suite has %d render_scale steps" % runner.reports[0].steps.size()
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("render_scale_enabled", true) != false or float(measured.get("render_scale_lowest", 0.0)) != 1.0 \
				or int(measured.get("render_scale_changes", -1)) != 0:
			problem = "measured %s" % measured
		elif RenderScaler.in_use != 1.0:
			problem = "the flat scene's scale is %s" % RenderScaler.in_use
	_done(runner)
	return problem


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run() -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			kept.append(found)
	suite.steps = kept
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
