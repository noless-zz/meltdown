extends RefCounted

## The m6 `pickup_look` step (#1308, GFX-2, SLV-1, SLV-3, CRF-1, DEV-6): the
## owner's G6 "screenshots approved" check needs the new pickups on record, so
## the step flies m4's `crew_joins` flight (run 12345, drops and rescue on),
## with screenshots where the ship faces a dropped needle gun at 7 m (tick
## 360), a cell salts heap at 9 m (990), a pulse cannon and needle gun (1230),
## an arc lance (5670) and the trapped miner at 8 m (7230). Its pinned hash is
## m4 `crew_joins`'s, so the look leaves the simulation alone (ARC-1, ARC-2).
## Only cell salts drop on this level, so the other kinds' shapes are judged
## by `test_pickup_looks.gd` and in the headset, not by this step.

const PART_PATH: String = "res://acceptance/suites/m6/ship.json"
const M4_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "pickup_look"
const M4_STEP_ID: String = "crew_joins"
const REPLAY: String = "res://acceptance/replays/crew_joins.replay"
## The escape takes about 10,500 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 25000


static func _step_from(steps: Array[AcceptanceStep], id: String) -> AcceptanceStep:
	for found: AcceptanceStep in steps:
		if found.id == id:
			return found
	return null


static func _shipped_step() -> AcceptanceStep:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return null
	return _step_from(found[0].steps, STEP_ID)


func test_the_step_flies_the_crew_joins_flight_with_screenshots() -> String:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return "%s does not hold the %s step" % [PART_PATH, STEP_ID]
	var step: AcceptanceStep = _shipped_step()
	var m4: AcceptanceStep = _step_from(AcceptanceSuite.load_file(M4_PATH).steps, M4_STEP_ID)
	if step == null or m4 == null:
		return "steps found: m6 %s %s, m4 %s %s" % [STEP_ID, step, M4_STEP_ID, m4]
	if step.replay_path != REPLAY or step.run_seed != m4.run_seed:
		return "the step flies run %d from %s" % [step.run_seed, step.replay_path]
	if step.expected_hash != m4.expected_hash:
		return "the step pins %d, not m4 %s's %d" % [step.expected_hash, M4_STEP_ID, m4.expected_hash]
	if not step.checks.has(AcceptanceStep.CHECK_FINAL_HASH) or not step.checks.has(AcceptanceStep.CHECK_NO_SCRIPT_ERRORS):
		return "the step checks %s" % [step.checks]
	if step.screenshot_ticks.size() < 4:
		return "the step takes %d screenshots" % step.screenshot_ticks.size()
	var replay: Replay = Replay.load_file(REPLAY)
	for tick: int in step.screenshot_ticks:
		if tick >= replay.frames.size():
			return "screenshot tick %d is past the replay's %d ticks" % [tick, replay.frames.size()]
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
