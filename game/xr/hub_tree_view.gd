class_name HubTreeView
extends Node3D

## The Workbench's tech tree on its station screen (#1367, CRF-3, CRF-6,
## CRW-2, CMF-8): each upgrade its icon (#1365), a thin line for each "needs",
## and the three states told apart by shape, not colour alone: a built node
## sits in a square frame, one that can be built now in a round one, and a
## locked one is drawn smaller with no frame. The selected node gets a wider
## ring in the selected colour and its edges are lit. The rows under it (cost,
## effect, unlocks) get their icons at the face's left edge.
##
## It draws the hub text's `drawing()` data and nothing else: it reads no profile,
## writes no simulation state (MP-2) and reads no comfort setting (ARC-3). The
## tree pans inside the screen when it is wider than the window; the pilot's
## view never moves (CMF-8). Hung on the station's `HubStationScreen`, so it
## comes forward and grows with the words.
##
## A drawing that shows a node built that the last drawing showed buildable
## plays the crafting moment over it (`HubCraftMoment`, #1402): the cost rows'
## component icons fly in, the node fills, and the nodes it unlocked glow up.
##
## The Workbench's Parts Locker face (#1413) is drawn here too, as a drawing
## with no nodes and a `board` of component tiles for its `HubBoardView`.

const NODE_NAME: String = "TreeView"
## The node states the drawing names (the hub text's; `xr/` names no meta class).
const BUILT: String = "built"
const READY: String = "ready"
const LOCKED: String = "locked"
## In front of the face like the words: edges, then frames, then icons.
const EDGE_Z_M: float = 0.0012
const FRAME_Z_M: float = 0.0018
const ICON_Z_M: float = 0.0025
## Sizes against a node's: a locked icon, the square frame's side and bar,
## the round frame, the selection ring.
const LOCKED_SCALE: float = 0.68
const SQUARE: float = 1.3
const SQUARE_BAR: float = 0.12
const ROUND: float = 1.35
const SELECTED_RING: float = 1.75

## Node id to the node drawn for it.
var nodes: Dictionary[String, Node3D] = {}
## Node id to its state as drawn ("built", "ready", "locked").
var states: Dictionary[String, String] = {}
## The node ringed as selected, or "".
var selected_node: String = ""
## Edges drawn, and how many of them are lit.
var edge_count: int = 0
var lit_edges: int = 0
## Icons drawn beside detail rows.
var row_icons: Array[HubIcon] = []
## The crafting moment over the tree (#1402).
var moment: HubCraftMoment
## Draws the Parts Locker's component tiles.
var board: HubBoardView
## False draws every change at rest at once, with no moment (for tests).
var moments_enabled: bool = true

var _icons: HubIcons
var _screen: Dictionary
var _layers: int
var _drawn: Node3D
static var _edge_mesh: BoxMesh
static var _flat: Dictionary[Color, StandardMaterial3D] = {}


func _init(icons: HubIcons, screen: Dictionary, layers: int = 1) -> void:
	name = NODE_NAME
	_icons = icons
	_screen = screen
	_layers = layers
	_drawn = Node3D.new()
	_drawn.name = "Tree"
	add_child(_drawn)
	moment = HubCraftMoment.new(screen, LOCKED_SCALE)
	add_child(moment)
	board = HubBoardView.new(icons, screen, layers)
	board.visible = false
	add_child(board)


func _process(delta: float) -> void:
	advance(delta)


## Moves the crafting moment `seconds` on; once hidden it ends at once.
func advance(seconds: float) -> void:
	moment.advance(seconds if visible else INF, nodes)


## Draws `drawing` (the hub text's `drawing()`) on a face of `face` metres, with
## `shown` the screen's row lines (`HubStationScreen.shown_rows`) of a window
## starting at row `first`.
func show_drawing(drawing: Dictionary, shown: Array[Dictionary], first: int, face: Vector2) -> void:
	var before: Dictionary[String, String] = {}
	if visible:  # A view shown again after the hub closed starts afresh.
		before.assign(states)
	var spent: Array[Dictionary] = _component_icons()
	visible = true
	_clear()
	var size: float = drawing.get("node_size_m", 0.0)
	for edge: Dictionary in drawing.get("edges", []):
		_edge(edge["from"], edge["to"], drawing["edge_width_m"], edge["lit"])
	for node: Dictionary in drawing.get("nodes", []):
		_node(node, size)
	var tiles: Dictionary = drawing.get("board", {})
	board.visible = not tiles.is_empty()
	if board.visible:
		board.show_drawing(tiles, shown, first, face)
	var icons: Array = drawing["row_icons"]
	var row_size: float = minf(_icons.numbers["size_m"], float(_screen["row_step_m"]) * 0.8)
	for line: Dictionary in shown:
		var index: int = first + int(line["row"])
		if index < icons.size() and not (icons[index] as Dictionary).is_empty():
			var drawn: HubIcon = _icon(icons[index], row_size)
			drawn.position = Vector3(-face.x * 0.5 + HubStationScreen.MARGIN_M + row_size * 0.5, line["y"], ICON_Z_M)
			drawn.set_meta(&"icon", icons[index])
			add_child(drawn)
			row_icons.append(drawn)
	_start_moment(before, spent, size)
	moment.apply(nodes)


