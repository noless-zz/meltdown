class_name ShaftPanelModel
extends RefCounted

## What the shaft panel shows and which entry is highlighted (#990, RUN-1,
## CRF-7): the shafts offered between a run's levels, in `RunState.offer()`
## order, each with its label and its risk and reward put in words by
## `ShaftPanelLook`.
##
## With `ShaftPanelShapes` each shaft also gets its look key and its gauges
## (#1320); a shaft with no look keeps "" and no gauges, and shows as a text row.
##
## It takes the dev menu's named actions (decision record 0009): up or left
## and down or right move the highlight, stopping at either end without
## wrapping, and confirm picks the highlighted shaft. Pointing at an entry
## highlights it too. An action counts on the frame it is pressed;
## every action counts as held when the panel opens, so the press that opened
## it (A, which also ends the escape screen) cannot confirm at once.
## It only answers a kind; choosing it is the caller's (MP-2).

## Shaft kinds in offer order.
var kinds: Array[String] = []
## The label of each shaft, from the shaft file.
var labels: Array[String] = []
## The risk and reward line of each shaft.
var details: Array[String] = []
## The look key of each shaft, "" for a text row.
var looks: Array[String] = []
## The gauges of each shaft (`ShaftPanelGauges.for_shaft`), empty for a text row.
var gauges: Array[Array] = []
## Entries before the first added row: the shafts themselves.
var shaft_count: int = 0
## Index of the highlighted shaft.
var highlight: int = 0

var _pointed: String = ""

var _held: Dictionary = {DevMenuModel.UP: true, DevMenuModel.DOWN: true, DevMenuModel.LEFT: true,
	DevMenuModel.RIGHT: true, DevMenuModel.CONFIRM: true}


## The panel for `offered` kinds of `shafts`, worded with `look` and drawn
## with `shapes` when given. A kind the shaft file does not have is left out.
static func build(offered: Array[String], shafts: ShaftOffer, look: Dictionary,
		shapes: ShaftPanelShapes = null) -> ShaftPanelModel:
	var model: ShaftPanelModel = ShaftPanelModel.new()
	for kind: String in offered:
		if shafts == null or not shafts.labels.has(kind):
			continue
		model.kinds.append(kind)
		model.labels.append(shafts.labels[kind])
		model.details.append(ShaftPanelLook.detail_line(look, shafts.risks[kind], shafts.rewards[kind]))
		var look_key: String = shapes.look_of(kind) if shapes != null else ""
		model.looks.append(look_key)
		model.gauges.append(ShaftPanelGauges.for_shaft(shapes, shafts.risks[kind], shafts.rewards[kind], look)
			if look_key != "" else [])
	model.shaft_count = model.kinds.size()
	return model


## Adds a row after the shafts that is not a shaft, such as suspending the run
## (#1107): confirming it answers `kind`, which the caller tells apart.
func add_row(kind: String, label: String, detail: String) -> void:
	kinds.append(kind)
	labels.append(label)
	details.append(detail)
	looks.append("")
	gauges.append([])


## The number of entries drawn as shafts with a look, before any added row.
func shown_as_things() -> int:
	var count: int = 0
	for key: String in looks:
		if key != "":
			count += 1
	return count


## Takes one frame's named actions (held true or false). Returns the
## highlighted kind on the frame confirm is pressed, otherwise "".
func update(actions: Dictionary) -> String:
	var chosen: String = ""
	if _pressed(actions, DevMenuModel.UP) or _pressed(actions, DevMenuModel.LEFT):
		highlight = maxi(highlight - 1, 0)
	if _pressed(actions, DevMenuModel.DOWN) or _pressed(actions, DevMenuModel.RIGHT):
		highlight = mini(highlight + 1, maxi(kinds.size() - 1, 0))
	if _pressed(actions, DevMenuModel.CONFIRM) and not kinds.is_empty():
		chosen = kinds[highlight]
	for action: String in _held:
		_held[action] = bool(actions.get(action, false))
	return chosen


## The entry the aim points at, by kind ("" for none): an entry newly pointed
## at becomes the highlighted one, so a still hand does not undo a stick step.
func point(kind: String) -> void:
	if kind != _pointed and kinds.has(kind):
		highlight = kinds.find(kind)
	_pointed = kind


## The highlighted kind, or "" with nothing offered.
func selected() -> String:
	return kinds[highlight] if not kinds.is_empty() else ""


func _pressed(actions: Dictionary, action: String) -> bool:
	return bool(actions.get(action, false)) and not bool(_held[action])
