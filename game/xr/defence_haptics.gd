class_name DefenceHaptics
extends RefCounted

## Warns the pilot before the ship is lost, on every comfort preset (#616,
## CMB-2, PLT-6): one pulse on both hands when the hull falls to the low-hull
## mark, and a distinct short pulse when the shield breaks (falls from above
## zero to zero). Each fires once per crossing; the hull must rise above the
## mark, or the shield above zero, before the same pulse can fire again.
##
## It is handed plain fractions and never reads or writes `ShipState` or `Sim`
## (ARC-3, MP-2). The pulses come from `HapticsSpec.DEFAULT_FILE` and the mark
## from the status panel's look file, the same one the hull bar's red uses.

## The OpenXR output action bound to both hands, as `BoostHaptics` uses.
const HAPTIC_ACTION: String = "haptic"

## The pulses; null when the file was rejected, so nothing is sent.
var spec: HapticsSpec = null
## At or below this hull fraction the low-hull pulse fires.
var low_hull_fraction: float = StatusPanel.HULL_WARNING_FRACTION
## The rig's hands, set by the scene; null in tests and flat runs.
var left_controller: XRController3D = null
var right_controller: XRController3D = null
## Called with (hand: String, pulse: Dictionary) for every pulse asked for,
## sent or not, so tests can record the requests without a controller.
var request_hook: Callable = Callable()

## False until the first values, so a ship that starts low or without a
## shield does not pulse on its first frame.
var _seen: bool = false
var _hull_low: bool = false
var _shield_up: bool = false


func _init(haptics: HapticsSpec = null, low_hull: float = StatusPanel.HULL_WARNING_FRACTION) -> void:
	spec = haptics
	low_hull_fraction = low_hull


## The warnings with the shipped haptics and look files.
## A rejected haptics file is printed once and sends nothing.
static func load_shipped() -> DefenceHaptics:
	var haptics: HapticsSpec = HapticsSpec.load_file()
	if haptics.error != "":
		print("Meltdown: defence haptics off: %s" % haptics.error)
		haptics = null
	return DefenceHaptics.new(haptics, float(StatusPanelLook.load_file()["low_hull_fraction"]))


## Call once per frame with the local ship's shield and hull as fractions of
## their maximums. Returns the kinds that fired this frame, in the order sent.
## Pulses reach a controller only while `xr_running`.
func update(shield_fraction: float, hull_fraction: float, xr_running: bool) -> Array[String]:
	var fired: Array[String] = []
	var hull_low: bool = hull_fraction <= low_hull_fraction
	var shield_up: bool = shield_fraction > 0.0
	if _seen:
		if shield_up != _shield_up and not shield_up:
			fired.append(HapticsSpec.SHIELD_BREAK)
		if hull_low and not _hull_low:
			fired.append(HapticsSpec.LOW_HULL)
	_seen = true
	_hull_low = hull_low
	_shield_up = shield_up
	for kind: String in fired:
		_pulse_both(kind, xr_running)
	return fired


## Forgets the last values, as at the start: used after a restart, so the new
## ship's first frame is not compared with the destroyed one.
func reset() -> void:
	_seen = false


func _pulse_both(kind: String, xr_running: bool) -> void:
	if spec == null:
		return
	var pulse: Dictionary = spec.pulse_for(kind)
	if pulse.is_empty():
		return
	for hand: String in ["left", "right"]:
		if request_hook.is_valid():
			request_hook.call(hand, pulse)
		var controller: XRController3D = left_controller if hand == "left" else right_controller
		if not xr_running or controller == null:
			continue
		controller.trigger_haptic_pulse(HAPTIC_ACTION, pulse["frequency_hz"],
			pulse["amplitude"], pulse["duration_s"], 0.0)