## Starts the moment when a node shown buildable before is built now; the
## nodes that went from locked to buildable with it are the ones it unlocked.
func _start_moment(before: Dictionary[String, String], spent: Array[Dictionary], size: float) -> void:
	var built: String = ""
	var opened: Array[String] = []
	for id: String in states:
		if before.get(id, "") == READY and states[id] == BUILT:
			built = id
		elif before.get(id, "") == LOCKED and states[id] == READY:
			opened.append(id)
	if built == "" or not moments_enabled:
		return
	var flying: Array[Dictionary] = []
	for each: Dictionary in spent:
		flying.append({"icon": _icon(each["icon"], each["size"]), "at": each["at"]})
	moment.start(built, opened, flying, size, _layers)


## The component icons beside the rows shown now, where they are: what a
## craft from here spends.
func _component_icons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for drawn: HubIcon in row_icons:
		var icon: Dictionary = drawn.get_meta(&"icon", {})
		if str(icon.get("group", "")) == "component":
			out.append({"icon": icon, "at": drawn.position, "size": drawn.size_m})
	return out


## Whether the aim can pick a node here now.
func can_point() -> bool:
	return visible and not nodes.is_empty()


## Where a ray from `origin` along `direction` (both in the space of
## `ancestor`, which holds this view) meets the face's plane, in the face's
## metres, or null when it runs along or away from it.
func point_on(origin: Vector3, direction: Vector3, ancestor: Node) -> Variant:
	var to_face: Transform3D = HubScreenMeasure.in_space_of(_drawn, ancestor).affine_inverse()
	var from: Vector3 = to_face * origin
	var along: Vector3 = to_face.basis * direction
	if absf(along.z) < 0.000001:
		return null
	var distance: float = -from.z / along.z
	if distance <= 0.0:
		return null
	var hit: Vector3 = from + along * distance
	return Vector2(hit.x, hit.y)


func _node(node: Dictionary, size: float) -> void:
	var spot: Node3D = Node3D.new()
	var id: String = node["id"]
	spot.name = "Node_%s" % id
	spot.position = Vector3((node["at"] as Vector2).x, (node["at"] as Vector2).y, 0.0)
	var drawn_state: String = node["state"]
	match drawn_state:
		BUILT:
			spot.add_child(_square(size * SQUARE, _screen["text_color"]))
		READY:
			var ring: HubIcon = HubIcon.new(_ring(_screen["frame_color"], 1.0), size * ROUND, _layers)
			ring.name = "Frame"
			ring.position.z = FRAME_Z_M
			spot.add_child(ring)
	var icon: HubIcon = _icon(node["icon"], size * (LOCKED_SCALE if drawn_state == LOCKED else 1.0))
	icon.position.z = ICON_Z_M
	spot.add_child(icon)
	if node["selected"]:
		var chosen: HubIcon = HubIcon.new(_ring(_screen["selected_color"], 1.0), size * SELECTED_RING, _layers)
		chosen.name = "Selected"
		chosen.position.z = FRAME_Z_M * 0.5
		spot.add_child(chosen)
		selected_node = id
	_drawn.add_child(spot)
	nodes[id] = spot
	states[id] = drawn_state


## A square frame `side` across: four bars, so it reads as a shape.
func _square(side: float, color: Color) -> Node3D:
	var frame: Node3D = Node3D.new()
	frame.name = "Frame"
	var bar: float = side * SQUARE_BAR
	var half: float = (side - bar) * 0.5
	for at: Vector2 in [Vector2(0.0, half), Vector2(0.0, -half), Vector2(half, 0.0), Vector2(-half, 0.0)]:
		var long: Vector2 = Vector2(side, bar) if at.y != 0.0 else Vector2(bar, side)
		frame.add_child(_flat_box(Vector3(at.x, at.y, FRAME_Z_M), Vector3(long.x, long.y, HubIcon.THICK_M), color))
	return frame


func _edge(from: Vector2, to: Vector2, width: float, lit: bool) -> void:
	var length: float = from.distance_to(to)
	if length < 0.0001:
		return
	var middle: Vector2 = (from + to) * 0.5
	var color: Color = _screen["selected_color"] if lit else (_screen["text_color"] as Color).darkened(0.45)
	var bar: MeshInstance3D = _flat_box(Vector3(middle.x, middle.y, EDGE_Z_M), Vector3(length, width, HubIcon.THICK_M), color)
	bar.rotation.z = (to - from).angle()
	bar.name = "Edge%d" % edge_count
	_drawn.add_child(bar)
	edge_count += 1
	lit_edges += 1 if lit else 0


func _flat_box(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	if _edge_mesh == null:
		_edge_mesh = BoxMesh.new()
		_edge_mesh.size = Vector3.ONE
	if not _flat.has(color):
		var made: StandardMaterial3D = StandardMaterial3D.new()
		made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		made.albedo_color = color
		_flat[color] = made
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = _edge_mesh
	box.material_override = _flat[color]
	box.layers = _layers
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.position = at
	box.scale = size
	return box


func _clear() -> void:
	var drawn: Array[Node] = _drawn.get_children()
	drawn.append_array(row_icons)
	for node: Node in drawn:
		node.get_parent().remove_child(node)
		node.free()
	nodes.clear()
	states.clear()
	row_icons.clear()
	selected_node = ""
	edge_count = 0
	lit_edges = 0


func _icon(icon: Dictionary, size: float) -> HubIcon:
	if icon.is_empty():
		return HubIcon.new(_icons.fallback, size, _layers)
	return HubIcon.new(_icons.icon(str(icon["group"]), str(icon["id"])), size, _layers)


## An icon description of a single ring, in `HubIconParts`' parsed form.
static func _ring(color: Color, across: float) -> Dictionary:
	return {"color": color, "parts": [{"shape": "ring", "size": Vector2(across, across), "at": Vector2.ZERO,
		"turn_deg": 0.0, "color": color}]}
