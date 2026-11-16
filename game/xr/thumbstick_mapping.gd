class_name ThumbstickMapping
extends RefCounted

## The thumbsticks-only control scheme (PLT-5) as a pure mapping from
## controller values to one tick's `ShipInput` (FLT-1).
##
## It reads no input device: the caller passes the values it read, so the
## mapping can be tested without a headset and the same code serves every
## controller source. Comfort filtering is not done here (ARC-3).
##
## Default right-handed layout (decision record 0004):
## - left stick: x strafe, y forward and back
## - right stick: x yaw, y pitch
## - left grip rolls left, right grip rolls right
## - right trigger fires the primary weapon (CMB-1); the left trigger is kept
##   for the secondary weapon and is unbound until secondaries exist
## - B (right upper) moves up, X (left lower) moves down
## - A (right lower) holds the afterburner (FLT-2), which also gives full
##   forward thrust unless the stick is pulled back
## - the right stick click slots the part in the hold into a primary slot
##   (SLV-1, #312), a stand-in until a hand gesture is designed
## - Y (left upper) is the comfort preset button, read outside this mapping;
##   the left stick click shows and hides the labels, also read outside this
##   mapping (#181)
## - holding the left stick click for `MapHologram.HOLD_SECONDS` shows the
##   map hologram (`show_map`, MAP-1, #314); a shorter click still toggles
##   the labels, on release
##
## Ship axes use the pilot's view, each -1..1 before scaling:
## `strafe` (+ right), `lift` (+ up), `forward` (+ ahead), `pitch` (+ nose up),
## `yaw` (+ nose right), `roll` (+ right wing down). Stick y is + when pushed
## away from the player, as OpenXR reports it, so pushing the right stick
## away pitches the nose up unless `invert_pitch` is on.
##
## Left-handed mode swaps the roles of the two hands: every left control acts
## as the right one and the other way round, so the right stick flies and the
## left stick turns. Stick x keeps its direction, so pushing right still means
## right.
##
## Besides the six axes the layout holds button actions, `afterburner`,
## `fire_primary` and `slot_part`. They are bound like an axis, so the settings menu remaps
## them the same way, and each counts as held when its bound controls add up
## to at least `BUTTON_THRESHOLD`. Left-handed mode moves them to the other
## hand like everything else.
##
## While the afterburner is held, forward thrust is full, so boost alone
## moves the ship (#149). A stick pulled back still wins: the pilot asked to
## slow down, and reversing under boost must stay possible.
##
## `show_map` is a view action: bound in the layout like the others, so it is
## remapped and swapped the same way, but never part of `ShipInput` (ARC-3).
## `action_held` reads it.
##
## Layouts are data files (ARC-4) under `res://xr/layouts/`, one JSON object
## of the same shape as `layout`. `from_file` and `from_json` validate them;
## a rejected file leaves the built-in default in place and sets `error`.

## Radial dead zone of each stick as a fraction of full deflection. Drift
## inside it gives exactly zero, so a resting stick never moves the ship.
const STICK_DEAD_ZONE: float = 0.15
const MAX_PITCH_RATE: float = PI / 2.0
const MAX_YAW_RATE: float = PI / 2.0
const MAX_ROLL_RATE: float = PI * 0.75

const AXES: Array[String] = ["strafe", "lift", "forward", "pitch", "yaw", "roll"]
## On/off actions held while their controls are pressed.
const BUTTON_ACTIONS: Array[String] = ["afterburner", "fire_primary", "slot_part"]
## Actions bound in the layout that only the view reads; never in `ShipInput`.
const VIEW_ACTIONS: Array[String] = ["show_map"]
## Half way, so an action bound to a trigger or grip fires at half pull.
const BUTTON_THRESHOLD: float = 0.5
## Physical controls a layout may bind. Buttons are named by position rather
## than by letter, so left-handed mode can swap them like everything else.
const CONTROLS: Array[String] = [
	"left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y",
	"left_trigger", "right_trigger", "left_grip", "right_grip",
	"left_button_lower", "left_button_upper", "right_button_lower", "right_button_upper",
	"left_stick_click", "right_stick_click",
]
## The controls passed in the `buttons` argument of `map_controls`.
const BUTTONS: Array[String] = [
	"left_button_lower", "left_button_upper", "right_button_lower", "right_button_upper",
	"left_stick_click", "right_stick_click",
]

