extends RefCounted

## The m1 `no_stale_overlay` step (#1439, DEV-6, CMF-3, CMF-8): after the
## comfort and hit steps, once nothing that needs it is happening, no
## full-view overlay may still cover the view, and a fault names the overlay
## and its opacity.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "no_stale_overlay"
const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/stale_overlay_check.gd")
## The destroyed replay of the hit step before it, and the check's frames.
const FRAME_LIMIT: int = 20000


func test_the_step_runs_after_the_comfort_and_hit_steps() -> String:
	var ids: Array[String] = []
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		ids.append(step.id)
	var at: int = ids.find(STEP_ID)
	if at < 0:
		return "m1 has no step %s" % STEP_ID
	for earlier: String in ["comfort_preset_1", "comfort_preset_4", "comfort_preset_1_destroyed",
			"comfort_hits_preset_2", "comfort_hits_preset_3", "comfort_hits_preset_4"]:
		if ids.find(earlier) < 0 or ids.find(earlier) > at:
			return "%s does not run before %s: %s" % [earlier, STEP_ID, ids]
	if ids.find("focus_pause") < at:
		return "%s runs after focus_pause: %s" % [STEP_ID, ids]
	return ""


## Run after the last hit step, as in m1, the step passes headless: the
## restart leaves no fade, vignette or hit flash over the view.
func test_the_step_passes_after_the_last_hit_step() -> String:
	var runner: AcceptanceRunner = _run(["comfort_hits_preset_4", STEP_ID])
	var problem: String = ""
	if runner.reports.is_empty() or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var entry: Dictionary = runner.reports[0].steps[-1]
		var measured: Dictionary = entry["measurements"]
		if int(measured.get("idle_frames_judged", 0)) <= 0 \
				or not (measured.get("highest_opacity", {}) as Dictionary).has("fade"):
			problem = "measured %s" % measured
	_done(runner)
	return problem


## A fade left at 0.6 with nothing in progress fails, naming the overlay and its opacity.
func test_a_fade_left_over_fails_naming_it() -> String:
	var main: Node = _main()
	var reset_hold: ResetHold = main.get("reset_hold") as ResetHold
	reset_hold.alpha = 0.6  # Idle, yet still dark: what a fade that never finished leaves.
	var verdict: Array = CHECK_SCRIPT.judge_scene(main, {})
	main.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("fade at opacity 0.600"):
		return "gave %s" % [verdict]
	return ""


## While the session is held, the overlays are not judged; a pause that never
## lifts fails saying so rather than passing.
func test_a_pause_is_in_progress_and_never_judged() -> String:
	var main: Node = _main()
	(main.get("session") as LocalSession).paused = true
	var verdict: Array = CHECK_SCRIPT.judge_scene(main, {})
	main.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("pause"):
		return "gave %s" % [verdict]
	return ""


func test_stale_overlays_are_named_with_their_opacity() -> String:
	var text: String = CHECK_SCRIPT.stale_overlays({"fade": 0.0, "vignette": 0.25, "hit_flash": 0.0004})
	return "" if text == "vignette at opacity 0.250" else "gave '%s'" % text


static func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _run(ids: Array[String]) -> AcceptanceRunner:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for id: String in ids:
		for found: AcceptanceStep in suite.steps:
			if found.id == id:
				kept.append(found)
	suite.steps = kept
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup(_main(), suites, null)
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


## A scene that was never set up draws no overlay: skipped, not failed.
func test_a_scene_never_set_up_is_skipped() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var verdict: Array = CHECK_SCRIPT.judge_scene(main, {})
	main.free()
	return "" if verdict[0] == AcceptanceReport.RESULT_SKIPPED else "gave %s" % [verdict]
