class_name ShaftPanel
extends Node3D

## The shaft panel between a run's levels (#990, RUN-1, CMF-8): a title, the
## offered shafts, the highlighted one marked and coloured, and the prompt.
## Hung under the rig origin at the head point like `EscapeScreen`, so the
## head turns while the panel stays put, and drawn over the fade quad the same
## way.
##
## When the model gives shafts a look (#1320, RUN-2, GFX-2), the shafts stand
## side by side as `ShaftPanelCard`s, each a small object with gauges drawn on
## one scale, and the rows that are not shafts ("Suspend run") sit apart below
## them, `suspend_gap_m` under the plates. With no looks it shows today's text
## rows, one under the other.
##
## It only shows the `ShaftPanelModel` it is handed and never reads the run or
## the session. Nothing moves or animates (CMF-3, CMF-8). Words, colours, sizes
## and placement come from `ShaftPanelLook` and `ShaftPanelShapes` (ARC-4).

const NODE_NAME: String = "ShaftPanel"

var _look: Dictionary
var _shapes: ShaftPanelShapes
var _title: Label3D
var _prompt: Label3D
var _labels: Array[Label3D] = []
var _details: Array[Label3D] = []
var _cards: Array[ShaftPanelCard] = []
## Where each shown entry can be pointed at, by kind, in the panel's space.
var _points: Dictionary[String, Vector3] = {}


func _init(look: Dictionary = ShaftPanelLook.FALLBACK, shapes: ShaftPanelShapes = null) -> void:
	name = NODE_NAME
	_look = look
	_shapes = shapes if shapes != null and shapes.error == "" else null
	_title = _label("Title", look["title_text"], look["title_position_m"], look["title_font_size"],
		look["title_color"])
	_prompt = _label("Prompt", "", look["title_position_m"], look["detail_font_size"], look["title_color"])
	visible = false


## Shows `model`, or hides the panel for null; `xr_running` picks the prompt.
func show_model(model: ShaftPanelModel, xr_running: bool) -> void:
	visible = model != null
	if model == null:
		return
	_points.clear()
	var as_cards: bool = _shapes != null and model.shown_as_things() > 0
	var first_row: int = model.shaft_count if as_cards else 0
	var below: float = _show_cards(model) if as_cards else 0.0
	for card: int in range(first_row, _cards.size()):
		_cards[card].visible = false
	var step: Vector3 = Vector3(0.0, -float(_look["entry_step_m"]), 0.0)
	var row_top: Vector3 = _look["title_position_m"] + Vector3(0.0, -below, 0.0)
	while _labels.size() < model.kinds.size():
		var index: int = _labels.size()
		_labels.append(_label("Shaft%d" % index, "", Vector3.ZERO, _look["label_font_size"], _look["text_color"]))
		_details.append(_label("Detail%d" % index, "", Vector3.ZERO, _look["detail_font_size"], _look["text_color"]))
	for i: int in _labels.size():
		var shown: bool = i >= first_row and i < model.kinds.size()
		_labels[i].visible = shown
		_details[i].visible = shown
		if not shown:
			continue
		var lit: bool = i == model.highlight
		var color: Color = _look["highlight_color"] if lit else _look["text_color"]
		var row: int = i - first_row
		_put_line(_labels[i], (_look["mark_text"] if lit else "") + model.labels[i], row_top + step * (row + 1), color)
		_put_line(_details[i], model.details[i], row_top + step * (row + 1.45), color)
		_points[model.kinds[i]] = _labels[i].position
	_put_line(_prompt, _look["prompt_xr"] if xr_running else _look["prompt_flat"],
		row_top + step * (model.kinds.size() - first_row + 1.2), _look["title_color"])


## Each shown entry's point to aim at, by kind, in the panel's space.
func entry_points() -> Dictionary[String, Vector3]:
	return _points


## The shown cards, left to right, for tests.
func cards() -> Array[ShaftPanelCard]:
	var shown: Array[ShaftPanelCard] = []
	for card: ShaftPanelCard in _cards:
		if card.visible:
			shown.append(card)
	return shown


## The text of each shown text row, highlighted one marked, for tests.
func shaft_texts() -> PackedStringArray:
	var texts: PackedStringArray = PackedStringArray()
	for label: Label3D in _labels:
		if label.visible:
			texts.append(label.text)
	return texts


func detail_texts() -> PackedStringArray:
	var texts: PackedStringArray = PackedStringArray()
	for label: Label3D in _details:
		if label.visible:
			texts.append(label.text)
	return texts


func prompt_text() -> String:
	return _prompt.text


## Lays the shafts out side by side, centred under the title; returns how far
## below the title the rows after them start, so they sit apart.
func _show_cards(model: ShaftPanelModel) -> float:
	var count: int = model.shaft_count
	while _cards.size() < count:
		var card: ShaftPanelCard = ShaftPanelCard.new(_shapes, _look)
		card.name = "Card%d" % _cards.size()
		_cards.append(card)
		add_child(card)
	var entry_step: float = float(_look["entry_step_m"])
	var top: Vector3 = _look["title_position_m"] + Vector3(0.0, -entry_step, 0.0)
	var step: float = _shapes.lengths["card_step_m"]
	for i: int in count:
		_cards[i].visible = true
		_cards[i].position = top + Vector3(step * (i - (count - 1) * 0.5), 0.0, 0.0)
		_cards[i].show_entry(model, i, i == model.highlight)
		_points[model.kinds[i]] = _cards[i].position + Vector3(0.0, -_shapes.lengths["plate_drop_m"], 0.0)
	var plate_bottom: float = entry_step + _shapes.lengths["plate_drop_m"] + _shapes.plate_size_m.y * 0.5
	# The text rows step down one `entry_step_m` before their first line.
	return plate_bottom + _shapes.lengths["suspend_gap_m"] - entry_step


## Label3D rebuilds its glyphs on every text assignment; most frames change nothing.
static func _put_line(label: Label3D, text: String, at: Vector3, color: Color) -> void:
	if label.text != text:
		label.text = text
	label.position = at
	label.modulate = color


func _label(label_name: String, text: String, at: Vector3, font_size: float, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.text = text
	label.position = at
	label.pixel_size = _look["pixel_size"]
	label.font_size = roundi(font_size)
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = DestroyedScreen.RENDER_PRIORITY
	add_child(label)
	return label