const LAYOUTS_DIR: String = "res://xr/layouts"
## Today's built-in layout as a file; must equal `default_layout()`.
const DEFAULT_LAYOUT_FILE: String = LAYOUTS_DIR + "/thumbsticks_default.json"
## Both directions of lift on the right hand and of roll on the left, so
## either hand alone can undo its own moves (issue #82).
const PAIRED_LAYOUT_FILE: String = LAYOUTS_DIR + "/thumbsticks_paired.json"

## Ship axis or button action -> {physical control: weight}. The settings menu can replace this
## to remap controls without code changes.
var layout: Dictionary = {}
var left_handed: bool = false
var invert_pitch: bool = false
## Set by `from_json` or `from_file` when the layout was rejected; empty otherwise.
var error: String = ""


func _init(p_layout: Dictionary = default_layout()) -> void:
	layout = p_layout


## A fresh copy of the default right-handed layout, safe to edit.
static func default_layout() -> Dictionary:
	return {
		"strafe": {"left_stick_x": 1.0},
		"forward": {"left_stick_y": 1.0},
		"yaw": {"right_stick_x": 1.0},
		"pitch": {"right_stick_y": 1.0},
		"roll": {"left_grip": -1.0, "right_grip": 1.0},
		# Face buttons rather than triggers, which fire (decision record 0004).
		"lift": {"left_button_lower": -1.0, "right_button_upper": 1.0},
		# A, away from the thumb that holds the left stick forward (#149).
		"afterburner": {"right_button_lower": 1.0},
		"fire_primary": {"right_trigger": 1.0},
		# The one control decision record 0004 left free (#312).
		"slot_part": {"right_stick_click": 1.0},
		# Shares the label toggle's click; a hold tells them apart (#314).
		"show_map": {"left_stick_click": 1.0},
	}


## A mapping with the layout read from a data file. If the file is missing
## or rejected, the mapping keeps the built-in default and `error` says why.
static func from_file(path: String) -> ThumbstickMapping:
	if not FileAccess.file_exists(path):
		return _default_with_error("no layout file at %s" % path)
	return from_json(FileAccess.get_file_as_string(path))


