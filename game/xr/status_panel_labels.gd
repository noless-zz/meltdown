class_name StatusPanelLabels
extends RefCounted

## Builds and updates the status panel's text labels. Split out of
## `StatusPanel` before the outcome row joined it (#361), so the panel stays
## short; what is drawn is unchanged.


## Adds a label under `panel` drawn like every other panel label: unshaded,
## no outline, no shadow, no depth test, and one render priority step above
## the bars' tracks so nothing on the panel covers it (#199).
static func make(panel: Node3D, label_name: String, at: Vector3, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.position = at
	label.pixel_size = StatusPanel.PIXEL_SIZE
	label.font_size = font_size
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.modulate = StatusPanel.TEXT_COLOR
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = StatusPanel.RENDER_PRIORITY_TOP
	panel.add_child(label)
	return label


## Label3D rebuilds its glyph mesh on every assignment; most frames change nothing.
## Returns whether the text was replaced.
static func set_text(label: Label3D, text: String) -> bool:
	if label.text == text:
		return false
	label.text = text
	return true
