extends RefCounted

## The `control_labels_clear` check (#1316, PLT-5, DEV-6), lane-b's file under
## `acceptance/checks/`. In `suites/m6/effects.json`:
##
##     {"id": "control_labels_clear", "checks": ["no_script_errors", "control_labels_clear"]}
##
## The scene's own rig is held in the layout's resting grip and then with the
## hands 20 cm apart (`ControlLabelClearance`), with the labels its mapping
## shows, and fails if any label box overlaps another or a controller, or a
## leader is too long. The hands are put back afterwards. Skipped, not passed,
## when the scene has no rig with both hands. Whether the labels read at a
## glance stays human-checked in the headset.

const CHECK: String = "control_labels_clear"
const RIG_PATH: NodePath = ^"XRRig"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	return judge_rig(main.get_node_or_null(RIG_PATH) if main != null else null, measurements)


## The verdict for `rig`, an `XRRig` or null.
static func judge_rig(rig: Node, measurements: Dictionary) -> Array:
	if rig == null or rig.get_node_or_null("LeftHand") == null or rig.get_node_or_null("RightHand") == null \
			or not rig.has_method("model_for") or rig.call("model_for", "right") == null:
		return [AcceptanceReport.RESULT_SKIPPED, "the scene has no rig with both hands"]
	rig.call("refresh_labels")
	var shown: int = 0
	for hand: String in ControlLabelClearance.HANDS:
		shown += (rig.call("model_for", hand) as ControllerModel).label_texts().size()
	measurements["control_labels"] = shown
	if shown == 0:
		return [AcceptanceReport.RESULT_FAIL, "no control labels are shown"]
	var problem: String = ControlLabelClearance.check(rig)
	if problem != "":
		return [AcceptanceReport.RESULT_FAIL, problem]
	var apart: float = float(ControlLabelLayout.load_file()["close_apart_m"])
	return [AcceptanceReport.RESULT_PASS, "%d labels clear of each other and both controllers, resting grip and hands %.0f cm apart" %
		[shown, apart * 100.0]]
