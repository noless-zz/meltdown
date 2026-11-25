extends RefCounted

## The `robot_voices_heard` acceptance check (#1363, DEV-6): it is registered
## from its own file, passes on the shipped m6 `robot_voices` step (robots
## heard through a wall on `bot_g2_level`), and fails on a wrong hash, a
## missing or unexpected type, no muffled voice, or too many at once.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/robot_voices_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/sound.json"
const STEP_ID: String = "robot_voices"
const ALL: Array[String] = ["drone", "hauler"]


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


static func _flight(types: Array[String], most: int, muffled_ticks: int, least_drop: float) -> Dictionary:
	return {"types": types, "most": most, "muffled_ticks": muffled_ticks, "least_muffle_db": least_drop}


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
	return "" if int(measurements.get("robot_voices_muffled_ticks", 0)) > 0 else "no muffled tick measured"


func test_wrong_hash_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.expected_hash += 1
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed on a wrong hash"


func test_bad_flights_fail() -> String:
	var only_drone: Array[String] = ["drone"]
	var extra: Array[String] = ["drone", "hauler", "warden"]
	var cases: Dictionary[String, Dictionary] = {
		"a missing type": _flight(only_drone, 2, 10, -8.0),
		"an unexpected type": _flight(extra, 2, 10, -8.0),
		"too many at once": _flight(ALL, 7, 10, -8.0),
		"no muffled voice": _flight(ALL, 2, 0, 0.0),
		"a wall that did not quieten": _flight(ALL, 2, 10, 0.0),
	}
	for why: String in cases:
		if CHECK_SCRIPT.judge_flight(cases[why], ALL, 6)[0] != AcceptanceReport.RESULT_FAIL:
			return "passed with %s" % why
	var good: Array = CHECK_SCRIPT.judge_flight(_flight(ALL, 2, 10, -8.0), ALL, 6)
	return "" if good[0] == AcceptanceReport.RESULT_PASS else "a good flight failed: %s" % [good]


func test_expected_types_are_data() -> String:
	var listed: Array[String] = CHECK_SCRIPT.expected_for(STEP_ID)
	if listed.size() != 6:
		return "%s lists %d types for %s" % [CHECK_SCRIPT.EXPECTED_FILE, listed.size(), STEP_ID]
	return "" if CHECK_SCRIPT.expected_for("no_such_step").is_empty() else "an unknown step lists types"
