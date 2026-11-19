class_name StatusPanelHoldRow
extends RefCounted

## The status panel's hold row: "Hold <part>" or "Hold empty" (#290), and for
## a short while after a pickup or a slotting, a message saying what happened
## instead (#605). Split out of `StatusPanel` so the panel stays short.

## How many times the label's text was replaced; read by tests only.
var text_changes: int = 0
## Seconds the message has left; 0 when the row shows the hold.
var seconds_left: float = 0.0

var _label: Label3D
var _message_seconds: float
var _part_text: String = StatusPanel.HOLD_EMPTY
var _message: String = ""


## `label` is the row's label; a message stays up `message_seconds`.
func _init(label: Label3D, message_seconds: float) -> void:
	_label = label
	_message_seconds = maxf(message_seconds, 0.0)
	_label.text = _part_text


## Shows the part in the hold by name; an empty string shows `HOLD_EMPTY`.
## A message that is up keeps the row until it runs out.
func show_part(part_name: String) -> void:
	_part_text = StatusPanel.HOLD_EMPTY if part_name.is_empty() else "Hold %s" % part_name
	_refresh()


## Puts `message` on the row for the message time; a new message restarts it.
func show_message(message: String) -> void:
	if message.is_empty() or _message_seconds <= 0.0:
		return
	_message = message
	seconds_left = _message_seconds
	_refresh()


func advance(delta: float) -> void:
	if seconds_left <= 0.0:
		return
	seconds_left = maxf(seconds_left - maxf(delta, 0.0), 0.0)
	_refresh()


func _refresh() -> void:
	if StatusPanelLabels.set_text(_label, _message if seconds_left > 0.0 else _part_text):
		text_changes += 1
