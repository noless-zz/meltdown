extends RefCounted

## The `music_follows_alarm` acceptance check (#1303, DEV-6): it is registered
## from its own file, passes on the shipped m6 step, and fails on moments out
## of order, a slow meltdown switch or a cut.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/music_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/sound.json"
const STEP_ID: String = "music_follows_alarm"


static func _shipped_step() -> AcceptanceStep:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE_PART))
	var step: AcceptanceStep = AcceptanceStep.new()
	for row: Dictionary in data["steps"]:
		if row["id"] == STEP_ID and (row["checks"] as Array).has(CHECK_SCRIPT.CHECK):
			step.id = row["id"]
			step.replay_path = row["replay"]
			step.expected_hash = int(row["expected_hash"])
	return step


static func _flown(moments: Array[String], meltdown_ticks: int, largest_step: float) -> Dictionary:
	return {"moments": moments, "reactor_destroyed": true, "meltdown_ticks": meltdown_ticks,
		"largest_step": largest_step}


func test_check_is_known() -> String:
	return "" if AcceptanceCheckFiles.known_checks().has(CHECK_SCRIPT.CHECK) else "not registered"


func test_shipped_step_passes() -> String:
	var step: AcceptanceStep = _shipped_step()
	if step.id != STEP_ID:
		return "%s has no %s step with the check" % [SUITE_PART, STEP_ID]
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "the shipped step gave %s" % [outcome]
	var ticks: int = int(measurements.get("music_meltdown_ticks", -1))
	return "" if ticks >= 0 and ticks <= CHECK_SCRIPT.MELTDOWN_TICKS_MAX else "meltdown after %d ticks" % ticks


func test_wrong_hash_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.expected_hash += 1
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed on a wrong hash"


func test_order_slow_switch_and_cut_fail() -> String:
	var expected: Array[String] = ["calm", "meltdown", "faded"]
	var good: Array = CHECK_SCRIPT.judge_flight(_flown(["calm", "meltdown", "faded"], 30, 0.01), expected, 0.02)
	if good[0] != AcceptanceReport.RESULT_PASS:
		return "a good flight failed: %s" % [good]
	var order: Array = CHECK_SCRIPT.judge_flight(_flown(["meltdown", "calm", "faded"], 30, 0.01), expected, 0.02)
	if order[0] != AcceptanceReport.RESULT_FAIL:
		return "moments out of order passed"
	var slow: Array = CHECK_SCRIPT.judge_flight(_flown(["calm", "meltdown", "faded"], 61, 0.01), expected, 0.02)
	if slow[0] != AcceptanceReport.RESULT_FAIL:
		return "a switch after 61 ticks passed"
	var never: Array = CHECK_SCRIPT.judge_flight(_flown(["calm", "meltdown", "faded"], -1, 0.01), expected, 0.02)
	if never[0] != AcceptanceReport.RESULT_FAIL:
		return "a switch that never finished passed"
	var cut: Array = CHECK_SCRIPT.judge_flight(_flown(["calm", "meltdown", "faded"], 30, 1.0), expected, 0.02)
	return "" if cut[0] == AcceptanceReport.RESULT_FAIL else "a cut passed"


func test_expected_moments_are_data() -> String:
	var moments: Array[String] = CHECK_SCRIPT.expected_for(STEP_ID)
	if moments.is_empty() or moments[-1] != CHECK_SCRIPT.FADED:
		return "expected %s" % [moments]
	return "" if moments.has(MusicLayer.MELTDOWN) else "the meltdown is not expected"


func test_the_shipped_step_expects_a_tension_layer_before_the_meltdown() -> String:
	# #1342: with the core's alarm the step hears tension join before the meltdown.
	var expected: Array[String] = CHECK_SCRIPT.expected_for(STEP_ID)
	var meltdown: int = expected.find("meltdown")
	for index: int in maxi(meltdown, 0):
		if expected[index].begins_with("tension"):
			return ""
	return "%s expects no tension layer before the meltdown: %s" % [STEP_ID, expected]
