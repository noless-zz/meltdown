extends RefCounted

## The m1 step `comfort_custom` and the suite field it uses (#836, CMF-1,
## CMF-6, CMF-3, ARC-3, DEV-6): a step names a shipped custom comfort file, the
## runner flies it in the custom mode built from that file, and
## `comfort_motion` judges the view against the custom file's own limits.
##
## The step flies its own replay, recorded like `comfort_preset_1` and
## `comfort_preset_2` (`test_m1_comfort_replays.gd`) by `m1_comfort_source.gd`
## with every input handed through the comfort wiring, here in the custom mode.
## A replay stores the inputs the filter let through and is flown without the
## filter, so `m1_comfort_preset_2.replay`, recorded at preset 2's 60°/s, would
## keep preset 2's hash and break the custom file's lower cap; a test below
## shows it fails. Re-recording, from the repository root:
##
##     MELTDOWN_RECORD_M1=comfort_custom godot --headless --path game -s res://tests/run_tests.gd
##
## It overwrites the replay and prints the new hash; paste it into the step's
## `expected_hash` in `acceptance/suites/m1.json`.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "comfort_custom"
const CUSTOM_PATH: String = "res://acceptance/comfort/m1_custom.json"
const REPLAY_PATH: String = "res://acceptance/replays/m1_comfort_custom.replay"
const PRESET_2_REPLAY_PATH: String = "res://acceptance/replays/m1_comfort_preset_2.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M1"
const RUN_SEED: int = 836
const SCRATCH_PATH: String = "user://test_m1_comfort_custom_rejected.json"
const RecordSwitch := preload("res://tests/record_switch.gd")
const ComfortSource := preload("res://tests/m1_comfort_source.gd")
const Main := preload("res://main.gd")
const MAX_TICKS: int = 4000
const FRAME_LIMIT: int = 8000


## Flies the pilot in the empty test tunnel, every input handed through the
## comfort wiring in the custom mode of CUSTOM_PATH. Returns the session.
static func record() -> LocalSession:
	var pilot: ComfortSource = ComfortSource.new()
	var latest: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(RUN_SEED, latest, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH))
	var wiring: ComfortWiring = ComfortWiring.new(latest, ThumbstickMapping.new())
	wiring.custom_path = CUSTOM_PATH
	wiring.set_preset(ComfortPresetFiles.CUSTOM_NUMBER)
	pilot.sim = session.sim
	while not pilot.done() and session.sim.tick < MAX_TICKS:
		var raw: ShipInput = pilot.next_input(session.sim.tick)
		wiring.hand_input(raw, session.current_ship().orientation, raw.reset_to_start)
		session.advance(ShipState.TICK_DT)
		wiring.end_one_tick_if_flown(session.ticks_last_advance)
	return session


static func _m1_step(id: String = STEP_ID) -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == id:
			return step
	return null


## Off unless RECORD_SWITCH is `1` or lists `comfort_custom`; see the top.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()
	session.replay.expected_hash = session.sim.state_hash()
	var error: Error = session.replay.save(ProjectSettings.globalize_path(REPLAY_PATH))
	if error != OK:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(error)]
	print("Meltdown: recorded %s: %d ticks, hash %d; put the hash in %s" % [
		REPLAY_PATH, session.sim.tick, session.replay.expected_hash, SUITE_PATH])
	return ""


## The shipped sample is accepted whole, on base preset 2, with at least two
## rows changed from it: a lower yaw cap and the vignette off.
func test_the_sample_file_changes_two_rows_of_preset_2() -> String:
	var custom: ComfortCustom = ComfortCustom.load_from(CUSTOM_PATH)
	if custom.preset == null or custom.error != "" or custom.base != 2:
		return "sample: base %d, error '%s'" % [custom.base, custom.error]
	var base: ComfortPreset = ComfortPresetFiles.load_number(2)
	var changed: Array[String] = []
	for field: String in ComfortCustom.settable_fields():
		if field != ComfortCustom.FIELD_NAME and custom.preset.get(field) != base.get(field):
			changed.append(field)
	if changed.size() < 2:
		return "only %s differ from preset 2" % [changed]
	if custom.preset.yaw_rate_cap_deg_per_s >= base.yaw_rate_cap_deg_per_s or custom.preset.vignette_strength != 0.0:
		return "yaw cap %.1f, vignette %.2f" % [custom.preset.yaw_rate_cap_deg_per_s, custom.preset.vignette_strength]
	return ""


func test_custom_file_parses_and_bad_values_are_rejected() -> String:
	var good: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text("\"custom_file\": \"%s\"" % CUSTOM_PATH))
	if good.error != "" or good.steps[0].custom_file != CUSTOM_PATH or good.steps[0].preset != AcceptanceStep.NO_PRESET:
		return "good file: '%s'" % good.error
	var plain: AcceptanceSuite = AcceptanceSuite.load_file("res://acceptance/suites/m0.json")
	if plain.error != "" or plain.steps[0].custom_file != "":
		return "a step without custom_file has '%s'" % plain.steps[0].custom_file
	var cases: Array[String] = [
		"\"custom_file\": 3", "\"custom_file\": \"\"", "\"custom_file\": \"user://mine.json\"",
		"\"custom_file\": \"%s\", \"preset\": 2" % CUSTOM_PATH,
	]
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(fields))
		if not suite.error.contains("steps[0].custom_file"):
			return "%s gave '%s'" % [fields, suite.error]
	return ""


