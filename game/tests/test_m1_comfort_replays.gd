extends RefCounted

## The m1 steps `comfort_preset_1` and `comfort_preset_2` (#697, CMF-1, CMF-3,
## CMF-8, ARC-3, DEV-6, decision record 0005, umbrella #153). Each flies its
## own replay, recorded by `m1_comfort_source.gd` with every input passed
## through `ComfortWiring.hand_input` under the step's preset, so the stored
## inputs are the snaps and capped turns the headset would fly. Each step has
## its own hash: the filtered inputs differ, so the flights do (ARC-3 is shown
## by presets 3 and 4 on `flight_axes`, see `test_m1_comfort_steps.gd`).
##
## Re-recording one or both, from the repository root (see `record_switch.gd`):
##
##     MELTDOWN_RECORD_M1=comfort_preset_1,comfort_preset_2 godot --headless --path game -s res://tests/run_tests.gd
##
## It overwrites the replays and prints the new hashes; paste each into
## `expected_hash` of its step in `acceptance/suites/m1.json`.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const RAW_REPLAY_PATH: String = "res://acceptance/replays/m1_flight_axes.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M1"
const PRESETS: Array[int] = [1, 2]
const RUN_SEED: int = 697
const RecordSwitch := preload("res://tests/record_switch.gd")
const ComfortSource := preload("res://tests/m1_comfort_source.gd")
const Main := preload("res://main.gd")
const MAX_TICKS: int = 4000
const FRAME_LIMIT: int = 8000
## The steps that were in m1 before these two, in order (#686, #687).
const EARLIER_IDS: Array[String] = ["basic_flight", "refresh_rate", "frame_budget", "flight_axes",
	"comfort_preset_3", "comfort_preset_4"]


static func step_id(preset_number: int) -> String:
	return "comfort_preset_%d" % preset_number


static func replay_path(preset_number: int) -> String:
	return "res://acceptance/replays/m1_comfort_preset_%d.replay" % preset_number


## Flies the pilot in the empty test tunnel with the main scene's walls and
## tuning, every input handed through the comfort wiring of `preset_number`
## as the main scene does each frame, one tick a frame. Returns [session, pilot].
static func record(preset_number: int) -> Array:
	var pilot: ComfortSource = ComfortSource.new()
	var latest: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(RUN_SEED, latest, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH))
	var wiring: ComfortWiring = ComfortWiring.new(latest, ThumbstickMapping.new())
	wiring.set_preset(preset_number)
	pilot.sim = session.sim
	while not pilot.done() and session.sim.tick < MAX_TICKS:
		var raw: ShipInput = pilot.next_input(session.sim.tick)
		wiring.hand_input(raw, session.current_ship().orientation, raw.reset_to_start)
		session.advance(ShipState.TICK_DT)
		wiring.end_one_tick_if_flown(session.ticks_last_advance)
	return [session, pilot]


static func _suite_steps() -> Dictionary:
	var found: Dictionary = {}
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		found[step.id] = step
	return found


## Off unless RECORD_SWITCH is `1` or lists a step id; see the top of this file.
func test_record_when_asked() -> String:
	for preset_number: int in PRESETS:
		if not RecordSwitch.asks_for(RECORD_SWITCH, step_id(preset_number)):
			continue
		var session: LocalSession = record(preset_number)[0]
		session.replay.expected_hash = session.sim.state_hash()
		var path: String = replay_path(preset_number)
		var error: Error = session.replay.save(ProjectSettings.globalize_path(path))
		if error != OK:
			return "could not write %s: %s" % [path, error_string(error)]
		print("Meltdown: recorded %s: %d ticks, hash %d; put the hash in %s" % [
			path, session.sim.tick, session.replay.expected_hash, SUITE_PATH])
	return ""


## The recorder still produces each stored flight, so a re-record changes
## nothing unless the data did.
func test_the_recorder_reproduces_both_replays() -> String:
	for preset_number: int in PRESETS:
		var session: LocalSession = record(preset_number)[0]
		var replay: Replay = Replay.load_file(replay_path(preset_number))
		if replay.error != "":
			return replay.error
		if session.sim.state_hash() != replay.expected_hash or session.replay.frames.size() != replay.frames.size():
			return "preset %d: the recorder flies %d ticks to %d; the replay %d ticks to %d" % [preset_number,
				session.replay.frames.size(), session.sim.state_hash(), replay.frames.size(), replay.expected_hash]
	return ""


