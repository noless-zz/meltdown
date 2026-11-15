class_name ResetHold
extends RefCounted

## The deliberate way back to the start (#90): hold both stick clicks, or
## Backspace in the flat build, for `RESET_HOLD_SECONDS`. The view fades to
## black, exactly one tick's input then asks the simulation for
## `reset_to_start`, and the view fades back in, so the pilot never sees the
## ship sweep to the start (CMF-8). The Meta button cannot be used: the system
## reserves it.
##
## This class only times the gesture and the fade. It never touches ship
## state; the reset goes through `ShipInput` and the simulation (ARC-3, MP-2).
## A hold fires once and re-arms only after both clicks are released, so a
## pilot who keeps holding is not reset again and again.

enum Phase { IDLE, FADING_OUT, BLACK, FADING_IN }

const RESET_HOLD_SECONDS: float = 1.0
const FADE_SECONDS: float = 0.25
## The flat build's stand-in for the two stick clicks, a physical key.
const KEYBOARD_KEY: Key = KEY_BACKSPACE
## The button name `main.gd` sets while `KEYBOARD_KEY` is held. No mapping
## binds it, so it flies nothing.
const KEYBOARD_BUTTON: String = "reset_key"

var phase: Phase = Phase.IDLE
## Black overlay opacity, 0 (clear) to 1 (black).
var alpha: float = 0.0
## Seconds the current hold has lasted; 0 when not held or already fired.
var held_seconds: float = 0.0

var _held: bool = false
var _armed: bool = true


## True when `values` (sampled controller or keyboard values) hold the gesture.
static func is_held(values: Dictionary) -> bool:
	var buttons: Dictionary = values.get("buttons", {})
	if bool(buttons.get(KEYBOARD_BUTTON, false)):
		return true
	return bool(buttons.get("left_stick_click", false)) \
		and bool(buttons.get("right_stick_click", false))


## Records whether the gesture is held this frame. Letting go cancels a hold
## that has not fired yet and re-arms after one that has.
func press(held: bool) -> void:
	_held = held
	if not held:
		_armed = true
		held_seconds = 0.0


## Moves the hold timer and the fade on by `delta` seconds.
func advance(delta: float) -> void:
	if _held and _armed:
		held_seconds += delta
		if held_seconds >= RESET_HOLD_SECONDS and (phase == Phase.IDLE or phase == Phase.FADING_IN):
			_armed = false
			held_seconds = 0.0
			phase = Phase.FADING_OUT
	match phase:
		Phase.FADING_OUT:
			alpha = minf(alpha + delta / FADE_SECONDS, 1.0)
			if alpha >= 1.0:
				phase = Phase.BLACK
		Phase.FADING_IN:
			alpha = maxf(alpha - delta / FADE_SECONDS, 0.0)
			if alpha <= 0.0:
				phase = Phase.IDLE


## True while the view is black and the reset has not been flown yet.
func reset_due() -> bool:
	return phase == Phase.BLACK


## A tick has flown the reset; the view may fade back in.
func reset_flown() -> void:
	if phase == Phase.BLACK:
		phase = Phase.FADING_IN
