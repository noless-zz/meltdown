extends RefCounted

## The m6 `launch_fade` step (#1396, CRW-2, CMF-1, CMF-8, decision record
## 0005): after the replay a lost run opens the base, the room fades in, the
## launch station's launch row glows the cradle ship with one launch sound,
## the next level starts behind a full fade and the mine fades in, with the
## camera still throughout.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const STEP_ID: String = "launch_fade"
## The idle replay, the destroyed screen's fade, the restart and the launch.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


func test_the_step_launches_from_the_base_through_the_fade() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.reports.is_empty() or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif runner.reports[0].steps.size() != 1:
		problem = "the suite has %d launch_fade steps" % runner.reports[0].steps.size()
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("dark_at_level_start") != 1.0 or measured.get("launch_sounds") != 1 \
				or float(measured.get("glow_peak", 0.0)) < 1.0:
			problem = "measured %s" % measured
		elif (runner.main.get("hub") as HubWiring).is_open():
			problem = "the check left the hub open"
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
