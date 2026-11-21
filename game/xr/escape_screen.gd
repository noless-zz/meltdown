class_name EscapeScreen
extends Node3D

## The end screen of an escaped run (#751, RUN-3, RUN-7): `ESCAPED`, the
## meltdown time that was left, and the prompt to fly the level again. Hung
## under the rig origin at the head point like `DestroyedScreen`, so the head
## turns while the words stay put, and drawn over the fade quad the same way:
## no depth test and the highest render priority.
##
## It only shows what it is handed; it never reads the session. Nothing here
## moves or animates (CMF-3, CMF-8). Words, colours, sizes and placement come
## from `EscapeScreenLook` (ARC-4).

const NODE_NAME: String = "EscapeScreen"
const LINE_NAME: String = "Line"
const TIME_NAME: String = "Time"
const PROMPT_NAME: String = "Prompt"

var _look: Dictionary
var _line: Label3D
var _time: Label3D
var _prompt: Label3D


func _init(look: Dictionary = EscapeScreenLook.FALLBACK) -> void:
	name = NODE_NAME
	_look = look
	_line = _label(LINE_NAME, look["line_text"], look["line_position_m"], look["line_font_size"], look["line_color"])
	_time = _label(TIME_NAME, "", look["time_position_m"], look["time_font_size"], look["time_color"])
	_prompt = _label(PROMPT_NAME, look["prompt_xr"], look["prompt_position_m"], look["prompt_font_size"],
		look["prompt_color"])
	visible = false


## Shows the line and the time line with `seconds_left` when `line` is true,
## and the prompt under them when `prompt` is true; `xr_running` picks the
## button the prompt names. `won` shows the run's won line in place of the
## escape's (#989).
func show_state(line: bool, prompt: bool, seconds_left: float, xr_running: bool, won: bool = false) -> void:
	visible = line
	_prompt.visible = line and prompt
	if not line:
		return
	var line_text: String = _look["won_text"] if won else _look["line_text"]
	if _line.text != line_text:
		_line.text = line_text
	# Label3D rebuilds its glyphs on every assignment; most frames change nothing.
	var time: String = EscapeScreenLook.time_line(_look, seconds_left)
	if _time.text != time:
		_time.text = time
	var wanted: String = _look["prompt_xr"] if xr_running else _look["prompt_flat"]
	if _prompt.text != wanted:
		_prompt.text = wanted


func line_visible() -> bool:
	return visible and _line.visible


func prompt_visible() -> bool:
	return visible and _prompt.visible


func line_text() -> String:
	return _line.text


func time_text() -> String:
	return _time.text


func prompt_text() -> String:
	return _prompt.text


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
