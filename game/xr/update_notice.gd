class_name UpdateNotice
extends Node3D

## The in-app update notice on the status panel (#646). It offers a newer
## build with two choices, "Update" (a tap of the left menu button) and
## "Later" (let it go: it hides after `OFFER_SECONDS`), or shows a one-line
## reason for a check the pilot asked for. It is handed plain text and only
## emits the choice; it never starts a download or an install itself.
##
## Drawn like the panel's own labels and placed above them, clear of the
## large outcome and preset labels. Text only, no motion (CMF-3).

signal update_chosen
signal later_chosen

const NODE_NAME: String = "UpdateNotice"
const LINE_NAME: String = "UpdateLine"
const CHOICES_NAME: String = "UpdateChoices"
const CHOICES_TEXT: String = "Update: tap Menu    Later: wait"
const POSITION: Vector3 = Vector3(0.0, 0.25, 0.0)
const CHOICES_Y: float = -0.022
## Long enough to read and decide; the offer comes back on the next start.
const OFFER_SECONDS: float = 20.0
const REASON_SECONDS: float = 5.0

## True while the "Update" / "Later" choice is open.
var offering: bool = false
## Seconds until the notice hides; 0 when hidden.
var seconds_left: float = 0.0

var _line: Label3D
var _choices: Label3D


func _init() -> void:
	name = NODE_NAME
	position = POSITION
	_line = StatusPanelLabels.make(self, LINE_NAME, Vector3.ZERO, StatusPanel.SMALL_FONT)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choices = StatusPanelLabels.make(self, CHOICES_NAME, Vector3(0.0, CHOICES_Y, 0.0), StatusPanel.SMALL_FONT)
	_choices.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choices.text = CHOICES_TEXT
	_hide()


func _process(delta: float) -> void:
	advance(delta)


## Opens the choice with `text` as its first line.
func offer(text: String) -> void:
	StatusPanelLabels.set_text(_line, text)
	offering = true
	seconds_left = OFFER_SECONDS
	_line.visible = true
	_choices.visible = true


## Shows `text` alone for `REASON_SECONDS`, unless a choice is open: the offer
## matters more than why a later check said nothing new.
func tell(text: String) -> void:
	if offering or text == "":
		return
	StatusPanelLabels.set_text(_line, text)
	seconds_left = REASON_SECONDS
	_line.visible = true
	_choices.visible = false


## The pilot chose "Update". Returns false, doing nothing, when no choice is open.
func choose_update() -> bool:
	if not offering:
		return false
	_hide()
	update_chosen.emit()
	return true


func is_showing() -> bool:
	return _line.visible


func line_text() -> String:
	return _line.text


func advance(delta: float) -> void:
	if seconds_left <= 0.0:
		return
	seconds_left = maxf(seconds_left - delta, 0.0)
	if seconds_left > 0.0:
		return
	var was_offering: bool = offering
	_hide()
	if was_offering:
		later_chosen.emit()


func _hide() -> void:
	offering = false
	seconds_left = 0.0
	_line.visible = false
	_choices.visible = false
