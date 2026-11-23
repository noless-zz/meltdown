class_name DevMenuValueToggle
extends DevMenuValue

## An on / off value (#908): the break reminder, refresh and swivel chair
## entries. Two choices, so either direction flips it.

var prefix: String
## What confirming returns after the prefix, on and off.
var on_choice: String
var off_choice: String
var on_text: String
var off_text: String
## Shown after the value while `noted` or `locked`.
var note: String
var on: bool = false
## While locked, left and right leave the value alone (the swivel entry while
## the custom comfort file decides it, #853).
var locked: bool = false
var noted: bool = false


func _init(p_prefix: String, p_on_choice: String, p_off_choice: String, p_on_text: String,
		p_off_text: String, p_note_text: String = "", p_on: bool = false) -> void:
	prefix = p_prefix
	on_choice = p_on_choice
	off_choice = p_off_choice
	on_text = p_on_text
	off_text = p_off_text
	note = p_note_text
	on = p_on


func plain_text() -> String:
	return on_text if on else off_text


func note_text() -> String:
	return note if noted or locked else ""


func step(_direction: int) -> void:
	if not locked:
		on = not on


func confirmed() -> String:
	return prefix + (on_choice if on else off_choice)
