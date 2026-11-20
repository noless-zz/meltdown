class_name HitHaptics
extends RefCounted

## The controller side of the hit cue (#618; CMB-2, PLT-6): a short pulse on
## the hand on the side a shot came from (both for the front, top and bottom,
## which no single hand points at), and a lighter, distinct pulse on both
## hands when a part goes into the hold (#600). The sides are the cockpit's
## left and right, so left-handed mode does not swap them.
##
## It is handed sides and never reads or writes `ShipState` or `Sim` (ARC-3,
## MP-2). The pulses come from `HapticsSpec.DEFAULT_FILE`.

## The OpenXR output action bound to both hands, as `BoostHaptics` uses.
const HAPTIC_ACTION: String = "haptic"

## The pulses; null when the file was rejected, so nothing is sent.
var spec: HapticsSpec = null
## The rig's hands, set by the scene; null in tests and flat runs.
var left_controller: XRController3D = null
var right_controller: XRController3D = null
## Called with (hand: String, pulse: Dictionary) for every pulse asked for,
## sent or not, so tests can record the requests without a controller.
var request_hook: Callable = Callable()


func _init(haptics: HapticsSpec = null) -> void:
	spec = haptics


## The cue with the shipped haptics file; a rejected file is printed once and sends nothing.
static func load_shipped() -> HitHaptics:
	var haptics: HapticsSpec = HapticsSpec.load_file()
	if haptics.error != "":
		print("Meltdown: hit haptics off: %s" % haptics.error)
		haptics = null
	return HitHaptics.new(haptics)


## The hands that pulse for a hit from `side` (a `HitFlash` side).
static func hands_for(side: String) -> Array[String]:
	if side == HitFlash.LEFT:
		return ["left"]
	if side == HitFlash.RIGHT:
		return ["right"]
	return ["left", "right"]


## One hit from `side`. Pulses reach a controller only while `xr_running`.
func hit(side: String, xr_running: bool) -> void:
	_pulse(HapticsSpec.SHIP_HIT, hands_for(side), xr_running)


## One part taken into the hold.
func pickup(xr_running: bool) -> void:
	_pulse(HapticsSpec.SALVAGE_PICKUP, ["left", "right"], xr_running)


func _pulse(kind: String, hands: Array[String], xr_running: bool) -> void:
	if spec == null:
		return
	var pulse: Dictionary = spec.pulse_for(kind)
	if pulse.is_empty():
		return
	for hand: String in hands:
		if request_hook.is_valid():
			request_hook.call(hand, pulse)
		var controller: XRController3D = left_controller if hand == "left" else right_controller
		if not xr_running or controller == null:
			continue
		controller.trigger_haptic_pulse(HAPTIC_ACTION, pulse["frequency_hz"],
			pulse["amplitude"], pulse["duration_s"], 0.0)
