class_name ShaftPanelModel
extends RefCounted

## What the shaft panel shows and which entry is highlighted (#990, RUN-1,
## CRF-7): the shafts offered between a run's levels, in `RunState.offer()`
## order, each with its label and its risk and reward put in words by
## `ShaftPanelLook`.
##
## It takes the dev menu's named actions (decision record 0009): up and down
## move the highlight, stopping at either end without wrapping, and confirm
## picks the highlighted shaft. An action counts on the frame it is pressed;
## every action counts as held when the panel opens, so the press that opened
## it (A, which also ends the escape screen) cannot confirm at once.
## It only answers a kind; choosing it is the caller's (MP-2).

## Shaft kinds in offer order.
var kinds: Array[String] = []
## The label of each shaft, from the shaft file.
var labels: Array[String] = []
## The risk and reward line of each shaft.
var details: Array[String] = []
## Index of the highlighted shaft.
var highlight: int = 0

var _held: Dictionary = {DevMenuModel.UP: true, DevMenuModel.DOWN: true, DevMenuModel.CONFIRM: true}


## The panel for `offered` kinds of `shafts`, worded with `look`. A kind the
## shaft file does not have is left out.
static func build(offered: Array[String], shafts: ShaftOffer, look: Dictionary) -> ShaftPanelModel:
	var model: ShaftPanelModel = ShaftPanelModel.new()
	for kind: String in offered:
		if shafts == null or not shafts.labels.has(kind):
			continue
		model.kinds.append(kind)
		model.labels.append(shafts.labels[kind])
		model.details.append(ShaftPanelLook.detail_line(look, shafts.risks[kind], shafts.rewards[kind]))
	return model


## Adds a row after the shafts that is not a shaft, such as suspending the run
## (#1107): confirming it answers `kind`, which the caller tells apart.
func add_row(kind: String, label: String, detail: String) -> void:
	kinds.append(kind)
	labels.append(label)
	details.append(detail)


## Takes one frame's named actions (held true or false). Returns the
## highlighted kind on the frame confirm is pressed, otherwise "".
func update(actions: Dictionary) -> String:
	var chosen: String = ""
	if _pressed(actions, DevMenuModel.UP):
		highlight = maxi(highlight - 1, 0)
	if _pressed(actions, DevMenuModel.DOWN):
		highlight = mini(highlight + 1, maxi(kinds.size() - 1, 0))
	if _pressed(actions, DevMenuModel.CONFIRM) and not kinds.is_empty():
		chosen = kinds[highlight]
	for action: String in _held:
		_held[action] = bool(actions.get(action, false))
	return chosen


## The highlighted kind, or "" with nothing offered.
func selected() -> String:
	return kinds[highlight] if not kinds.is_empty() else ""


func _pressed(actions: Dictionary, action: String) -> bool:
	return bool(actions.get(action, false)) and not bool(_held[action])
