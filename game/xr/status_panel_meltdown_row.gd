class_name StatusPanelMeltdownRow
extends RefCounted

## The status panel's meltdown countdown row (#315). Split out of
## `StatusPanel` when the weapon row and hold messages joined it (#605), so
## the panel stays short; what is drawn is unchanged.

## How many times the label's text was replaced; read by tests only.
var text_changes: int = 0

var _label: Label3D


func _init(label: Label3D) -> void:
	_label = label
	# Hidden until a meltdown starts: most of a run has no countdown.
	_label.visible = false


## Shows the countdown as "Meltdown m:ss"; a negative value hides the row (no
## meltdown). Whole seconds are floored, so the row reads 0:00 only in the
## last second. Safe to call every frame: the glyphs are rebuilt only when the
## shown second changes. Under `MELTDOWN_WARNING_SECONDS` it turns red.
func show(seconds_left: float) -> void:
	if seconds_left < 0.0:
		_label.visible = false
		return
	_label.visible = true
	var whole: int = floori(seconds_left)
	if StatusPanelLabels.set_text(_label, "Meltdown %d:%02d" % [floori(whole / 60.0), whole % 60]):
		text_changes += 1
	_label.modulate = StatusPanel.HULL_WARNING_COLOR \
		if seconds_left < StatusPanel.MELTDOWN_WARNING_SECONDS else StatusPanel.TEXT_COLOR


func visible() -> bool:
	return _label.visible


func warning_shown() -> bool:
	return _label.modulate == StatusPanel.HULL_WARNING_COLOR
