extends RefCounted

## The `portal_visibility_counted` acceptance check (#1364, GFX-3, DEV-6): it is
## registered from its own file, passes on the shipped m6 `portal_visibility`
## step (the bot's G2 flight, culled every tick against culling off), and fails
## on a wrong hash, a hidden own box or culling that saves nothing.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/portal_visibility_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/effects.json"
const STEP_ID: String = "portal_visibility"


static func _shipped_step() -> AcceptanceStep:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE_PART))
	var step: AcceptanceStep = AcceptanceStep.new()
	for row: Dictionary in data["steps"]:
		if row["id"] == STEP_ID and (row["checks"] as Array).has(CHECK_SCRIPT.CHECK):
			step.id = row["id"]
			step.replay_path = row["replay"]
			step.expected_hash = int(row["expected_hash"])
	return step


static func _flight(boxes_mean: float, calls_mean: float, hidden_at: int) -> Dictionary:
	return {"frames": 100, "boxes_all": 20, "draw_calls_all": 80, "boxes_mean": boxes_mean, "boxes_most": 9,
		"draw_calls_mean": calls_mean, "draw_calls_most": 36, "own_box_hidden_at": hidden_at}


func test_check_is_known() -> String:
	return "" if AcceptanceCheckFiles.known_checks().has(CHECK_SCRIPT.CHECK) else "not registered"


func test_shipped_step_passes_and_culls() -> String:
	var step: AcceptanceStep = _shipped_step()
	if step.id != STEP_ID:
		return "%s has no %s step with the check" % [SUITE_PART, STEP_ID]
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "the shipped step gave %s" % [outcome]
	print("portal_visibility: %s" % outcome[1])
	if int(measurements.get("portal_frames", 0)) == 0 or float(measurements.get("portal_boxes_mean", 0.0)) <= 0.0:
		return "nothing measured: %s" % measurements
	# Items hidden with their box are reported per frame (#1382).
	for key: String in ["portal_items_mean", "portal_items_hidden_mean", "portal_items_hidden_most"]:
		if not measurements.has(key):
			return "%s not measured: %s" % [key, measurements]
	if float(measurements["portal_items_hidden_mean"]) > float(measurements["portal_items_mean"]):
		return "more items hidden than there are: %s" % measurements
	return ""


func test_wrong_hash_fails() -> String:
	var step: AcceptanceStep = _shipped_step()
	step.expected_hash += 1
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(step, null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "passed on a wrong hash"


func test_bad_flights_fail() -> String:
	var cases: Dictionary[String, Dictionary] = {
		"the own box hidden": _flight(5.0, 20.0, 40),
		"no box saved": _flight(20.0, 20.0, -1),
		"no draw call saved": _flight(5.0, 80.0, -1),
	}
	for name: String in cases:
		if CHECK_SCRIPT.judge_flight(cases[name])[0] != AcceptanceReport.RESULT_FAIL:
			return "passed with %s" % name
	if CHECK_SCRIPT.judge_flight(_flight(5.0, 20.0, -1))[0] != AcceptanceReport.RESULT_PASS:
		return "a culled flight failed"
	return ""