## The stored inputs are the filter's: preset 1 turns only by 30° snaps in
## pitch and yaw, preset 2 never past its caps; both still turn about.
func test_the_replays_hold_filtered_turns() -> String:
	for preset_number: int in PRESETS:
		var preset: ComfortPreset = ComfortPresetFiles.load_number(preset_number)
		var snap: int = ComfortInputFilter.new(preset).snap_rate_q()
		var replay: Replay = Replay.load_file(replay_path(preset_number))
		if replay.error != "":
			return replay.error
		var turning: int = 0
		for frame: Array in replay.frames:
			var turn: Vector3i = (frame[0] as ShipInput).turn_q
			turning += 1 if turn.x != 0 or turn.y != 0 else 0
			if preset_number == 1 and ((turn.x != 0 and absi(turn.x) != snap) or (turn.y != 0 and absi(turn.y) != snap)):
				return "preset 1 flies a turn of %s, not a snap of %d" % [turn, snap]
			if preset_number == 2 and (absi(turn.y) > ComfortInputFilter.cap_q(preset.yaw_rate_cap_deg_per_s)
					or absi(turn.x) > ComfortInputFilter.cap_q(preset.pitch_rate_cap_deg_per_s)):
				return "preset 2 flies %s past its caps" % turn
		if turning == 0:
			return "preset %d never turns" % preset_number
	return ""


## The two steps follow the earlier ones (later steps, such as #762's, may follow
## them), which keep their order and hashes,
## and each flies its own replay under its own preset on that replay's hash.
func test_the_steps_fly_their_own_replays() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var ids: Array[String] = []
	for step: AcceptanceStep in suite.steps:
		ids.append(step.id)
	# Later steps (view_not_flat, #737; afterburner, #775; reset_to_start, #776) may follow these eight.
	if ids.slice(0, EARLIER_IDS.size() + 2) != EARLIER_IDS + [step_id(1), step_id(2)]:
		return "m1 steps %s" % [ids]
	var found: Dictionary = _suite_steps()
	if found[EARLIER_IDS[3]].expected_hash != 3139276631 or found[EARLIER_IDS[4]].expected_hash != 3139276631:
		return "an earlier step's hash changed"
	for preset_number: int in PRESETS:
		var step: AcceptanceStep = found[step_id(preset_number)]
		if step.replay_path != replay_path(preset_number) or step.preset != preset_number:
			return "%s flies %s on preset %d" % [step.id, step.replay_path, step.preset]
		if step.checks != [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_COMFORT_MOTION,
				AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
			return "%s checks %s" % [step.id, step.checks]
		var replay: Replay = Replay.load_file(step.replay_path)
		if replay.error != "" or step.expected_hash != replay.expected_hash:
			return "%s expects %d, its replay %d %s" % [step.id, step.expected_hash, replay.expected_hash, replay.error]
	return ""


## Both steps pass in the real main scene and fail with a changed hash.
## Preset 1's view only ever jumps; preset 2's turns smoothly but under its caps.
func test_the_steps_pass_in_the_main_scene() -> String:
	var found: Dictionary = _suite_steps()
	for preset_number: int in PRESETS:
		var step: AcceptanceStep = found.get(step_id(preset_number))
		if step == null:
			return "m1 has no step %s" % step_id(preset_number)
		var report: Array = _run_step(step)
		if report[0] != AcceptanceRunner.EXIT_PASS:
			return "%s exit %d: %s" % [step.id, report[0], report[1]]
		var measured: Dictionary = report[2]
		if preset_number == 1 and (int(measured.get("snap_frames", 0)) == 0
				or int(measured.get("smooth_rotation_frames", -1)) != 0):
			return "%s measured %s" % [step.id, measured]
		if preset_number == 2 and int(measured.get("smooth_rotation_frames", 0)) == 0:
			return "%s never turned smoothly: %s" % [step.id, measured]
		var wrong: AcceptanceStep = found[step_id(preset_number)]
		wrong.expected_hash += 1
		var failed: Array = _run_step(wrong)
		if failed[0] == AcceptanceRunner.EXIT_PASS or not str(failed[1]).contains("final hash"):
			return "%s with a wrong hash gave exit %d: %s" % [step.id, failed[0], failed[1]]
	return ""


## The preset 1 step on the raw `flight_axes` replay (on that replay's hash)
## fails `comfort_motion`: the check is what tells the two flights apart.
func test_the_preset_1_step_fails_on_the_raw_replay() -> String:
	var found: Dictionary = _suite_steps()
	var step: AcceptanceStep = found.get(step_id(1))
	if step == null:
		return "m1 has no step %s" % step_id(1)
	step.replay_path = RAW_REPLAY_PATH
	step.expected_hash = found[EARLIER_IDS[3]].expected_hash
	var report: Array = _run_step(step)
	if report[0] == AcceptanceRunner.EXIT_PASS or not str(report[1]).contains("smoothly") \
			or report[2].get("final_hash") != step.expected_hash:
		return "the raw replay on preset 1 gave exit %d: %s" % [report[0], report[1]]
	return ""


## [exit code, messages and step results, the step's measurements] of the
## runner flying `step` alone in the main scene.
func _run_step(step: AcceptanceStep) -> Array:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, null)
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
	if runner.main != null:
		runner.main.free()
	runner.free()
	return [code, text, measurements]


func _on_quit(_code: int) -> void:
	pass
