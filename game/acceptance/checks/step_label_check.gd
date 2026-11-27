extends RefCounted

## The `step_label_shown` check (#1438, DEV-6, CMF-8, ARC-3), lane-b's file
## under `acceptance/checks/`. In `suites/m6/effects.json`:
##
##     {"id": "step_label", "replay": "res://acceptance/replays/both_primaries_fire.replay",
##      "checks": ["final_hash", "no_script_errors", "step_label_shown"], ...}
##
## The step's screenshots show the label; this check makes sure it is there to
## show: the scene's `AcceptanceStepLabelWiring` must hang a visible label that
## names this suite, this step's number and count and this step, fixed in the
## cockpit (under the rig, not the camera, so it never follows the head) and
## within `MAX_ANGLE_DEG` of straight ahead, so it is in the eye picture.
## Whether it reads clearly in a recording stays a headset check.

const CHECK: String = "step_label_shown"
## The Quest 3's view reaches about 45 degrees below the line of sight.
const MAX_ANGLE_DEG: float = 40.0


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var wiring: AcceptanceStepLabelWiring = AcceptanceStepLabelWiring.find(runner.main if runner != null else null)
	if wiring == null or wiring.label == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene shows no acceptance step label"]
	wiring.refresh()
	var expected: String = expected_text(step, runner)
	measurements["step_label"] = wiring.label.label.text
	return judge_label(wiring.label, expected, wiring.cockpit_point(), measurements)


## What the label must say during `step`: the suite it is in, its number and count.
static func expected_text(step: AcceptanceStep, runner: AcceptanceRunner) -> String:
	var suite: AcceptanceSuite = runner.suites[runner.reports.size() - 1]
	return AcceptanceStepLabel.text_for(suite.name, suite.steps.find(step) + 1, suite.steps.size(), step.id)


## The verdict for `label`, which should say `expected` and sit in view of the eye point `cockpit`.
static func judge_label(label: AcceptanceStepLabel, expected: String, cockpit: Transform3D,
		measurements: Dictionary) -> Array:
	if not label.visible or label.label.text == "":
		return [AcceptanceReport.RESULT_FAIL, "the step label is hidden"]
	if label.label.text != expected:
		return [AcceptanceReport.RESULT_FAIL, "the step label says '%s', not '%s'" % [label.label.text, expected]]
	var parent: Node = label.get_parent()
	if parent is Camera3D or (parent != null and parent.get_parent() is Camera3D):
		return [AcceptanceReport.RESULT_FAIL, "the step label hangs under the camera, so it follows the head (CMF-8)"]
	var seen: Vector3 = cockpit.affine_inverse() * label.transform.origin
	var angle: float = rad_to_deg(seen.angle_to(Vector3.FORWARD))
	measurements["step_label_angle_deg"] = snappedf(angle, 0.1)
	if seen.z >= 0.0 or angle > MAX_ANGLE_DEG:
		return [AcceptanceReport.RESULT_FAIL, "the step label is %.0f degrees off the line of sight; at most %.0f" % [
			angle, MAX_ANGLE_DEG]]
	if label.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the label's look file was refused: %s" % label.error]
	return [AcceptanceReport.RESULT_PASS, "'%s', fixed in the cockpit %.0f degrees off the line of sight" % [
		expected, angle]]
