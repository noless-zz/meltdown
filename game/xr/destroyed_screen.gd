class_name DestroyedScreen
extends Node3D

## The `SHIP DESTROYED` line and the restart prompt under it (#616, RUN-7),
## hung under the rig origin at the head point like the status panel, so the
## head turns while the words stay put in the cockpit. They draw over the
## fade quad, the one thing in view once the fade is dark: no depth test and
## the highest render priority, one step above the fade (`FadeOverlay`).
##
## It only shows what `DestroyedSequence` answers; it never reads the ship.
## Nothing here moves or animates (CMF-3, CMF-8).

const NODE_NAME: String = "DestroyedScreen"
const LINE_NAME: String = "Line"
const PROMPT_NAME: String = "Prompt"
const LINE_TEXT: String = "SHIP DESTROYED"
const PROMPT_XR: String = "Press A to restart"
const PROMPT_FLAT: String = "Press Enter to restart"
## Straight ahead of the eye point, far enough to focus on comfortably. It may
## lie beyond a wall; with no depth test and the view faded, that cannot hide it.
const LINE_POSITION: Vector3 = Vector3(0.0, 0.04, -1.5)
const PROMPT_POSITION: Vector3 = Vector3(0.0, -0.08, -1.5)
## About 10 cm tall at 1.5 m, nearly 4 degrees: read without searching.
const PIXEL_SIZE: float = 0.001
const LINE_FONT: int = 96
const PROMPT_FONT: int = 48
const LINE_COLOR: Color = Color(1.0, 0.2, 0.15)
const PROMPT_COLOR: Color = Color(0.85, 0.95, 1.0)
const RENDER_PRIORITY: int = Material.RENDER_PRIORITY_MAX

var _line: Label3D
var _prompt: Label3D


func _init() -> void:
	name = NODE_NAME
	_line = _label(LINE_NAME, LINE_TEXT, LINE_POSITION, LINE_FONT, LINE_COLOR)
	_prompt = _label(PROMPT_NAME, PROMPT_XR, PROMPT_POSITION, PROMPT_FONT, PROMPT_COLOR)
	visible = false


## Shows the line when `line` is true and the prompt under it when `prompt` is
## true; `xr_running` picks the button the prompt names.
func show_state(line: bool, prompt: bool, xr_running: bool) -> void:
	visible = line
	_prompt.visible = line and prompt
	var wanted: String = PROMPT_XR if xr_running else PROMPT_FLAT
	if _prompt.text != wanted:
		_prompt.text = wanted


func line_visible() -> bool:
	return visible and _line.visible


func prompt_visible() -> bool:
	return visible and _prompt.visible


func prompt_text() -> String:
	return _prompt.text


func _label(label_name: String, text: String, at: Vector3, font_size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.text = text
	label.position = at
	label.pixel_size = PIXEL_SIZE
	label.font_size = font_size
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = RENDER_PRIORITY
	add_child(label)
	return label
