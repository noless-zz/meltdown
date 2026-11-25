class_name ShaftChoiceWiring
extends RefCounted

## Joins a run's shaft choice to the shaft panel (#990, RUN-1, CRF-7, CMF-8,
## ARC-3, MP-2). `EscapeEndWiring` opens it on the escape screen's press after a
## level that is not the run's last: `RunWiring.escape_for_choice` moves the run
## on and hands back the offer, and the panel shows it in front of the pilot.
##
## While it is open it takes the controls as the dev menu does (decision record
## 0009): the frame's values reach the rest of `main.gd` idle, so the ship gets
## neutral input, and the right stick and A drive `ShaftPanelModel` through the
## dev menu's named actions (`DevMenuWiring.actions`). The flat build therefore
## uses the dev menu's keys: the arrows and Shift. While the session is paused
## the panel holds still and takes no action.
##
## A confirm calls `RunWiring.choose` and answers the restart that flies the
## chosen shaft's level; the view stays dark until then, so the level changes
## behind the fade (CMF-8). Comfort settings are neither read nor changed. It
## sits beside `main.gd` because it reads `RunWiring`.
##
## Each shaft is drawn as a thing with gauges from `ShaftPanelShapes` (#1320),
## and pointing the right controller's aim at a shaft or row highlights it, as
## at the hub's stations; the stick still steps and A still confirms. It is
## presentation only: the shafts' rules and data are not read from here.
##
## A run with a save store gets one more row after the shafts, "Suspend run"
## (#1107, RUN-8, `RunSuspend`): confirming it saves the run and answers the
## restart too, and `HubWiring.open_after` then opens the hub instead of a level.

var look: Dictionary = ShaftPanelLook.load_file()
## How the shafts are drawn; a refused file leaves today's text rows.
var shapes: ShaftPanelShapes = ShaftPanelShapes.load_file()
## The suspend row's words (`data/run/suspend.json`).
var suspend_words: Dictionary = RunSuspend.words()
## Under the rig origin once `attach` has run, null before.
var panel: ShaftPanel = null
## The open panel's model; null while closed.
var model: ShaftPanelModel = null

var _actions: Dictionary = {}
var _aim: XRController3D = null


## Hangs the panel under `rig`. Calling it again adds nothing.
func attach(rig: Node3D) -> void:
	if panel != null or rig == null:
		return
	panel = ShaftPanel.new(look, shapes)
	rig.add_child(panel)
	_aim = rig.get_node_or_null("RightHand") as XRController3D


func is_open() -> bool:
	return model != null


## Opens the panel on `run`'s offer after an escape with `collected` picked up
## and `rescued` miners aboard (#1032). False, opening nothing, when the run
## has no choice due.
func open(run: RunWiring, collected: Dictionary, rescued: int = 0) -> bool:
	var offered: Array[String] = run.escape_for_choice(collected, rescued) if run != null else []
	if offered.is_empty():
		return false
	model = ShaftPanelModel.build(offered, run.shafts, look, shapes)
	if run.saves != null:
		model.add_row(RunSuspend.ROW_KIND, suspend_words["row_text"], suspend_words["detail_text"])
	_actions = {}
	return true


## Once per frame, after the dev menu, with the sampled `values`. Returns them
## unchanged while closed, idle but for the menu button while open.
func read(values: Dictionary) -> Dictionary:
	if not is_open():
		return values
	_actions = DevMenuWiring.actions(values)
	return DevMenuWiring.neutral(values)


## Once per frame after the ticks, while open. Returns true on the frame a
## confirmed shaft is taken and its level should fly, or the run is suspended.
func update(run: RunWiring, paused: bool, head_point: Transform3D, xr_running: bool) -> bool:
	if not is_open():
		return false
	if not paused and not _actions.is_empty():  # No frame read since opening: nothing pressed yet.
		var kind: String = model.update(_actions)
		var taken: bool = false
		if kind != "" and run != null:
			taken = run.suspend() if kind == RunSuspend.ROW_KIND else run.choose(kind)
		if taken:
			close()
			return true
	if panel != null:
		panel.transform = head_point
		if not paused:
			_point()
		panel.show_model(model, xr_running)
	return false


## Hands the model the entry the right controller's aim points at, in the
## panel's space; a controller that is not tracked points at nothing.
func _point() -> void:
	if _aim == null or not _aim.get_is_active() or model == null:
		return
	var radius: float = shapes.lengths.get("point_radius_m", 0.0) if shapes.error == "" else 0.0
	model.point(point_in(panel, _aim.transform, radius))


## The kind of `panel`'s entry that an aim at `aim` (in the panel's parent's
## space) points at, within `radius`; "" for none.
static func point_in(shown: ShaftPanel, aim: Transform3D, radius: float) -> String:
	var to_panel: Transform3D = shown.transform.affine_inverse()
	return HubStations.pick(to_panel * aim.origin, to_panel.basis * -aim.basis.z, shown.entry_points(), radius)


func close() -> void:
	model = null
	_actions = {}
	if panel != null:
		panel.show_model(null, false)
