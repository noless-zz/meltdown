class_name BoostHaptics
extends RefCounted

## Notices each afterburner start and stop, logs it, and asks for a haptic
## pulse on the hand that holds the boost control (PLT-6, #146, #170).
##
## It sits beside `main.gd` because it reads the ship state the session
## hands out and drives the scene's controllers. It only reads copies of
## `ShipState`; it never writes `ShipState` or `Sim` (ARC-3, MP-2).

## The OpenXR output action bound to both hands in `openxr_action_map.tres`.
const HAPTIC_ACTION: String = "haptic"

## The pulses, from `HapticsSpec.DEFAULT_FILE`. Null when the file was
## rejected: the log line still prints, no pulse is sent.
var spec: HapticsSpec = load_spec(HapticsSpec.DEFAULT_FILE)
## The rig's hands, set by the scene; null in tests and flat runs.
var left_controller: XRController3D = null
var right_controller: XRController3D = null
## Called with (hand: String, pulse: Dictionary) for every pulse asked for,
## sent or not, so tests can record the requests without a controller.
var request_hook: Callable = Callable()

## The afterburner state last seen, so each start and stop counts once.
var _active: bool = false


## Reads the haptics file at `path`. A rejected file is printed once, here,
## and gives null, so no pulse is sent rather than one with guessed values.
static func load_spec(path: String) -> HapticsSpec:
	var loaded: HapticsSpec = HapticsSpec.load_file(path)
	if loaded.error != "":
		print("Meltdown: haptics off: %s" % loaded.error)
		return null
	return loaded


## Call once per frame with the latest ship's afterburner state. On a change
## it prints the afterburner log line and, at the same moment, asks for the
## matching pulse on the boosting hand of `mapping`. Pulses reach a
## controller only while `xr_running`; otherwise nothing is sent. Returns the
## event kind, or empty when nothing changed.
func update(afterburner_active: bool, mapping: ThumbstickMapping, xr_running: bool) -> String:
	if afterburner_active == _active:
		return ""
	_active = afterburner_active
	print("Meltdown: afterburner %s" % ("on" if afterburner_active else "off"))
	var kind: String = HapticsSpec.BOOST_START if afterburner_active else HapticsSpec.BOOST_STOP
	_pulse(kind, HapticsSpec.hand_for_action(mapping, "afterburner"), xr_running)
	return kind


func _pulse(kind: String, hand: String, xr_running: bool) -> void:
	if spec == null or hand == "":
		return
	var pulse: Dictionary = spec.pulse_for(kind)
	if pulse.is_empty():
		return
	if request_hook.is_valid():
		request_hook.call(hand, pulse)
	if not xr_running:
		return
	var controller: XRController3D = left_controller if hand == "left" else right_controller
	if controller == null:
		return
	controller.trigger_haptic_pulse(HAPTIC_ACTION, pulse["frequency_hz"], pulse["amplitude"],
		pulse["duration_s"], 0.0)
