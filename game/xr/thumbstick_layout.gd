class_name ThumbstickLayout
extends RefCounted

## Reading a thumbsticks layout (PLT-5): the built-in default and layout data
## files (ARC-4), apart from `ThumbstickMapping`, which maps one tick's
## controller values through a layout (#1158).
##
## Default right-handed layout (decision record 0004):
## - left stick: x strafe, y forward and back
## - right stick: x yaw, y pitch
## - left grip rolls left, right grip rolls right
## - right trigger fires the primary weapon (CMB-1); the left trigger is kept
##   for the secondary weapon and is unbound until secondaries exist
## - B (right upper) moves up, Y (left upper) moves down, so the two mirror
##   (#613); both are on/off for now and may change
## - A (right lower) holds the afterburner (FLT-2), which also gives full
##   forward thrust unless the stick is pulled back
## - the right stick click slots the part in the hold into a primary slot
##   (SLV-1, #312), a stand-in until a hand gesture is designed
## - X (left lower) is the comfort preset button, read outside the mapping;
##   the left stick hold shows and hides the labels, also read outside the
##   mapping (#181, #914)
## - a click of the left stick opens or closes the map hologram (`show_map`,
##   MAP-1, #314, #914, on release); holding it for `MapHologram.HOLD_SECONDS`
##   toggles the labels instead
##
## Layouts are data files under `LAYOUTS_DIR`, one JSON object of the same
## shape as `default_layout`. `from_file` and `from_json` validate them; a
## rejected file leaves the built-in default in place and sets `error`. A
## file may also set the stick dead zone (`StickDeadZone`, #855).

const AXES: Array[String] = ["strafe", "lift", "forward", "pitch", "yaw", "roll"]
## On/off actions held while their controls are pressed.
const BUTTON_ACTIONS: Array[String] = ["afterburner", "fire_primary", "slot_part"]
## Actions bound in the layout that only the view reads; never in `ShipInput`.
const VIEW_ACTIONS: Array[String] = ["show_map"]
## Physical controls a layout may bind. Buttons are named by position rather
## than by letter, so left-handed mode can swap them like everything else.
const CONTROLS: Array[String] = [
	"left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y",
	"left_trigger", "right_trigger", "left_grip", "right_grip",
	"left_button_lower", "left_button_upper", "right_button_lower", "right_button_upper",
	"left_stick_click", "right_stick_click",
]

const LAYOUTS_DIR: String = "res://xr/layouts"
## Today's built-in layout as a file; must equal `default_layout()`.
const DEFAULT_LAYOUT_FILE: String = LAYOUTS_DIR + "/thumbsticks_default.json"
## Both directions of lift on the right hand and of roll on the left, so
## either hand alone can undo its own moves (issue #82).
const PAIRED_LAYOUT_FILE: String = LAYOUTS_DIR + "/thumbsticks_paired.json"

## Ship axis or button action -> {physical control: weight}.
var bindings: Dictionary = default_layout()
var stick_dead_zone: float = StickDeadZone.DEFAULT
## Set when the file's dead zone was rejected and the default used; the
## bindings still loaded. Empty otherwise.
var warning: String = ""
## Set when the file was rejected and the default kept; empty otherwise.
var error: String = ""


## A fresh copy of the default right-handed layout, safe to edit.
static func default_layout() -> Dictionary:
	return {
		"strafe": {"left_stick_x": 1.0},
		"forward": {"left_stick_y": 1.0},
		"yaw": {"right_stick_x": 1.0},
		"pitch": {"right_stick_y": 1.0},
		"roll": {"left_grip": -1.0, "right_grip": 1.0},
		# The upper face buttons, rather than triggers, which fire: down on Y
		# mirrors up on B (decision record 0004, #613).
		"lift": {"left_button_upper": -1.0, "right_button_upper": 1.0},
		# A, away from the thumb that holds the left stick forward (#149).
		"afterburner": {"right_button_lower": 1.0},
		"fire_primary": {"right_trigger": 1.0},
		# The one control decision record 0004 left free (#312).
		"slot_part": {"right_stick_click": 1.0},
		# Shares the label toggle's click; a hold tells them apart (#314).
		"show_map": {"left_stick_click": 1.0},
	}


## The layout read from a data file. If the file is missing or rejected, the
## result has the built-in default and `error` says why.
static func from_file(path: String) -> ThumbstickLayout:
	if not FileAccess.file_exists(path):
		return _default_with_error("no layout file at %s" % path)
	return from_json(FileAccess.get_file_as_string(path), path)


## The layout parsed from the text of a layout file: a JSON object of axis or
## action name -> {control name: weight}. Every name must be one of `AXES`,
## `BUTTON_ACTIONS`, `VIEW_ACTIONS` or `CONTROLS` and every weight a number in
## -1..1. A name outside the lists is rejected rather than ignored, so a typo
## cannot silently leave a control unbound. On failure the result has the
## built-in default layout and `error` names what was wrong. The optional
## `StickDeadZone.FIELD` is read apart from the bindings; `source` names the
## file in its warning.
static func from_json(text: String, source: String = "layout") -> ThumbstickLayout:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _default_with_error("invalid JSON at line %d: %s" % [
			json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _default_with_error("top level must be a JSON object")
	var data: Dictionary = json.data
	var parsed: Dictionary = {}
	for action: Variant in data:
		if action == StickDeadZone.FIELD:
			continue
		if typeof(action) != TYPE_STRING \
				or not (AXES.has(action) or BUTTON_ACTIONS.has(action) or VIEW_ACTIONS.has(action)):
			return _default_with_error("unknown axis or action \"%s\"" % str(action))
		if typeof(data[action]) != TYPE_DICTIONARY:
			return _default_with_error("\"%s\" must map controls to weights" % action)
		var action_bindings: Dictionary = data[action]
		var weights: Dictionary = {}
		for control: Variant in action_bindings:
			if typeof(control) != TYPE_STRING or not CONTROLS.has(control):
				return _default_with_error("unknown control \"%s\" in \"%s\"" % [str(control), action])
			var weight: Variant = action_bindings[control]
			# A bool must not pass as 0 or 1.
			if typeof(weight) != TYPE_FLOAT and typeof(weight) != TYPE_INT:
				return _default_with_error("weight of \"%s\" in \"%s\" must be a number" % [control, action])
			if float(weight) < -1.0 or float(weight) > 1.0:
				return _default_with_error("weight of \"%s\" in \"%s\" is %s, must be in -1..1" % [
					control, action, float(weight)])
			weights[control] = float(weight)
		parsed[action] = weights
	var result: ThumbstickLayout = ThumbstickLayout.new()
	result.bindings = parsed
	var dead_zone: Dictionary = StickDeadZone.read(data, source)
	result.stick_dead_zone = dead_zone["value"]
	result.warning = dead_zone["warning"]
	if result.warning != "":
		push_warning(result.warning)
	return result


## Controls with left and right swapped, for left-handed mode: every left
## control acts as the right one and the other way round.
static func swap_hands(controls: Dictionary) -> Dictionary:
	var swapped: Dictionary = {}
	for control: String in controls:
		var other: String = control
		if control.begins_with("left_"):
			other = "right_" + control.trim_prefix("left_")
		elif control.begins_with("right_"):
			other = "left_" + control.trim_prefix("right_")
		swapped[other] = controls[control]
	return swapped


static func _default_with_error(message: String) -> ThumbstickLayout:
	var result: ThumbstickLayout = ThumbstickLayout.new()
	result.error = message
	return result
