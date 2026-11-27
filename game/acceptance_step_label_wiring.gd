class_name AcceptanceStepLabelWiring
extends Node

## Feeds the cockpit's acceptance step label (#1438, DEV-6) from the running
## `AcceptanceRunner`, and puts it where the cockpit frame is each frame.
## `main.gd` makes one only when the acceptance switch started a runner, so a
## normal start never shows a label.
##
## The runner is read, never written: its suites, the reports it has begun
## (one per suite started) and the lines it printed. The current step is the
## last `step <id>` line, so this needs nothing new from the runner.

const NODE_NAME: String = "AcceptanceStepLabelWiring"
const STEP_LINE: String = "%s: step " % AcceptanceRunner.LOG_PREFIX

var runner: AcceptanceRunner = null
var label: AcceptanceStepLabel = null
var _main: Node = null


## The one call `main.gd` makes, with what `AcceptanceRunner.start_if_requested`
## returned. Returns the wiring, or null when there is no runner.
static func attach(main: Node, p_runner: AcceptanceRunner) -> AcceptanceStepLabelWiring:
	if main == null or p_runner == null:
		return null
	var wiring: AcceptanceStepLabelWiring = AcceptanceStepLabelWiring.new()
	wiring.name = NODE_NAME
	wiring.runner = p_runner
	wiring._main = main
	wiring.label = AcceptanceStepLabel.new()
	var rig: Node = main.get_node_or_null("XRRig")
	(rig if rig != null else main).add_child(wiring.label)
	main.add_child(wiring)
	wiring.refresh()
	return wiring


## The wiring `attach` added under `main`, or null.
static func find(main: Node) -> AcceptanceStepLabelWiring:
	return main.get_node_or_null(NODE_NAME) as AcceptanceStepLabelWiring if main != null else null


## The label's text for a runner's state: `suites` in run order, how many
## suites have begun (`reports.size()`), and the lines it printed.
static func text_for_run(suites: Array[AcceptanceSuite], begun: int, messages: PackedStringArray) -> String:
	if begun <= 0 or begun > suites.size():
		return ""
	var suite: AcceptanceSuite = suites[begun - 1]
	var step_id: String = last_step_id(messages)
	for index: int in suite.steps.size():
		if suite.steps[index].id == step_id:
			return AcceptanceStepLabel.text_for(suite.name, index + 1, suite.steps.size(), step_id)
	return AcceptanceStepLabel.text_for(suite.name, 0, suite.steps.size(), "")


## The id in the last `step <id>` line, start or end, or "".
static func last_step_id(messages: PackedStringArray) -> String:
	for index: int in range(messages.size() - 1, -1, -1):
		var line: String = messages[index]
		if line.begins_with(STEP_LINE):
			return line.substr(STEP_LINE.length()).get_slice(" ", 0)
	return ""


func _process(_delta: float) -> void:
	refresh()


## Shows the runner's current step at the cockpit frame; hides the label once the run ends.
func refresh() -> void:
	if label == null or runner == null:
		return
	label.show_text("" if runner.finished else text_for_run(runner.suites, runner.reports.size(), runner.messages))
	label.place(cockpit_point())


## The cockpit frame's place in the rig, or the recentred head point without a frame.
func cockpit_point() -> Transform3D:
	var comfort: ComfortWiring = _main.get("comfort") as ComfortWiring if _main != null else null
	if comfort != null and comfort.cockpit_frame != null:
		return comfort.cockpit_frame.transform
	var recentre: HeadRecentre = _main.get("head_recentre") as HeadRecentre if _main != null else null
	return RigViews.head_point(recentre) if recentre != null else Transform3D.IDENTITY
