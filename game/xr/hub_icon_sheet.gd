class_name HubIconSheet
extends Node3D

## The whole icon set on one screen (#1365, CRW-2, GFX-2): one row per group in
## `HubIcons.GROUPS` order, each group's icons in id order, so a screenshot
## shows every icon beside the others of its group and a missing or clashing
## one is seen. A group of more than `MAX_COLUMNS` icons (the menu's, #1458)
## goes on over the next rows, so one long group does not shrink the rest.
## Shrunk as a whole to fit `width_m` by `height_m`; the icons keep their own
## proportions. Used by the `hub_icons` acceptance step.

const NODE_NAME: String = "IconSheet"
## Space between icons and between rows, as a share of the icon size.
const STEP: float = 1.35
const MAX_COLUMNS: int = 8

var _icons: Array[HubIcon] = []


func _init(icons: HubIcons, width_m: float, height_m: float, layers: int = 1) -> void:
	name = NODE_NAME
	var size: float = icons.numbers["size_m"]
	var step: float = size * STEP
	var grid: Vector2i = grid_of(icons)
	var fit: float = minf(1.0, minf(width_m / (step * grid.x), height_m / (step * grid.y)))
	scale = Vector3(fit, fit, 1.0)
	var row: int = 0
	for group: String in HubIcons.GROUPS:
		var ids: Array[String] = icons.ids(group)
		for index: int in ids.size():
			var column: int = index % MAX_COLUMNS
			var drawn: HubIcon = HubIcon.new(icons.icon(group, ids[index]), size, layers)
			drawn.name = "%s_%s" % [group, ids[index]]
			drawn.position = Vector3(step * (column - (grid.x - 1) * 0.5),
				step * ((grid.y - 1) * 0.5 - (row + floori(index / float(MAX_COLUMNS)))), 0.0)
			add_child(drawn)
			_icons.append(drawn)
		row += _rows_of(ids.size())


func icon_count() -> int:
	return _icons.size()


## Columns and rows the sheet lays the set out in.
static func grid_of(icons: HubIcons) -> Vector2i:
	var widest: int = 1
	var rows: int = 0
	for group: String in HubIcons.GROUPS:
		var count: int = icons.ids(group).size()
		widest = maxi(widest, mini(count, MAX_COLUMNS))
		rows += _rows_of(count)
	return Vector2i(widest, maxi(rows, 1))


## Width and height the sheet covers once shrunk, in metres.
func covered_m(icons: HubIcons) -> Vector2:
	var step: float = icons.numbers["size_m"] * STEP
	var grid: Vector2i = grid_of(icons)
	return Vector2(step * grid.x, step * grid.y) * scale.x


static func _rows_of(count: int) -> int:
	return maxi(1, ceili(float(count) / MAX_COLUMNS))
