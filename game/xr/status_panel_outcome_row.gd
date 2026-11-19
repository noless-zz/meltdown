class_name StatusPanelOutcomeRow
extends RefCounted

## The status panel's large outcome row (#361). Split out of `StatusPanel`
## when the weapon row and hold messages joined it (#605), so the panel stays
## short; what is drawn is unchanged.

## How many times the label's text was replaced; read by tests only.
var text_changes: int = 0

var _label: Label3D
var _escaped_color: Color
var _shown: int = ExitRule.Outcome.RUNNING


func _init(label: Label3D, escaped_color: Color) -> void:
	_label = label
	_escaped_color = escaped_color
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Hidden while the level runs, which is nearly always.
	_label.visible = false


## Shows how the level ended, from `ExitRule.Outcome`: `RUNNING` hides the
## row, `ESCAPED` reads `ESCAPED_TEXT` in the look's colour and `LOST` reads
## `LOST_TEXT` in the hull-warning red. Safe to call every frame: nothing is
## touched unless the outcome changed. The row never moves or animates (CMF-3).
func show(outcome: int) -> void:
	if outcome == _shown:
		return
	_shown = outcome
	if outcome == ExitRule.Outcome.ESCAPED:
		_apply(StatusPanel.ESCAPED_TEXT, _escaped_color)
	elif outcome == ExitRule.Outcome.LOST:
		_apply(StatusPanel.LOST_TEXT, StatusPanel.HULL_WARNING_COLOR)
	else:
		_label.visible = false


func visible() -> bool:
	return _label.visible


func _apply(text: String, color: Color) -> void:
	if StatusPanelLabels.set_text(_label, text):
		text_changes += 1
	_label.modulate = color
	_label.visible = true
