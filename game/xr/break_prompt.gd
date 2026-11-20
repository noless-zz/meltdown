class_name BreakPrompt
extends Node3D

## The "take a break" prompt (CMF-10): a few lines fixed in the cockpit just
## below the line of sight, above the status panel, that say how long the
## pilot has flown, how to dismiss the prompt and that reminders can be
## switched off. `BreakReminder` decides when it is due; this only shows it.
##
## It never touches the camera, the fade or the tree's pause state, so the view
## does not move or dim (CMF-8), and it reads nothing but the reminder it is
## handed, so the simulation runs on unchanged while it shows (CMF-6, ARC-3).
## Hang it under the rig origin at the head point, like the status panel.
##
## Text, sizes, colours, placement and the player's on/off choice live in
## `res://xr/break_prompt.json` (ARC-4); see `BreakPromptLook`.

const NODE_NAME: String = "BreakPrompt"
const TITLE_NAME: String = "Title"
const BODY_NAME: String = "Body"
## Gap between the title and the body, in font pixels.
const LINE_GAP_PX: float = 8.0
## Drawn without a depth test over the cockpit shell, one step above the status
## panel's labels, and well below the reset fade quad so a fade still covers it.
const RENDER_PRIORITY: int = StatusPanel.RENDER_PRIORITY_TOP + 1

var _look: Dictionary
var _title: Label3D
var _body: Label3D
## The reminder last passed to `show_if`; `acknowledge` clears it.
var _reminder: BreakReminder = null


## `look` is a parsed break prompt file; empty reads the shipped one.
func _init(look: Dictionary = {}) -> void:
	name = NODE_NAME
	_look = look if not look.is_empty() else BreakPromptLook.load_file()
	var tilt: float = deg_to_rad(float(_look["tilt_deg"]))
	transform = Transform3D(Basis(Vector3.RIGHT, -tilt), _look["position_m"] as Vector3)
	var pixel: float = float(_look["pixel_size"])
	var title_font: int = int(_look["title_font"])
	var body_font: int = int(_look["body_font"])
	_title = _label(TITLE_NAME, _look["title_text"], title_font, _look["title_color"], pixel)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_body = _label(BODY_NAME, "", body_font, _look["body_color"], pixel)
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body.position = Vector3(0.0, -LINE_GAP_PX * pixel, 0.0)
	visible = false


## Sets `reminder`'s switch from the file's `enabled` value, the player's
## choice until a settings menu exists (M8). Call once when the reminder is made.
func apply_setting(reminder: BreakReminder) -> void:
	reminder.set_enabled(enabled_by_default())


## Shows the prompt while `reminder` is switched on and due, and hides it
## otherwise. `xr_running` picks the button the dismiss line names. Returns
## whether the prompt is shown. Only reads the reminder.
func show_if(reminder: BreakReminder, xr_running: bool = true) -> bool:
	_reminder = reminder
	var wanted: bool = reminder.is_enabled() and reminder.due()
	if wanted:
		var text: String = _body_text(reminder.flown_seconds(), xr_running)
		if _body.text != text:
			_body.text = text
	visible = wanted
	return wanted


## The pilot dismissed the prompt: hide it and acknowledge the reminder, which
## starts the next interval. Does nothing while the prompt is hidden, so the
## same button pressed for something else never resets the count. Returns
## whether the prompt was dismissed.
func acknowledge() -> bool:
	if not visible or _reminder == null:
		return false
	_reminder.acknowledge()
	visible = false
	return true


func is_shown() -> bool:
	return visible


func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _body.text


func enabled_by_default() -> bool:
	return bool(_look["enabled"])


## Why the data file was rejected, or empty when it loaded.
func look_error() -> String:
	return str(_look.get("error", ""))


## Whole minutes flown, then the dismiss line and the switch-off line.
func _body_text(flown_s: float, xr_running: bool) -> String:
	var minutes: int = floori(maxf(flown_s, 0.0) / 60.0)
	var flown: String = (_look["flown_text"] as String).replace(BreakPromptLook.MINUTES_TAG, str(minutes))
	var dismiss: String = _look["dismiss_xr"] if xr_running else _look["dismiss_flat"]
	return "%s\n%s\n%s" % [flown, dismiss, _look["off_text"]]


func _label(label_name: String, text: String, font_size: int, color: Color, pixel: float) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.text = text
	label.pixel_size = pixel
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
