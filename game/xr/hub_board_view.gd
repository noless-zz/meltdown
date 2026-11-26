class_name HubBoardView
extends Node3D

## The Crew Quarters' and Logbook's boards on their station screens (#1368,
## CRW-1, CRW-2): crew cards (role icon, name, and what the role gives as an
## attribute icon and a number), attribute bars (a fill for the current value,
## a tick at stock, the number beside them) and Logbook figures with a short
## caption and, for a part of a whole, a small bar. The selected item gets a
## frame in the selected colour, so the choice is a shape, not only a colour.
##
## It draws the hub text's `drawing()` data and nothing else: it reads no
## profile, writes no simulation state (MP-2) and reads no comfort setting
## (ARC-3). Words use the screen's row size, so they read as the rows do.
## Hung on the station's `HubStationScreen`, so it comes forward with the words.

const NODE_NAME: String = "BoardView"
## The item types the drawing names (the hub text's; `xr/` names no meta class).
const CARD: String = "card"
const BAR: String = "bar"
const TILE: String = "tile"
## In front of the face like the words: backs, then bars and frames, then icons and words.
const BACK_Z_M: float = 0.0008
const BAR_Z_M: float = 0.0014
const ICON_Z_M: float = 0.0025
const TEXT_Z_M: float = 0.004
## Gap between parts of a strip, and the frame's width, in metres.
const GAP_M: float = 0.004
const FRAME_M: float = 0.0015
## A strip's back fills this much of its height, leaving a gap to the next.
const BACK_FILL: float = 0.88
## The stock tick stands this much taller than the bar.
const TICK_HEIGHT: float = 1.8
## A tile's bar spans this much of the tile's width, right of its figure.
const TILE_BAR: float = 0.5
## A tile's figure and caption sit this many lines above and below its middle.
const TILE_LINE: float = 0.45

## Item id to the node drawn for it.
var items: Dictionary[String, Node3D] = {}
## The item framed as selected, or "".
var selected_item: String = ""
## Bar item id to its drawn fill and stock mark, as fractions of its length.
var fills: Dictionary[String, float] = {}
var marks: Dictionary[String, float] = {}

var _icons: HubIcons
var _screen: Dictionary
var _layers: int
static var _box: BoxMesh
static var _flat: Dictionary[Color, StandardMaterial3D] = {}


func _init(icons: HubIcons, screen: Dictionary, layers: int = 1) -> void:
	name = NODE_NAME
	_icons = icons
	_screen = screen
	_layers = layers


## Draws `drawing` (the hub text's `drawing()`) on a face of `face` metres.
## The station's row lines are not needed: the board sits under them.
func show_drawing(drawing: Dictionary, _shown: Array[Dictionary], _first: int, face: Vector2) -> void:
	visible = true
	_clear()
	var width: float = face.x - HubStationScreen.MARGIN_M * 2.0
	for item: Dictionary in drawing["items"]:
		var spot: Node3D = Node3D.new()
		spot.name = "Item_%s" % str(item["id"]).replace(":", "_")
		var at: Vector2 = item["at"]
		match str(item["type"]):
			CARD:
				_card(spot, item, drawing, width)
			BAR:
				_bar(spot, item, drawing, width)
			TILE:
				var tile: float = width / float(item["columns"])
				at.x = -width * 0.5 + tile * (float(item["column"]) + 0.5)
				_tile(spot, item, drawing, tile)
		spot.position = Vector3(at.x, at.y, 0.0)
		add_child(spot)
		items[str(item["id"])] = spot
		if item["selected"]:
			selected_item = str(item["id"])


## Pointing picks nothing on a board; the stick chooses.
func can_point() -> bool:
	return false


func point_on(_origin: Vector3, _direction: Vector3, _ancestor: Node) -> Variant:
	return null


## The texts drawn for item `id`, left to right, top down.
func item_texts(id: String) -> Array[String]:
	var out: Array[String] = []
	if items.has(id):
		for label: Node in items[id].find_children("*", "Label3D", true, false):
			out.append((label as Label3D).text)
	return out


func _card(spot: Node3D, item: Dictionary, drawing: Dictionary, width: float) -> void:
	var height: float = float(drawing["strip_height_m"])
	var icon: float = drawing["icon_size_m"]
	_back(spot, Vector2(width, height * BACK_FILL), item["selected"])
	var left: float = -width * 0.5 + GAP_M
	_put_icon(spot, item["icon"], icon, Vector2(left + icon * 0.5, 0.0))
	_text(spot, item["name"], Vector2(left + icon + GAP_M, 0.0), HORIZONTAL_ALIGNMENT_LEFT, item["selected"])
	var right: float = width * 0.5 - GAP_M
	var figure: Label3D = _text(spot, item["figure"], Vector2(right, 0.0), HORIZONTAL_ALIGNMENT_RIGHT, item["selected"])
	var figure_w: float = _width(figure)
	_put_icon(spot, item["figure_icon"], icon * 0.85, Vector2(right - figure_w - GAP_M - icon * 0.425, 0.0))


func _bar(spot: Node3D, item: Dictionary, drawing: Dictionary, width: float) -> void:
	var height: float = float(drawing["strip_height_m"])
	var icon: float = drawing["icon_size_m"]
	var length: float = drawing["bar_length_m"]
	var thick: float = drawing["bar_height_m"]
	_back(spot, Vector2(width, height * BACK_FILL), item["selected"])
	var left: float = -width * 0.5 + GAP_M
	_put_icon(spot, item["icon"], icon, Vector2(left + icon * 0.5, 0.0))
	var start: float = left + icon + GAP_M
	_draw_bar(spot, start, 0.0, length, thick, float(item["fill"]), float(item["mark"]))
	_text(spot, item["figure"], Vector2(start + length + GAP_M, 0.0), HORIZONTAL_ALIGNMENT_LEFT, item["selected"])
	fills[str(item["id"])] = float(item["fill"])
	marks[str(item["id"])] = float(item["mark"])


