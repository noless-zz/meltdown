class_name ComfortCustomNotice
extends RefCounted

## Counts the times a rejected custom comfort file kept the custom mode from
## being chosen (CMF-1, #807), so the status panel can say so in the headset
## instead of only in the log. The panel shows the notice once per count, so
## a file rejected at start and again when asked for shows twice.
##
## View side only: it reads the parsed file and never touches simulation state
## (ARC-3).

## How many rejections have been reported so far.
var reports: int = 0
## The field the latest rejection named (`ComfortCustom.rejected_field`).
var field: String = ""

var _start_checked: bool = false


## Reports `custom` once, the first time it is called: the start of the run.
## A missing file is no rejection.
func check_start(custom: ComfortCustom) -> void:
	if _start_checked:
		return
	_start_checked = true
	refused(custom)


## Reports `custom` when it was rejected: the custom mode was asked for and
## the file kept it away.
func refused(custom: ComfortCustom) -> void:
	if custom == null or custom.error.is_empty():
		return
	_start_checked = true  # A refusal at start is the start's report.
	reports += 1
	field = custom.rejected_field()
