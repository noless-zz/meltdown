extends RefCounted

## The `room_reverb_changed` acceptance check (#1291, DEV-6): it is
## registered from its own file, passes on the shipped m6 `room_reverb` step,
## and fails on a flight that stays in one room or jumps.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/room_reverb_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/sound.json"
const STEP_ID: String = "room_reverb"


static func _shipped_step() -> AcceptanceStep:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE_PART))
	var step: AcceptanceStep = AcceptanceStep.new()
	for row: Dictionary in data["steps"]:
		if row["id"] == STEP_ID:
			step.id = row["id"]
			step.replay_path = row["replay"]
			step.expected_hash = int(row["expected_hash"])
			if not (row["checks"] as Array).has(CHECK_SCRIPT.CHECK):
				step.id = ""
	return step


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
	return "" if float(measurements.get("room_reverb_change", 0.0)) > 0.0 else "no change measured"


func test_wrong_hash_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.expected_hash += 1
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed on a wrong hash"


func test_one_room_fails_and_a_jump_fails() -> String:
	var start: ReverbSetting = ReverbSetting.new(0.2, 0.6, 0.1)
	var still: Array = CHECK_SCRIPT.judge_flight({"start": start, "change": 0.01, "largest_step": 0.0}, 0.01)
	if still[0] != AcceptanceReport.RESULT_FAIL:
		return "a flight in one room passed"
	var jump: Array = CHECK_SCRIPT.judge_flight({"start": start, "change": 0.5, "largest_step": 0.5}, 0.01)
	if jump[0] != AcceptanceReport.RESULT_FAIL:
		return "a jump passed"
	var good: Array = CHECK_SCRIPT.judge_flight({"start": start, "change": 0.5, "largest_step": 0.005}, 0.01)
	return "" if good[0] == AcceptanceReport.RESULT_PASS else "a blended change failed: %s" % [good]
