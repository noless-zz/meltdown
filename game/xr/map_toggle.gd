class_name MapToggle
extends RefCounted

## Whether the hand-held map is open, from the `show_map` button (#914, MAP-1,
## PLT-5): a click opens it and the next click closes it, so nothing has to be
## held while steering with the same stick. Split from `MapHologram` to keep that
## file under the size limit.
##
## Sharing the label button, it reads the label wiring's `ClickHold` (#335): a
## press released before `MapHologram.HOLD_SECONDS` toggles the map on its
## release, and a longer hold (the label toggle) leaves it as it was, so one
## press never does both. Alone on its control, each press toggles it as it goes
## down. It only reads buttons and never touches the simulation (ARC-3, CMF-6).

## Whether `show_map` was down last frame, for the press edge of an unshared button.
var _was_pressed: bool = false


## Feeds one frame of `show_map` down or up; returns `open` flipped on the frame
## it goes down.
func press(pressed: bool, open: bool) -> bool:
	var flipped: bool = pressed and not _was_pressed
	_was_pressed = pressed
	return open != flipped


## Reads `show_map` through `mapping` from sampled `buttons` and returns whether
## the map is open after this frame, given it was `open`. With `shared` (the label
## button's `ClickHold`, given only while that button also toggles the map), a
## short click toggles it; feed `shared` first.
func read(mapping: ThumbstickMapping, buttons: Dictionary, shared: ClickHold, open: bool) -> bool:
	var pressed: bool = mapping.action_held("show_map", buttons)
	if shared == null:
		return press(pressed, open)
	_was_pressed = pressed
	return open != shared.short_click_released()
