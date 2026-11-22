class_name DevMenuRelease
extends RefCounted

## Keeps the controls the dev menu was using away from the ship after it
## closes (#1206). The owner's playtest of 22 Nov found that choosing a row
## flew the ship: A confirms in the menu and is the afterburner in flight, so
## an A still down on the frame after Close, Level or Restart level closed the
## menu boosted the ship forward. A stick or trigger still held when a tap
## closed the menu reached the ship the same way.
##
## `hold` notes every stick off centre, every trigger or grip pulled and every
## button down when the menu closes; `filter` then reads each of them as idle
## until it has been released (or returned to centre) once, and lets it act
## again after that. The menu button never latches, so a hold still resets.
## Input values only; nothing here touches the simulation (ARC-3, MP-2).

## A stick inside this length counts as back at centre.
const STICK_CENTRE: float = 0.2
## A trigger or grip under this pull counts as released.
const PULL_RELEASED: float = 0.1
const STICKS: Array[String] = ["left_stick", "right_stick"]
const PULLS: Array[String] = ["left_trigger", "right_trigger", "left_grip", "right_grip"]

## Value keys and button names still held since the menu closed.
var _controls: Array[String] = []
var _buttons: Array[String] = []


## Notes what `values` holds on the frame the menu closes.
func hold(values: Dictionary) -> void:
	_controls.clear()
	_buttons.clear()
	for key: String in STICKS + PULLS:
		if _active(key, values):
			_controls.append(key)
	var buttons: Dictionary = values.get("buttons", {})
	for button: Variant in buttons:
		if bool(buttons[button]) and not _passes(str(button)):
			_buttons.append(str(button))


## True while a control held at the close has not been released yet.
func holding() -> bool:
	return not (_controls.is_empty() and _buttons.is_empty())


## `values` with every control still held since the close read as idle.
## Unchanged, and the same dictionary, once all of them have been released.
func filter(values: Dictionary) -> Dictionary:
	if not holding():
		return values
	var shown: Dictionary = values.duplicate(true)
	for key: String in _controls.duplicate():
		if not _active(key, values):
			_controls.erase(key)
		else:
			shown[key] = Vector2.ZERO if STICKS.has(key) else 0.0
	var buttons: Dictionary = shown.get("buttons", {})
	for button: String in _buttons.duplicate():
		if not bool(buttons.get(button, false)):
			_buttons.erase(button)
		else:
			buttons.erase(button)
	shown["buttons"] = buttons
	return shown


static func _active(key: String, values: Dictionary) -> bool:
	if STICKS.has(key):
		var stick: Vector2 = values.get(key, Vector2.ZERO)
		return stick.length() > STICK_CENTRE
	return float(values.get(key, 0.0)) > PULL_RELEASED


static func _passes(button: String) -> bool:
	return button == ResetHold.BUTTON or button == ResetHold.KEYBOARD_BUTTON
