class_name ClickHold
extends RefCounted

## One button that means two things by how long it is held (#335, MAP-1,
## PLT-5): a short click (the control-label toggle) or a long hold (the map
## hologram). Both answers come from this one object, fed once per frame with
## one clock, so a press near the threshold can never count as both. Before
## this, the map timed the hold with frame deltas and the labels with a steady
## clock, and one press of about `MapHologram.HOLD_SECONDS` could do both.
##
## The rule that makes the two exclusive: a press is a long hold from the first
## frame that sees it still down at least `MapHologram.HOLD_SECONDS` after it
## went down; a press released before any such frame is a short click. A
## release seen exactly at the threshold therefore counts as a click, because
## no frame saw the button down that long.
##
## It holds only the button state and two times; it never touches the
## simulation or comfort settings (ARC-3, CMF-6).

## Slack for the subtraction of two clock readings, far below one frame and
## one microsecond tick of the clock, so a hold of exactly the threshold
## is not lost to rounding.
const EPSILON_SECONDS: float = 1e-7

var _held: bool = false
var _down_at: float = 0.0
var _long: bool = false
var _short_released: bool = false


## Seconds on the steady clock the feeder should use unless a test replaces it.
static func steady_seconds() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Feeds this frame: whether the button is down and the time `now` in seconds.
## Call exactly once per frame.
func feed(pressed: bool, now: float) -> void:
	_short_released = false
	if pressed and not _held:
		_down_at = now
		_long = false
	elif pressed and not _long:
		_long = now - _down_at >= MapHologram.HOLD_SECONDS - EPSILON_SECONDS
	elif not pressed and _held:
		_short_released = not _long
		_long = false
	_held = pressed


## True on every frame from the one the hold reached the threshold until the
## frame before release.
func is_long_hold() -> bool:
	return _long


## True only on the frame of a release that came before the hold threshold.
func short_click_released() -> bool:
	return _short_released


## True while the button is down.
func is_held() -> bool:
	return _held
