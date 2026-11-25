class_name HubIconCount
extends Node3D

## An icon with a number beside it (#1365, CRW-2, CRF-1, CRF-3), for the
## stations to place on their screens: "7" for what is held, or "3/5" for
## have and need, coloured as short while have is under need, so a cost reads
## as pictures with counts instead of a line of words (#1359). The icon sits
## centred on the node and the number starts `count_gap_m` to its right, at the
## set's count size, in front of the screen's face like its words.

const NODE_NAME: String = "IconCount"
## A hair in front of the icon's parts, as the screen's words are.
const COUNT_Z_M: float = 0.004

var icon: HubIcon
var _count: Label3D
var _icons: HubIcons


func _init(icons: HubIcons, group: String, id: String, layers: int = 1) -> void:
	name = NODE_NAME
	_icons = icons
	icon = HubIcon.new(icons.icon(group, id), icons.numbers["size_m"], layers)
	add_child(icon)
	_count = Label3D.new()
	_count.name = "Count"
	_count.pixel_size = icons.numbers["pixel_size"]
	_count.font_size = int(icons.numbers["count_font_size"])
	_count.outline_size = 0
	_count.shaded = false
	_count.double_sided = false
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_count.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_count.layers = layers
	_count.position = Vector3(icons.numbers["size_m"] * 0.5 + icons.numbers["count_gap_m"], 0.0, COUNT_Z_M)
	_count.visible = false
	add_child(_count)


## Shows `have`, or `have`/`need` when `need` is 0 or more.
func show_count(have: int, need: int = -1) -> void:
	var text: String = str(have) if need < 0 else "%d/%d" % [have, need]
	if _count.text != text:
		_count.text = text  # Label3D rebuilds its glyphs on every assignment.
	_count.modulate = _icons.colors["short_color"] if need >= 0 and have < need else _icons.colors["count_color"]
	_count.visible = true


## Only the icon, no number.
func hide_count() -> void:
	_count.visible = false


func count_text() -> String:
	return _count.text if _count.visible else ""


func count_color() -> Color:
	return _count.modulate
