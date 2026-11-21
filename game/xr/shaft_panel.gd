class_name ShaftPanel
extends Node3D

## The shaft panel between a run's levels (#990, RUN-1, CMF-8): a title, each
## offered shaft's label and its risk and reward line, the highlighted one
## marked and coloured, and the prompt. Hung under the rig origin at the head
## point like `EscapeScreen`, so the head turns while the words stay put, and
## drawn over the fade quad the same way.
##
## It only shows the `ShaftPanelModel` it is handed and never reads the run or
## the session. Nothing moves or animates (CMF-3, CMF-8). Words, colours, sizes
## and placement come from `ShaftPanelLook` (ARC-4).

const NODE_NAME: String = "ShaftPanel"

var _look: Dictionary
var _title: Label3D
var _prompt: Label3D
var _labels: Array[Label3D] = []
var _details: Array[Label3D] = []


func _init(look: Dictionary = ShaftPanelLook.FALLBACK) -> void:
	name = NODE_NAME
	_look = look
	_title = _label("Title", look["title_text"], look["title_position_m"], look["title_font_size"],
		look["title_color"])
	_prompt = _label("Prompt", "", look["title_position_m"], look["detail_font_size"], look["title_color"])
	visible = false


## Shows `model`, or hides the panel for null; `xr_running` picks the prompt.
func show_model(model: ShaftPanelModel, xr_running: bool) -> void:
	visible = model != null
	if model == null:
		return
	while _labels.size() < model.kinds.size():
		var index: int = _labels.size()
		_labels.append(_label("Shaft%d" % index, "", Vector3.ZERO, _look["label_font_size"], _look["text_color"]))
		_details.append(_label("Detail%d" % index, "", Vector3.ZERO, _look["detail_font_size"], _look["text_color"]))
	var step: Vector3 = Vector3(0.0, -float(_look["entry_step_m"]), 0.0)
	var top: Vector3 = _look["title_position_m"]
	for i: int in _labels.size():
		var shown: bool = i < model.kinds.size()
		_labels[i].visible = shown
		_details[i].visible = shown
		if not shown:
			continue
		var lit: bool = i == model.highlight
		var color: Color = _look["highlight_color"] if lit else _look["text_color"]
		_put_line(_labels[i], (_look["mark_text"] if lit else "") + model.labels[i], top + step * (i + 1), color)
		_put_line(_details[i], model.details[i], top + step * (i + 1.45), color)
	_put_line(_prompt, _look["prompt_xr"] if xr_running else _look["prompt_flat"],
		top + step * (model.kinds.size() + 1.2), _look["title_color"])


## The text of each shown shaft line, highlighted one marked, for tests.
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
