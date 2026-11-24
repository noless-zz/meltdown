extends RefCounted

## The `control_labels_clear` acceptance check (#1316, PLT-5, DEV-6): it is
## registered from its own file, the m6 effects part runs it, it passes on the
## main scene's rig, is skipped without a rig, and fails on a forced overlap.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/control_labels_check.gd")
const SUITE_PART: String = "res://acceptance/suites/m6/effects.json"
const STEP_ID: String = "control_labels_clear"


func test_check_is_known() -> String:
	return "" if AcceptanceCheckFiles.known_checks().has(CHECK_SCRIPT.CHECK) else "not registered"


func test_the_effects_part_has_the_step() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE_PART))
	for row: Dictionary in data["steps"]:
		if row["id"] == STEP_ID:
			return "" if (row["checks"] as Array).has(CHECK_SCRIPT.CHECK) else "the step does not run the check"
	return "%s has no %s step" % [SUITE_PART, STEP_ID]


func test_passes_on_the_main_scene_and_puts_the_hands_back() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var rig: Node = main.get_node(CHECK_SCRIPT.RIG_PATH)
	rig.call("build")  # As `_ready` does in the tree.
	var hand: Node3D = rig.get_node("RightHand") as Node3D
	var before: Transform3D = hand.transform
	var measurements: Dictionary = {}
	var outcome: Array = CHECK_SCRIPT.judge_rig(rig, measurements)
	var after: Transform3D = hand.transform
	main.free()
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "the main scene gave %s" % [outcome]
	if int(measurements.get("control_labels", 0)) < 10:
		return "only %s labels measured" % measurements.get("control_labels", 0)
	return "" if after.is_equal_approx(before) else "the right hand was left at %s" % after


func test_skipped_without_a_rig() -> String:
	var outcome: Array = AcceptanceCheckFiles.judges()[CHECK_SCRIPT.CHECK].call(AcceptanceStep.new(), null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_SKIPPED else "gave %s" % [outcome]


func test_fails_on_a_forced_overlap() -> String:
	var rig: Node = (load("res://xr/xr_rig.tscn") as PackedScene).instantiate()
	rig.call("build")
	var crowded: Dictionary = ControlLabelLayout.load_file().duplicate()
	crowded["row_gap_m"] = 0.0
	crowded["row_height_m"] = 0.0
	for hand: String in ControlLabelClearance.HANDS:
		(rig.call("model_for", hand) as ControllerModel).label_set().layout = crowded
	# Rows drawn over each other: the right stick's cross on its own trigger row.
	var labels: ControlLabelSet = (rig.call("model_for", "right") as ControllerModel).label_set()
	rig.call("refresh_labels")
	ControlLabelClearance.place_hands(rig, crowded, ControlLabelClearance.POSE_HELD)
	ControlLabelClearance.face_all(rig, Transform3D.IDENTITY)
	labels.label_for("trigger").position = labels.label_for("stick").position
	var outcome: Array = [AcceptanceReport.RESULT_PASS, ""]
	var problem: String = ControlLabelClearance.first_problem(rig, Transform3D.IDENTITY, crowded)
	if problem == "":
		outcome = [AcceptanceReport.RESULT_FAIL, "an overlap passed"]
	rig.free()
	return "" if outcome[0] == AcceptanceReport.RESULT_PASS else str(outcome[1])
