extends RefCounted

## The m1 suite's `comfort_preset_1_destroyed` step (#803, CMF-3, CMF-6, CMF-8,
## DEV-6): preset 1 flies m2's destroyed-ship replay, in which the tunnel robots
## hit the ship until it is destroyed (tick 272) and the replay goes on for three
## seconds, through the destroyed screen's one-second fade. CMF-3 allows no
## smooth rotation "including impacts, cutscenes and death", so `comfort_motion`
## must sample all of it and find none; the final hash is m2's, because a preset
## never changes the simulation (CMF-6).
##
## Re-recording m2's replay changes its hash: paste the new hash into both
## `m2.json` and this step in `m1.json` (`test_the_step_shares_m2s_hash`).

const M1_PATH: String = "res://acceptance/suites/m1.json"
const M2_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "comfort_preset_1_destroyed"
const M2_STEP_ID: String = "ship_destroyed_in_test_tunnel"
const REPLAY_PATH: String = "res://acceptance/replays/ship_destroyed_test_tunnel.replay"
const FRAME_LIMIT: int = 4000


static func _find(path: String, id: String) -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(path)
	for step: AcceptanceStep in suite.steps:
		if step.id == id:
			return step
	return null


func test_the_step_is_listed_with_its_preset_and_checks() -> String:
	var step: AcceptanceStep = _find(M1_PATH, STEP_ID)
	if step == null:
		return "m1 has no step %s" % STEP_ID
	if step.preset != 1:
		return "%s flies preset %d" % [STEP_ID, step.preset]
	if step.replay_path != REPLAY_PATH:
		return "%s flies %s" % [STEP_ID, step.replay_path]
	var wanted: Array[String] = [AcceptanceStep.CHECK_COMFORT_MOTION, AcceptanceStep.CHECK_FINAL_HASH,
		AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]
	if step.checks != wanted:
		return "%s checks %s" % [STEP_ID, step.checks]
	return ""


## Presets do not change the simulation (CMF-6): the same replay ends on the same hash.
func test_the_step_shares_m2s_hash() -> String:
	var step: AcceptanceStep = _find(M1_PATH, STEP_ID)
	var m2: AcceptanceStep = _find(M2_PATH, M2_STEP_ID)
	if step == null or m2 == null:
		return "missing step: m1 %s, m2 %s" % [step != null, m2 != null]
	if m2.replay_path != step.replay_path or m2.expected_hash != step.expected_hash:
		return "m1 expects %d from %s, m2 %d from %s" % [step.expected_hash, step.replay_path,
			m2.expected_hash, m2.replay_path]
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "" or replay.expected_hash != step.expected_hash:
		return "the replay holds %d %s" % [replay.expected_hash, replay.error]
	return ""


## The step passes in the main scene, and its comfort samples run past the
## ship's destruction and the whole fade, with hits on the way.
func test_the_step_passes_through_hits_destruction_and_fade() -> String:
	var step: AcceptanceStep = _find(M1_PATH, STEP_ID)
	if step == null:
		return "m1 has no step %s" % STEP_ID
	var report: Array = _run_step(step, null)
	if report[0] != AcceptanceRunner.EXIT_PASS:
		return "exit %d: %s" % [report[0], report[1]]
	var measured: Dictionary = report[2]
	if int(measured.get("smooth_rotation_frames", -1)) != 0 or int(measured.get("comfort_preset", 0)) != 1:
		return "measured %s" % measured
	var wreck: Dictionary = {}
	AcceptanceWreckCheck.run(Replay.load_file(REPLAY_PATH), wreck)
	var destroyed_tick: int = int(wreck.get("destroyed_tick", -1))
	var fade_ticks: int = ceili(DestroyedSequence.load_file().fade_seconds / ShipState.TICK_DT)
	if destroyed_tick <= 0:
		return "the replay's ship is never destroyed: %s" % wreck
	if int(measured.get("comfort_frames", 0)) < destroyed_tick + fade_ticks:
		return "%d comfort frames end before the fade (destroyed at %d, fade %d ticks)" % [
			measured.get("comfort_frames", 0), destroyed_tick, fade_ticks]
	if not _was_hit_before(Replay.load_file(REPLAY_PATH), destroyed_tick):
		return "no hit reached the ship before it was destroyed"
	return ""


## With a stand-in preset 1 whose hits row shakes and spins, the same flight
## fails comfort_motion naming the first frame that turned smoothly: the step
## would catch hit shake reaching preset 1.
func test_a_shaking_preset_1_fails_naming_the_frame() -> String:
	var step: AcceptanceStep = _find(M1_PATH, STEP_ID)
	if step == null:
		return "m1 has no step %s" % STEP_ID
	step.preset = AcceptanceStep.NO_PRESET  # The runner keeps the stand-in set below.
	var stand_in: ComfortPreset = ComfortPresetFiles.load_number(1).duplicate() as ComfortPreset
	stand_in.hit_shake = 1.0
	stand_in.hit_spin = true
	var report: Array = _run_step(step, stand_in)
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS:
		return "a shaking preset 1 passed: %s" % text
	var name_line: RegEx = RegEx.create_from_string("comfort_motion: frame \\d+ turned the view [0-9.]+° smoothly")
	if name_line.search(text) == null:
		return "the failure does not name the frame: %s" % text
	if int(report[2].get("final_hash", -1)) != step.expected_hash:
		return "the shake changed the simulation: %s" % report[2]
	return ""


## Whether ship 0 took a hit from a robot before `tick` when `replay` is re-flown,
## stepped from its header as `AcceptanceWreckCheck` does.
func _was_hit_before(replay: Replay, tick: int) -> bool:
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return false
	for frame: Array in frames:
		if sim.tick >= tick:
			return false
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_HIT and event.ship == 0:
				return true
	return false


## [exit code, messages and results, the step's measurements] of the runner
## flying `step` alone in the main scene; with `stand_in`, preset 1 in the
## scene's comfort wiring is replaced by it before the step starts.
func _run_step(step: AcceptanceStep, stand_in: ComfortPreset) -> Array:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	if stand_in != null:
		var wiring: ComfortWiring = main.get("comfort")
		wiring.set_preset(1)
		wiring.preset = stand_in
		wiring.hit_shake.preset = stand_in
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var code: int = runner.exit_code if runner.finished else -1
	var text: String = "\n".join(runner.messages)
	var measurements: Dictionary = {}
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			text += "\n%s: %s" % [entry["result"], entry["message"]]
			measurements = entry["measurements"]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	runner.main.free()
	runner.free()
	return [code, text, measurements]