func _tile(spot: Node3D, item: Dictionary, drawing: Dictionary, tile: float) -> void:
	var height: float = float(drawing["tile_height_m"])
	_back(spot, Vector2(tile - GAP_M, height * BACK_FILL), item["selected"])
	var line: float = _line_m() * TILE_LINE
	var barred: bool = float(item["fill"]) >= 0.0
	# A part of a whole has its bar beside its figure, so the tile keeps two lines.
	_text(spot, item["figure"], Vector2(-tile * TILE_BAR * 0.5 if barred else 0.0, line), HORIZONTAL_ALIGNMENT_CENTER,
		item["selected"])
	_text(spot, item["caption"], Vector2(0.0, -line), HORIZONTAL_ALIGNMENT_CENTER, false)
	if barred:
		var length: float = tile * TILE_BAR
		_draw_bar(spot, tile * (0.5 - TILE_BAR) + GAP_M, line, length - GAP_M * 2.0,
			float(drawing["bar_height_m"]), float(item["fill"]), -1.0)
		fills[str(item["id"])] = float(item["fill"])


## A track from `start` of `length`, filled to `fill`, with a tick at `mark` (none below 0).
func _draw_bar(spot: Node3D, start: float, y: float, length: float, thick: float, fill: float, mark: float) -> void:
	spot.add_child(_flat_box(Vector3(start + length * 0.5, y, BAR_Z_M), Vector3(length, thick, HubIcon.THICK_M),
		(_screen["text_color"] as Color).darkened(0.7), "Track"))
	if fill > 0.0:
		spot.add_child(_flat_box(Vector3(start + length * fill * 0.5, y, BAR_Z_M + 0.0002),
			Vector3(length * fill, thick, HubIcon.THICK_M), _screen["text_color"], "Fill"))
	if mark >= 0.0:
		spot.add_child(_flat_box(Vector3(start + length * mark, y, BAR_Z_M + 0.0004),
			Vector3(FRAME_M, thick * TICK_HEIGHT, HubIcon.THICK_M), _screen["frame_color"], "Stock"))


## The item's back, a shade lighter than the face, framed when selected.
func _back(spot: Node3D, size: Vector2, selected: bool) -> void:
	spot.add_child(_flat_box(Vector3(0.0, 0.0, BACK_Z_M), Vector3(size.x, size.y, HubIcon.THICK_M),
		(_screen["screen_color"] as Color).lightened(0.08), "Back"))
	if not selected:
		return
	var frame: Node3D = Node3D.new()
	frame.name = "Selected"
	var half: Vector2 = size * 0.5
	for side: Array in [[Vector2(0.0, half.y), Vector2(size.x, FRAME_M)], [Vector2(0.0, -half.y), Vector2(size.x, FRAME_M)],
			[Vector2(half.x, 0.0), Vector2(FRAME_M, size.y)], [Vector2(-half.x, 0.0), Vector2(FRAME_M, size.y)]]:
		var at: Vector2 = side[0]
		var long: Vector2 = side[1]
		frame.add_child(_flat_box(Vector3(at.x, at.y, BAR_Z_M), Vector3(long.x, long.y, HubIcon.THICK_M),
			_screen["selected_color"], "Bar"))
	spot.add_child(frame)


func _put_icon(spot: Node3D, icon: Dictionary, size: float, at: Vector2) -> void:
	var drawn: HubIcon = HubIcon.new(_icons.fallback if icon.is_empty() else _icons.icon(str(icon["group"]), str(icon["id"])),
		size, _layers)
	drawn.position = Vector3(at.x, at.y, ICON_Z_M)
	spot.add_child(drawn)


func _text(spot: Node3D, text: String, at: Vector2, align: HorizontalAlignment, selected: bool) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Text%d" % spot.get_child_count()
	label.pixel_size = float(_screen["pixel_size"])
	label.font_size = int(_screen["row_font_size"])
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = align
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.layers = _layers
	label.modulate = _screen["selected_color"] if selected else _screen["text_color"]
	label.text = text
	# An edge-aligned Label3D hangs its text from that edge at its position.
	label.position = Vector3(at.x, at.y, TEXT_Z_M)
	spot.add_child(label)
	return label


## A label's width in metres.
func _width(label: Label3D) -> float:
	return ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x \
		* label.pixel_size


func _line_m() -> float:
	return ThemeDB.fallback_font.get_height(int(_screen["row_font_size"])) * float(_screen["pixel_size"])


func _flat_box(at: Vector3, size: Vector3, color: Color, part_name: String) -> MeshInstance3D:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	if not _flat.has(color):
		var made: StandardMaterial3D = StandardMaterial3D.new()
		made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		made.albedo_color = color
		_flat[color] = made
	var box: MeshInstance3D = MeshInstance3D.new()
	box.name = part_name
	box.mesh = _box
	box.material_override = _flat[color]
	box.layers = _layers
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.position = at
	box.scale = size
	return box


func _clear() -> void:
	for node: Node in get_children():
		remove_child(node)
		node.free()
	items.clear()
	fills.clear()
	marks.clear()
	selected_item = ""
