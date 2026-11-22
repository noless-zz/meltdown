class_name ThumbstickMapping
extends RefCounted

## The thumbsticks-only control scheme (PLT-5) as a pure mapping from
## controller values to one tick's `ShipInput` (FLT-1).
##
## It reads no input device: the caller passes the values it read, so the
## mapping can be tested without a headset and the same code serves every
## controller source. Comfort filtering is not done here (ARC-3).
##
## The default right-handed layout (decision record 0004) and layout files
## are read by `ThumbstickLayout` (#1158); `default_layout`, `from_file` and
## `from_json` forward to it so callers do not change. X (left lower) is
## bound by no layout and does nothing; it is free for future use (decision
## record 0011, #1260). The comfort preset is chosen in the menu (CMF-4).
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

## Radial dead zone of each stick as a fraction of full deflection, used when
## the layout sets none. Drift inside it gives exactly zero, so a resting
## stick never moves the ship.
const STICK_DEAD_ZONE: float = StickDeadZone.DEFAULT
const MAX_PITCH_RATE: float = PI / 2.0
const MAX_YAW_RATE: float = PI / 2.0
const MAX_ROLL_RATE: float = PI * 0.75

const AXES: Array[String] = ThumbstickLayout.AXES
const BUTTON_ACTIONS: Array[String] = ThumbstickLayout.BUTTON_ACTIONS
const VIEW_ACTIONS: Array[String] = ThumbstickLayout.VIEW_ACTIONS
## Half way, so an action bound to a trigger or grip fires at half pull.
const BUTTON_THRESHOLD: float = 0.5
const CONTROLS: Array[String] = ThumbstickLayout.CONTROLS
## The controls passed in the `buttons` argument of `map_controls`.
const BUTTONS: Array[String] = [
	"left_button_lower", "left_button_upper", "right_button_lower", "right_button_upper",
	"left_stick_click", "right_stick_click",
]

## The control-label toggle in right-handed mode: the left stick click (#181,
## decision record 0004). Read outside the mapping; `label_button` swaps it.
const LABEL_BUTTON: String = "left_stick_click"

const LAYOUTS_DIR: String = ThumbstickLayout.LAYOUTS_DIR
const DEFAULT_LAYOUT_FILE: String = ThumbstickLayout.DEFAULT_LAYOUT_FILE
const PAIRED_LAYOUT_FILE: String = ThumbstickLayout.PAIRED_LAYOUT_FILE

## Ship axis or button action -> {physical control: weight}. The settings menu can replace this
## to remap controls without code changes.
var layout: Dictionary = {}
var left_handed: bool = false
var invert_pitch: bool = false
## Applied to both sticks, whichever hand flies (#855).
var stick_dead_zone: float = STICK_DEAD_ZONE
## Set when the layout's dead zone was rejected and the default used; the
## bindings still loaded. Empty otherwise.
var warning: String = ""
## Set by `from_json` or `from_file` when the layout was rejected; empty otherwise.
var error: String = ""


func _init(p_layout: Dictionary = default_layout()) -> void:
	layout = p_layout


## A fresh copy of the default right-handed layout, safe to edit.
static func default_layout() -> Dictionary:
	return ThumbstickLayout.default_layout()


## `ThumbstickLayout.from_file` as a mapping: on a missing or rejected file
## the built-in default and `error` saying why.
static func from_file(path: String) -> ThumbstickMapping:
	return _from_layout(ThumbstickLayout.from_file(path))


## `ThumbstickLayout.from_json` as a mapping; `source` names the file in a
## dead zone warning.
static func from_json(text: String, source: String = "layout") -> ThumbstickMapping:
	return _from_layout(ThumbstickLayout.from_json(text, source))


static func _from_layout(read: ThumbstickLayout) -> ThumbstickMapping:
	var mapping: ThumbstickMapping = ThumbstickMapping.new(read.bindings)
	mapping.stick_dead_zone = read.stick_dead_zone
	mapping.warning = read.warning
	mapping.error = read.error
	return mapping


## `StickDeadZone.apply`; the default dead zone unless one is given.
static func apply_dead_zone(stick: Vector2, dead_zone: float = STICK_DEAD_ZONE) -> Vector2:
	return StickDeadZone.apply(stick, dead_zone)


## Maps one frame of controller values to the input for one tick. Triggers
## and grips are 0..1; `buttons` maps button names from `BUTTONS` (face
## buttons and stick clicks) to pressed, and a missing button counts as
## released, so callers that pass no buttons never fire the afterburner.
func map_controls(left_stick: Vector2, right_stick: Vector2,
		left_trigger: float, right_trigger: float,
		left_grip: float, right_grip: float,
		buttons: Dictionary = {}) -> ShipInput:
	var left: Vector2 = apply_dead_zone(left_stick, stick_dead_zone)
	var right: Vector2 = apply_dead_zone(right_stick, stick_dead_zone)
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
		controls = ThumbstickLayout.swap_hands(controls)
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
		controls = ThumbstickLayout.swap_hands(controls)
	return _axis_value(controls, action) >= BUTTON_THRESHOLD


## The physical control-label toggle: the left stick click, or the right one
## when left-handed.
func label_button() -> String:
	return str(ThumbstickLayout.swap_hands({LABEL_BUTTON: 0.0}).keys()[0]) if left_handed else LABEL_BUTTON


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
			name = str(ThumbstickLayout.swap_hands({name: 0.0}).keys()[0])
		result.append(name)
	return result


func _axis_value(controls: Dictionary, axis_name: String) -> float:
	var bindings: Dictionary = layout.get(axis_name, {})
	var total: float = 0.0
	for control: Variant in bindings:
		total += float(controls.get(control, 0.0)) * float(bindings[control])
	return clampf(total, -1.0, 1.0)
