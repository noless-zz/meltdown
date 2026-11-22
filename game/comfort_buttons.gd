class_name ComfortButtons
extends RefCounted

## Press and hold bookkeeping of the two development buttons on the hand that
## does not turn: the preset switch (#613) and the control-label toggle, which
## may share its button with the map (#335, #914). Split out of
## `comfort_wiring.gd` (#1157): `ComfortWiring` extends this class, so every
## caller keeps the names it used, with no forwarding layer.
##
## Neither button is a flight control: nothing here reaches `ShipInput` (ARC-3).

## Seconds on a steady clock; `read_label_button` times a click with it. Tests
## replace it so a hold can be timed without waiting.
var clock: Callable = ClickHold.steady_seconds
## Click or hold of the label button, fed by `read_label_button` with `clock`
## each frame. The map reads it too while the label button also shows the map
## (`shared_click_hold`), so both answers come from one timer (#335).
var click_hold: ClickHold = ClickHold.new()

## Read for which hand carries each button.
var _mapping: ThumbstickMapping
## The preset switch acts once per press, not once per frame it is held.
var _preset_button_held: bool = false
## The label toggle, likewise, flips once per click.
var _label_button_held: bool = false


func _init(p_mapping: ThumbstickMapping) -> void:
	_mapping = p_mapping


## The development preset switch: the lower face button of the hand that does
## not turn (X, or A when left-handed; #613). Read here rather than bound in
## the layout, since it is not a flight control and a settings menu replaces it.
func preset_button() -> String:
	return _mapping.preset_button()


## True on the one frame the preset button goes down.
func preset_pressed(buttons: Dictionary) -> bool:
	var pressed: bool = bool(buttons.get(preset_button(), false))
	var went_down: bool = pressed and not _preset_button_held
	_preset_button_held = pressed
	return went_down


## The control-label toggle: the stick click of the hand that does not turn
## (left, or right when left-handed), as decision record 0004 places it.
func label_button() -> String:
	return _mapping.label_button()


## True on the one frame a press should flip the labels. When the label button
## also toggles the map (`show_map`), that is the frame a hold reaches
## `MapHologram.HOLD_SECONDS`, as `click_hold` decides, since a click toggles
## the map (#914); otherwise the frame the button goes down. Call once per
## frame, before the map reads `shared_click_hold`.
func read_label_button(buttons: Dictionary) -> bool:
	var pressed: bool = bool(buttons.get(label_button(), false))
	var went_down: bool = pressed and not _label_button_held
	_label_button_held = pressed
	if not label_button_shows_map():
		return went_down
	click_hold.feed(pressed, float(clock.call()))
	return click_hold.long_hold_started()


## True while `show_map` is bound to the label button.
func label_button_shows_map() -> bool:
	return _mapping.physical_controls("show_map").has(label_button())


## The `ClickHold` the map must read while it shares the label button, null
## when `show_map` is on another control and the map toggles on its own press.
func shared_click_hold() -> ClickHold:
	return click_hold if label_button_shows_map() else null
