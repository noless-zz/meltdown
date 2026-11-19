class_name MenuTap
extends RefCounted

## A short tap of the left menu button (Backspace in the flat build): pressed
## and released before `ResetHold.RESET_HOLD_SECONDS`. A hold that long is the
## reset (#90), so one press is never both. The tap asks for the update check
## and chooses "Update" on its notice (#646). Times come from a steady clock
## passed in, so tests need no device and no frame deltas.

var _held: bool = false
var _down_at: float = 0.0


static func steady_seconds() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Feeds this frame's button state at time `now`, once per frame. True only on
## the frame a tap is released.
func feed(pressed: bool, now: float) -> bool:
	var tapped: bool = false
	if pressed and not _held:
		_down_at = now
	elif not pressed and _held:
		tapped = now - _down_at < ResetHold.RESET_HOLD_SECONDS
	_held = pressed
	return tapped
