extends RefCounted

## The `weapon_effects_shown` acceptance check (#1309, DEV-6, ARC-1): it is
## registered from its own file, passes on the shipped m6 step (each weapon its
## own bolt, wall, robot and ship ends shown, lights in budget, the pinned hash
## kept), and fails on a wrong hash.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/weapon_effects_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/effects.json"


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
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(_shipped_step(), null, measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "the shipped step gave %s" % [outcome]
	return "" if int(measurements.get("weapon_meshes", 0)) >= 3 else "fewer than 3 bolt looks: %s" % [measurements]


func test_wrong_hash_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.expected_hash += 1
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed on a wrong hash"


func test_the_step_screenshots_shots_and_impacts() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE_PART))
	var row: Dictionary = (data["steps"] as Array)[0]
	return "" if row["id"] == "weapon_effects" and (row["screenshot_at_ticks"] as Array).size() >= 4 \
		else "the step takes no screenshots of the firefight"
