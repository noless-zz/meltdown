class_name HubIconSheet
extends Node3D

## The whole icon set on one screen (#1365, CRW-2, GFX-2): one row per group in
## `HubIcons.GROUPS` order, each group's icons in id order, so a screenshot
## shows every icon beside the others of its group and a missing or clashing
## one is seen. Shrunk as a whole to fit `width_m` by `height_m`; the icons keep
## their own proportions. Used by the `hub_icons` acceptance step.

const NODE_NAME: String = "IconSheet"
## Space between icons and between rows, as a share of the icon size.
const STEP: float = 1.35

var _icons: Array[HubIcon] = []


func _init(icons: HubIcons, width_m: float, height_m: float, layers: int = 1) -> void:
	name = NODE_NAME
	var size: float = icons.numbers["size_m"]
	var step: float = size * STEP
	var widest: int = 1
	for group: String in HubIcons.GROUPS:
		widest = maxi(widest, icons.ids(group).size())
	var rows: int = HubIcons.GROUPS.size()
	var fit: float = minf(1.0, minf(width_m / (step * widest), height_m / (step * rows)))
	scale = Vector3(fit, fit, 1.0)
	for row: int in rows:
		var group: String = HubIcons.GROUPS[row]
		var ids: Array[String] = icons.ids(group)
		for column: int in ids.size():
			var drawn: HubIcon = HubIcon.new(icons.icon(group, ids[column]), size, layers)
			drawn.name = "%s_%s" % [group, ids[column]]
			drawn.position = Vector3(step * (column - (widest - 1) * 0.5), step * ((rows - 1) * 0.5 - row), 0.0)
			add_child(drawn)
			_icons.append(drawn)


func icon_count() -> int:
	return _icons.size()


## Width and height the sheet covers once shrunk, in metres.
func covered_m(icons: HubIcons) -> Vector2:
	var step: float = icons.numbers["size_m"] * STEP
	var widest: int = 1
	for group: String in HubIcons.GROUPS:
		widest = maxi(widest, icons.ids(group).size())
	return Vector2(step * widest, step * HubIcons.GROUPS.size()) * scale.x
