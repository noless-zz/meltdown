extends RefCounted

## The `sound_cues_in_order` acceptance check (#1290, DEV-6): it is registered
## from its own file, passes on the shipped m6 step, and fails when an
## expected cue never follows the ones before it.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/sound_cues_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/sound.json"


static func _shipped_step() -> AcceptanceStep:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE_PART))
	var row: Dictionary = (data["steps"] as Array)[0]
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = row["id"]
	step.replay_path = row["replay"]
	step.expected_hash = int(row["expected_hash"])
	return step


func test_check_is_known() -> String:
	return "" if AcceptanceCheckFiles.known_checks().has(CHECK_SCRIPT.CHECK) else "not registered"


func test_shipped_step_passes() -> String:
	var judge: Callable = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK]
	var measurements: Dictionary = {}
	var outcome: Array = judge.call(_shipped_step(), null, measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "the shipped step gave %s" % [outcome]
	return "" if int(measurements.get("sound_cues_played", 0)) > 0 else "no cues measured"


func test_wrong_hash_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.expected_hash += 1
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed on a wrong hash"


func test_step_without_expected_cues_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.id = "a_step_with_no_cues_listed"
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed with nothing expected"


func test_order_is_checked() -> String:
	var played: Array[String] = ["A", "B", "A", "C"]
	if CHECK_SCRIPT.first_missing(played, ["A", "B", "C"] as Array[String]) != "":
		return "A B C not found in order"
	if CHECK_SCRIPT.first_missing(played, ["C", "B"] as Array[String]) != "B":
		return "B after C was found"
	if CHECK_SCRIPT.first_missing(played, ["D"] as Array[String]) != "D":
		return "a cue never played was found"
	return ""