## A mapping with the layout parsed from the text of a layout file: a JSON
## object of axis or action name -> {control name: weight}. Every name must
## be one of `AXES`, `BUTTON_ACTIONS`, `VIEW_ACTIONS` or `CONTROLS` and every weight a number
## in -1..1. A name outside the lists is rejected rather than ignored, so a
## typo cannot silently leave a control unbound. On failure the mapping has
## the built-in default layout and `error` names what was wrong.
static func from_json(text: String) -> ThumbstickMapping:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _default_with_error("invalid JSON at line %d: %s" % [
			json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _default_with_error("top level must be a JSON object")
	var data: Dictionary = json.data
	var parsed: Dictionary = {}
	for action: Variant in data:
		if typeof(action) != TYPE_STRING \
				or not (AXES.has(action) or BUTTON_ACTIONS.has(action) or VIEW_ACTIONS.has(action)):
			return _default_with_error("unknown axis or action \"%s\"" % str(action))
		if typeof(data[action]) != TYPE_DICTIONARY:
			return _default_with_error("\"%s\" must map controls to weights" % action)
		var bindings: Dictionary = data[action]
		var weights: Dictionary = {}
		for control: Variant in bindings:
			if typeof(control) != TYPE_STRING or not CONTROLS.has(control):
				return _default_with_error("unknown control \"%s\" in \"%s\"" % [str(control), action])
			var weight: Variant = bindings[control]
			# A bool must not pass as 0 or 1.
			if typeof(weight) != TYPE_FLOAT and typeof(weight) != TYPE_INT:
				return _default_with_error("weight of \"%s\" in \"%s\" must be a number" % [control, action])
			if float(weight) < -1.0 or float(weight) > 1.0:
				return _default_with_error("weight of \"%s\" in \"%s\" is %s, must be in -1..1" % [
					control, action, float(weight)])
			weights[control] = float(weight)
		parsed[action] = weights
	return ThumbstickMapping.new(parsed)


static func _default_with_error(message: String) -> ThumbstickMapping:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.error = message
	return mapping


## Scales a stick so that the dead zone gives exactly zero and the output
## rises from zero at its edge to 1 at full deflection, in the same direction.
static func apply_dead_zone(stick: Vector2) -> Vector2:
	var length: float = stick.length()
	# Vector2 holds 32-bit floats, so a stick reading exactly on the edge can
	# come out a hair longer than the 64-bit constant.
	if length <= STICK_DEAD_ZONE or is_equal_approx(length, STICK_DEAD_ZONE):
		return Vector2.ZERO
	var scaled: float = (minf(length, 1.0) - STICK_DEAD_ZONE) / (1.0 - STICK_DEAD_ZONE)
	return stick / length * scaled


## Maps one frame of controller values to the input for one tick. Triggers
## and grips are 0..1; `buttons` maps button names from `BUTTONS` (face
## buttons and stick clicks) to pressed, and a missing button counts as
## released, so callers that pass no buttons never fire the afterburner.
func map_controls(left_stick: Vector2, right_stick: Vector2,
		left_trigger: float, right_trigger: float,
		left_grip: float, right_grip: float,
		buttons: Dictionary = {}) -> ShipInput:
	var left: Vector2 = apply_dead_zone(left_stick)
	var right: Vector2 = apply_dead_zone(right_stick)
	var controls: Dictionary = {
		"left_stick_x": left.x, "left_stick_y": left.y,
		"right_stick_x": right.x, "right_stick_y": right.y,
		"left_trigger": clampf(left_trigger, 0.0, 1.0),
		"right_trigger": clampf(right_trigger, 0.0, 1.0),
		"left_grip": clampf(left_grip, 0.0, 1.0),
		"right_grip": clampf(right_grip, 0.0, 1.0),
	}
	for button: String in BUTTONS:
		controls[button] = 1.0 if buttons.get(button, false) else 0.0
	if left_handed:
		controls = _swap_hands(controls)
	var axis: Dictionary = {}
	for name: String in AXES:
		axis[name] = _axis_value(controls, name)
	var pitch: float = -axis["pitch"] if invert_pitch else axis["pitch"]
	# Ship space: z forward is negative; positive rotations about x, y and z
	# raise the nose, turn it left and lower the left wing.
	var thrust: Vector3 = Vector3(axis["strafe"], axis["lift"], -axis["forward"])
	var turn: Vector3 = Vector3(
		pitch * MAX_PITCH_RATE,
		-axis["yaw"] * MAX_YAW_RATE,
		-axis["roll"] * MAX_ROLL_RATE)
	var afterburner: bool = _axis_value(controls, "afterburner") >= BUTTON_THRESHOLD
	if afterburner and axis["forward"] >= 0.0:
		thrust.z = -1.0
	var input: ShipInput = ShipInput.from_floats(thrust, turn, afterburner)
	input.fire_primary = _axis_value(controls, "fire_primary") >= BUTTON_THRESHOLD
	input.slot_held = _axis_value(controls, "slot_part") >= BUTTON_THRESHOLD
	return input


## True when the controls bound to `action` add up to at least
## `BUTTON_THRESHOLD`. `buttons` maps names from `BUTTONS` to pressed, as in
## `map_controls`; left-handed mode swaps hands the same way. For view actions
## such as `show_map`, which never reach `ShipInput`.
func action_held(action: String, buttons: Dictionary) -> bool:
	var controls: Dictionary = {}
	for button: String in BUTTONS:
		controls[button] = 1.0 if buttons.get(button, false) else 0.0
	if left_handed:
		controls = _swap_hands(controls)
	return _axis_value(controls, action) >= BUTTON_THRESHOLD


## The physical controls that drive `action`, after left-handed mode moves
## them to the other hand; only bindings with a non-zero weight count.
func physical_controls(action: String) -> Array[String]:
	var result: Array[String] = []
	var bindings: Dictionary = layout.get(action, {})
	for control: Variant in bindings:
		if is_zero_approx(float(bindings[control])):
			continue
		var name: String = str(control)
		if left_handed:
			name = str(_swap_hands({name: 0.0}).keys()[0])
		result.append(name)
	return result


func _axis_value(controls: Dictionary, axis_name: String) -> float:
	var bindings: Dictionary = layout.get(axis_name, {})
	var total: float = 0.0
	for control: Variant in bindings:
		total += float(controls.get(control, 0.0)) * float(bindings[control])
	return clampf(total, -1.0, 1.0)


static func _swap_hands(controls: Dictionary) -> Dictionary:
	var swapped: Dictionary = {}
	for control: String in controls:
		var other: String = control
		if control.begins_with("left_"):
			other = "right_" + control.trim_prefix("left_")
		elif control.begins_with("right_"):
			other = "left_" + control.trim_prefix("right_")
		swapped[other] = controls[control]
	return swapped
