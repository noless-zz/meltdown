extends RefCounted

## The m6 `pickup_marks_shown` acceptance check (#1375, DEV-6): judged on fed
## views, listed on lane-b's `pickup_marks` step in `suites/m6/effects.json`,
## which flies m4's `crew_joins` flight on its pinned hash, and passing when
## that step is flown in the main scene.

const PickupMarksCheck := preload("res://acceptance/checks/pickup_marks_check.gd")
const PART_PATH: String = "res://acceptance/suites/m6/effects.json"
const M4_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "pickup_marks"
## The escape takes about 10,500 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 25000


## A view pair after one heap taken at its heap and one miner boarded, both run out.
static func _played() -> Array:
	var marks: PickupMarks = PickupMarks.new()
	var heaps: Array[Vector3] = [Vector3(1, 0, -4)]
	marks.start(Vector3(1, 0, -4), Color.WHITE, heaps)
	var leave: MinerLeave = MinerLeave.new()
	leave.configure({}, BoxMesh.new(), MinerPod.new())
	leave.start(Vector3(0, 0, -1), true)
	for frame: int in 120:
		marks.advance(1.0 / 60.0)
		leave.advance(1.0 / 60.0, null)
	return [marks, leave]


static func _free(played: Array) -> void:
	(played[0] as Node).free()
	(played[1] as Node).free()


func test_marks_and_a_boarding_that_ran_their_course_pass() -> String:
	var played: Array = _played()
	var verdict: Array = PickupMarksCheck.judge(played[0], played[1], 2, 1)
	_free(played)
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else "verdict %s" % [verdict]


func test_a_flight_without_a_mark_or_a_boarding_fails() -> String:
	var played: Array = _played()
	var no_rescue: Array = PickupMarksCheck.judge(played[0], played[1], 2, 2)
	var none: Array = PickupMarksCheck.judge(played[0], played[1], 0, 1)
	_free(played)
	var fresh: PickupMarks = PickupMarks.new()
	var leave: MinerLeave = MinerLeave.new()
	var unmarked: Array = PickupMarksCheck.judge(fresh, leave, 2, 1)
	fresh.free()
	leave.free()
	for verdict: Array in [no_rescue, none, unmarked]:
		if verdict[0] != AcceptanceReport.RESULT_FAIL:
			return "verdict %s" % [verdict]
	return ""


func test_a_mark_off_its_heap_or_still_drawn_fails() -> String:
	var played: Array = _played()
	(played[0] as PickupMarks).largest_offset_m = 0.5
	var off: Array = PickupMarksCheck.judge(played[0], played[1], 2, 1)
	_free(played)
	played = _played()
	(played[0] as PickupMarks).start(Vector3.ZERO, Color.WHITE)
	(played[0] as PickupMarks).advance(0.0)
	var drawn: Array = PickupMarksCheck.judge(played[0], played[1], 3, 1)
	_free(played)
	if off[0] != AcceptanceReport.RESULT_FAIL or drawn[0] != AcceptanceReport.RESULT_FAIL:
		return "verdicts %s and %s" % [off, drawn]
	return ""


func test_the_step_flies_crew_joins_on_its_hash() -> String:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return "%s does not hold the %s step" % [PART_PATH, STEP_ID]
	var step: AcceptanceStep = _shipped_step()
	var m4: AcceptanceStep = null
	for found: AcceptanceStep in AcceptanceSuite.load_file(M4_PATH).steps:
		if found.id == "crew_joins":
			m4 = found
	if step == null or m4 == null:
		return "steps found: m6 %s, m4 crew_joins %s" % [step, m4]
	if step.replay_path != m4.replay_path or step.run_seed != m4.run_seed or step.expected_hash != m4.expected_hash:
		return "the step flies run %d from %s on %d" % [step.run_seed, step.replay_path, step.expected_hash]
	if not step.checks.has(AcceptanceStep.CHECK_FINAL_HASH):
		return "the step checks %s" % [step.checks]
	# crew_joins turns drops and rescue on and moves the scene on, so the marks are read first.
	var at: int = step.checks.find(PickupMarksCheck.CHECK)
	if at < 0 or at > step.checks.find(AcceptanceStep.CHECK_CREW_JOINS):
		return "the step checks %s" % [step.checks]
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
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var code: int = runner.exit_code if runner.finished else -1
	if runner.main != null:
		runner.main.free()
	runner.free()
	if code != AcceptanceRunner.EXIT_PASS:
		return "the step did not pass (exit %d): %s" % [code, text]
	return ""


static func _shipped_step() -> AcceptanceStep:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return null
	for step: AcceptanceStep in found[0].steps:
		if step.id == STEP_ID:
			return step
	return null
