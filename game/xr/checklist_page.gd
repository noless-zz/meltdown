class_name ChecklistPage
extends Node3D

## The in-headset test checklist's page (#1325, DEV-6): text only, drawn as
## the dev menu is (one unshaded label, no depth test, just under the fade
## quad), and handed its lines by `ChecklistWiring`, so it knows nothing of the
## checklist file or the simulation (MP-2, ARC-3).
##
## Open, it shows the whole step in front of the head where it opened, like
## the dev menu (`DevMenu.placement`). Pinned, it shrinks to one line, the next
## step, up and to the left of the view, and stays there in the cockpit while
## the pilot flies. It appears and goes without a fade and moves no view
## (CMF-8), so it works the same at every comfort preset.

const NODE_NAME: String = "ChecklistPage"
const LABEL_NAME: String = "Text"
const FULL_DISTANCE_M: float = 1.0
const FULL_PIXEL_SIZE: float = 0.0008
## Wide enough for a step's words at the dev menu's size, about 0.9 m across.
const FULL_WIDTH_PX: float = 1100.0
const PINNED_DISTANCE_M: float = 0.9
## Up and left of the view centre, clear of the dev menu where it opens.
const PINNED_OFFSET_M: Vector2 = Vector2(-0.3, 0.24)
const PINNED_PIXEL_SIZE: float = 0.0005
const PINNED_WIDTH_PX: float = 700.0
const FONT: int = 56
const TEXT_COLOR: Color = DevMenu.TEXT_COLOR
const PINNED_COLOR: Color = DevMenu.SELECTED_COLOR

var label: Label3D = null
## Whether the page shows as one pinned line rather than the whole step.
var pinned: bool = false


func _init() -> void:
	name = NODE_NAME
	label = Label3D.new()
	label.name = LABEL_NAME
	label.font_size = FONT
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = DevMenu.RENDER_PRIORITY
	label.layers = DevMenu.LAYERS  # Drawn at the home base too (#1450).
	add_child(label)
	visible = false


## Shows the whole step, `lines` top to bottom, in front of `head` (a pose in
## the parent's space).
func show_full(lines: Array[String], head: Transform3D) -> void:
	pinned = false
	transform = DevMenu.placement(head, FULL_DISTANCE_M, Vector2.ZERO)
	label.pixel_size = FULL_PIXEL_SIZE
	label.width = FULL_WIDTH_PX
	label.modulate = TEXT_COLOR
	_set_text("\n".join(lines))
	visible = true


## Redraws the open page's `lines` where it is.
func refresh(lines: Array[String]) -> void:
	_set_text("\n".join(lines))


## Shows only `line`, small, up and to the left of `head`'s view.
func show_pinned(line: String, head: Transform3D) -> void:
	pinned = true
	transform = DevMenu.placement(head, PINNED_DISTANCE_M, PINNED_OFFSET_M)
	label.pixel_size = PINNED_PIXEL_SIZE
	label.width = PINNED_WIDTH_PX
	label.modulate = PINNED_COLOR
	_set_text(line)
	visible = true


func hide_page() -> void:
	pinned = false
	visible = false


func text() -> String:
	return label.text


func _set_text(words: String) -> void:
	if label.text != words:
		label.text = words  # Label3D rebuilds its glyphs on every assignment.