## The shipped step: the custom file, its own replay and hash, the three checks.
func test_the_m1_step_is_shipped() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = _m1_step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	if step.custom_file != CUSTOM_PATH or step.replay_path != REPLAY_PATH or step.preset != AcceptanceStep.NO_PRESET:
		return "%s flies %s with %s" % [step.id, step.replay_path, step.custom_file]
	if step.checks != [AcceptanceStep.CHECK_COMFORT_MOTION, AcceptanceStep.CHECK_FINAL_HASH,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		return "%s checks %s" % [step.id, step.checks]
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "" or replay.expected_hash != step.expected_hash:
		return "replay hash %d, step %d (%s)" % [replay.expected_hash, step.expected_hash, replay.error]
	if step.expected_hash == _m1_step("comfort_preset_2").expected_hash:
		return "the custom step expects preset 2's hash %d" % step.expected_hash
	return ""


## The stored replay is the pilot's flight in the custom mode today.
func test_the_replay_matches_a_fresh_recording() -> String:
	var session: LocalSession = record()
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if session.sim.state_hash() != replay.expected_hash or session.sim.tick != replay.frames.size():
		return "fresh flight %d ticks hash %d, stored %d ticks hash %d" % [
			session.sim.tick, session.sim.state_hash(), replay.frames.size(), replay.expected_hash]
	return ""


## Headless in the main scene the step passes twice on the same hash, in the
## custom mode, yawing but never past the file's 40°/s cap.
func test_the_step_passes_twice_on_one_hash() -> String:
	var first: Array = _run_step(_m1_step())
	var second: Array = _run_step(_m1_step())
	for report: Array in [first, second]:
		if report[0] != AcceptanceRunner.EXIT_PASS:
			return "exit %d: %s" % [report[0], report[1]]
	var measured: Dictionary = first[2]
	if measured.get("final_hash") != second[2].get("final_hash"):
		return "two runs ended on %s and %s" % [measured.get("final_hash"), second[2].get("final_hash")]
	if measured.get("comfort_preset") != ComfortPresetFiles.CUSTOM_NUMBER:
		return "flew preset %s" % measured.get("comfort_preset")
	var yaw: float = measured.get("max_yaw_deg_s", 0.0)
	if yaw < 30.0 or yaw > 40.0 * (1.0 + AcceptanceComfortCheck.CAP_TOLERANCE):
		return "fastest yaw %.1f°/s" % yaw
	return ""


## Preset 2's replay turns at its own 60°/s: in the custom mode comfort_motion
## fails it on the custom file's 40°/s cap, not preset 2's.
func test_comfort_motion_reads_the_custom_cap_not_the_base() -> String:
	var step: AcceptanceStep = _m1_step()
	step.replay_path = PRESET_2_REPLAY_PATH
	step.expected_hash = _m1_step("comfort_preset_2").expected_hash
	var report: Array = _run_step(step)
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS or not text.contains("cap 40.0°/s"):
		return "preset 2's replay in the custom mode gave exit %d: %s" % [report[0], text]
	if report[2].get("final_hash") != step.expected_hash:
		return "the mode moved the simulation: %s" % report[2]
	return ""


## The check alone: the same 50°/s yaw passes preset 2 and fails the custom
## preset; a custom file with every smooth setting off fails any smooth turn.
func test_the_check_judges_the_custom_values() -> String:
	var custom: ComfortPreset = ComfortCustom.load_from(CUSTOM_PATH).preset
	var base_check: AcceptanceComfortCheck = AcceptanceComfortCheck.new(2, ComfortPresetFiles.load_number(2))
	var custom_check: AcceptanceComfortCheck = AcceptanceComfortCheck.new(ComfortPresetFiles.CUSTOM_NUMBER, custom)
	var snaps_only: AcceptanceComfortCheck = AcceptanceComfortCheck.new(ComfortPresetFiles.CUSTOM_NUMBER,
		ComfortCustom.parse("{\"base\": 1, \"display_name\": \"Snaps\"}").preset)
	for check: AcceptanceComfortCheck in [base_check, custom_check, snaps_only]:
		for frame: int in 6:
			check.sample(Basis(Vector3.UP, deg_to_rad(frame * 50.0 / 60.0)), 1.0 / 60.0)
	if base_check.first_failure != "":
		return "preset 2 failed 50°/s: %s" % base_check.first_failure
	if not custom_check.first_failure.contains("cap 40.0°/s"):
		return "custom at 50°/s: '%s'" % custom_check.first_failure
	if not snaps_only.first_failure.contains("smoothly"):
		return "snap-only custom: '%s'" % snaps_only.first_failure
	return ""


## A file ComfortCustom rejects fails the step, naming the field, and the step
## flies nothing.
func test_a_rejected_file_fails_the_step_naming_the_field() -> String:
	var file: FileAccess = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	file.store_string("{\"base\": 2, \"yaw_rate_cap_deg_per_s\": \"fast\"}")
	file.close()
	var step: AcceptanceStep = _m1_step()
	step.custom_file = SCRATCH_PATH
	var report: Array = _run_step(step)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS or not text.contains("custom_file: ") \
			or not text.contains("field \"yaw_rate_cap_deg_per_s\""):
		return "a rejected file gave exit %d: %s" % [report[0], text]
	return ""


static func _suite_text(fields: String) -> String:
	return ("{\"name\": \"x\", \"steps\": [{\"id\": \"c\", \"replay\": \"%s\", \"checks\": [\"comfort_motion\"], %s}]}"
		% [REPLAY_PATH, fields])


## [exit code, messages and results, measurements] of the runner flying
## `step` alone in the main scene, as `test_m1_preset_change_step.gd` does.
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
