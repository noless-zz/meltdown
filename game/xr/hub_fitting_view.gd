class_name HubFittingView
extends Node3D

## The Fitting Bay's drawing on its station screen (#1366, CRF-4, CRW-2): the
## ship from above as a flat shape with each slot on it, showing the icon of
## what it holds (#1365) or an empty ring, and the slot the stick or the aim is
## on ringed again in the frame's colour, so the choice is a shape and not
## only a colour. While the pilot chooses what goes in a slot, the ship gives
## way to the list and each item row gets its icon at the face's left edge.
##
## It draws `HubText.drawing()`'s data and nothing else: it reads no profile,
## writes no simulation state (MP-2) and reads no comfort setting (ARC-3).
## Hung on the station's `HubStationScreen`, so it comes forward and grows
## with the words.
##
## The summary's and a mount's bars (#1385) are drawn by a `HubBoardView`
## held here, since a station's view is made once: on a summary row it takes
## the ship's place; under a chosen slot's item rows it sits below the words.

const NODE_NAME: String = "FittingView"
const SHIP_NAME: String = "Ship"
## In front of the face like the words, the icons a hair further.
const HULL_Z_M: float = 0.0015
const ICON_Z_M: float = 0.0025
## The selection ring's size against a slot's, and the empty ring's.
const SELECTED_RING: float = 1.45
const EMPTY_RING: float = 0.8

## Where the outline and slots are drawn; pointing is measured in its space.
var ship: Node3D
## Slot name to the node drawn for it.
var slot_nodes: Dictionary[String, Node3D] = {}
## The slot ringed as selected, or "".
var selected_slot: String = ""
## Icons drawn beside item rows.
var row_icons: Array[HubIcon] = []
## The bars, hidden while the drawing has none.
var board: HubBoardView

var _icons: HubIcons
var _screen: Dictionary
var _layers: int


func _init(icons: HubIcons, screen: Dictionary, layers: int = 1) -> void:
	name = NODE_NAME
	_icons = icons
	_screen = screen
	_layers = layers
	ship = Node3D.new()
	ship.name = SHIP_NAME
	add_child(ship)
	board = HubBoardView.new(icons, screen, layers)
	board.visible = false
	add_child(board)


## Draws `drawing` (`HubFitBay.drawing`) on a face of `face` metres, with
## `shown` the screen's row lines (`HubStationScreen.shown_rows`) of a window
## starting at row `first`.
func show_drawing(drawing: Dictionary, shown: Array[Dictionary], first: int, face: Vector2) -> void:
	visible = true
	_clear()
	var bars: Dictionary = drawing.get("board", {})
	board.visible = not bars.is_empty()
	if board.visible:
		board.show_drawing(bars, shown, first, face)
	ship.visible = not drawing["choosing"] and not board.visible
	if drawing["choosing"]:
		var size: float = _icons.numbers["size_m"]
		var icons: Array = drawing["row_icons"]
		for line: Dictionary in shown:
			var index: int = first + int(line["row"])
			if index < icons.size() and not (icons[index] as Dictionary).is_empty():
				var drawn: HubIcon = _icon(icons[index], size)
				drawn.position = Vector3(-face.x * 0.5 + HubStationScreen.MARGIN_M + size * 0.5, line["y"], ICON_Z_M)
				add_child(drawn)
				row_icons.append(drawn)
		return
	if board.visible:
		return
	ship.position = Vector3(0.0, drawing["center_y_m"], 0.0)
	ship.add_child(_hull(drawing["outline"], drawing["hull_color"]))
	var slot_size: float = drawing["slot_size_m"]
	for slot: Dictionary in drawing["slots"]:
		var spot: Node3D = Node3D.new()
		spot.name = "Slot_%s" % str(slot["slot"]).replace("[", "_").replace("]", "")
		spot.position = Vector3((slot["at"] as Vector2).x, (slot["at"] as Vector2).y, ICON_Z_M)
		var icon: Dictionary = slot["icon"]
		if icon.is_empty():
			spot.add_child(HubIcon.new(_ring(_screen["text_color"], EMPTY_RING), slot_size, _layers))
		else:
			spot.add_child(_icon(icon, slot_size))
		if slot["selected"]:
			var ring: HubIcon = HubIcon.new(_ring(_screen["frame_color"], SELECTED_RING), slot_size, _layers)
			ring.name = "Selected"
			ring.position = Vector3(0.0, 0.0, -ICON_Z_M * 0.5)
			spot.add_child(ring)
			selected_slot = slot["slot"]
		ship.add_child(spot)
		slot_nodes[slot["slot"]] = spot


## Whether the aim can pick a slot here now (the ship is shown).
func can_point() -> bool:
	return visible and ship.visible


## `point_on_ship`, under the name every station drawing shares (#1367).
func point_on(origin: Vector3, direction: Vector3, ancestor: Node) -> Variant:
	return point_on_ship(origin, direction, ancestor)


## Where a ray from `origin` along `direction` (both in the space of
## `ancestor`, which holds this view) meets the ship's plane, in the ship's
## metres, or null when it runs along or away from it.
func point_on_ship(origin: Vector3, direction: Vector3, ancestor: Node) -> Variant:
	var to_ship: Transform3D = HubScreenMeasure.in_space_of(ship, ancestor).affine_inverse()
	var from: Vector3 = to_ship * origin
	var along: Vector3 = to_ship.basis * direction
	if absf(along.z) < 0.000001:
		return null
	var distance: float = -from.z / along.z
	if distance <= 0.0:
		return null
	var hit: Vector3 = from + along * distance
	return Vector2(hit.x, hit.y)


func _clear() -> void:
	var drawn: Array[Node] = ship.get_children()
	drawn.append_array(row_icons)
	for node: Node in drawn:
		node.get_parent().remove_child(node)
		node.free()
	slot_nodes.clear()
	row_icons.clear()
	selected_slot = ""


func _icon(icon: Dictionary, size: float) -> HubIcon:
	return HubIcon.new(_icons.icon(str(icon["group"]), str(icon["id"])), size, _layers)


## An icon description of a single ring, in `HubIconParts`' parsed form.
static func _ring(color: Color, across: float) -> Dictionary:
	return {"color": color, "parts": [{"shape": "ring", "size": Vector2(across, across), "at": Vector2.ZERO,
		"turn_deg": 0.0, "color": color}]}


## The outline as a flat, unshaded shape.
func _hull(outline: Array, color: Color) -> MeshInstance3D:
	var points: PackedVector2Array = PackedVector2Array(outline)
	var vertices: PackedVector3Array = PackedVector3Array()
	for index: int in Geometry2D.triangulate_polygon(points):
		vertices.append(Vector3(points[index].x, points[index].y, HULL_Z_M))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.cull_mode = BaseMaterial3D.CULL_DISABLED  # The outline's winding is the file's.
	made.albedo_color = color
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = mesh
	hull.material_override = made
	hull.layers = _layers
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return hull
