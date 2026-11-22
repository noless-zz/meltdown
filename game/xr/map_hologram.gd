class_name MapHologram
extends Node3D

## The explored mine as a small hologram held in the hand (MAP-1, #314): the
## `MapWireframe` outline of the explored boxes as one emissive line mesh fitted
## into a cube of `size_m`, and a dart for the ship (`MapShipMarker`). It hangs
## under a controller; a click of `show_map` opens it and the next closes it
## (#914). Sharing the label button, a click toggles the map and a hold the
## labels (#335). It is handed copies and holds no session, so it never writes
## simulation state or comfort settings (ARC-3, CMF-6, MP-2).
##
## Children fitted like the lines mark the exit and reactor (#338, RUN-3), the
## route and blocked openings (`MapRoute`, #400), fires (`MapFires`, #519; only in
## explored boxes unless `fires_explored_only` is off, #562) and trapped miners
## (`MapMinerMarkers`, #1072). `set_zoom` scales it all about the hand (#549). The
## look is `res://xr/map_look.json` (ARC-4), parsed by `MapLook`.

const NODE_NAME: String = "MapHologram"
const LINES_NAME: String = "Lines"
const MARKER_NAME: String = "Marker"
const EXIT_NAME: String = "Exit"
const REACTOR_NAME: String = "Reactor"
const DEFAULT_LOOK_FILE: String = "res://xr/map_look.json"
## Seconds the shared `show_map` button is held for a hold (labels), not a click (map, #914).
const HOLD_SECONDS: float = 0.4
## The map's centre from the controller: above and ahead, clear of the hand, gone when it drops.
const HAND_OFFSET: Vector3 = Vector3(0.0, 0.12, -0.08)
## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = MapLook.FALLBACK

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
## Level space -> hologram space, as `MapWireframe.fit_to_cube` fits the lines.
var _fit: Transform3D = Transform3D.IDENTITY
var _lines: MeshInstance3D = MeshInstance3D.new()
var _marker: MeshInstance3D = MeshInstance3D.new()
var _exit: MeshInstance3D = MeshInstance3D.new()
var _reactor: MeshInstance3D = MeshInstance3D.new()
var _route: MapRoute = MapRoute.new()
var _fires: MapFires = MapFires.new()
var _miners: MapMinerMarkers = MapMinerMarkers.new()
## The route's level-space points and blocked centres, kept so `build` can re-fit them.
var _route_at: PackedVector3Array = PackedVector3Array()
var _blocked_at: PackedVector3Array = PackedVector3Array()
var _fire_at: PackedVector3Array = PackedVector3Array()
var _fire_radii: PackedFloat32Array = PackedFloat32Array()
## The explored boxes of the last `build`, as copies, for `fires_explored_only`.
var _explored_boxes: Array[AABB] = []
var _exit_at: Vector3 = Vector3.ZERO
var _reactor_at: Vector3 = Vector3.ZERO
var _markers_set: bool = false
var _reactor_known: bool = false
var _reactor_destroyed: bool = false
var _ship_at: Vector3 = Vector3.ZERO
var _zoom: float = MapZoom.START
var _toggle: MapToggle = MapToggle.new()


func _init() -> void:
	name = NODE_NAME
	visible = false
	_lines.name = LINES_NAME
	_marker.name = MARKER_NAME
	_exit.name = EXIT_NAME
	_reactor.name = REACTOR_NAME
	for child: MeshInstance3D in [_lines, _marker, _exit, _reactor]:
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(child)
	add_child(_route)
	add_child(_fires)
	add_child(_miners)
	load_look()


## Applies the look file at `path` via `MapLook.load_file`; a missing or rejected
## file leaves the built-in look and sets `look_error`, which it returns. Colours and
## sizes apply on the next `build`; the zoom re-clamps and all re-places now (#561).
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var loaded: Dictionary = MapLook.load_file(path)
	_look = loaded["look"]
	look_error = loaded["error"]
	set_zoom(_zoom)
	return look_error


## The look the next `build` uses.
func look() -> Dictionary:
	return _look


## Redraws the map from the boxes of `union` listed in `explored`.
func build(union: BoxUnion, explored: Array[int]) -> void:
	var points: PackedVector3Array = MapWireframe.segments(union, explored)
	_explored_boxes.clear()
	for index: int in explored:
		if index >= 0 and index < union.boxes.size():
			var box: BoxBounds = union.boxes[index]
			_explored_boxes.append(AABB(box.min_corner, box.max_corner - box.min_corner))
	var size: float = float(_look["size_m"])
	_fit = fit_transform(points, size)
	_lines.mesh = null
	if not points.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = MapWireframe.fit_to_cube(points, size)
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		mesh.surface_set_material(0, MapShapes.glow(_look["line_color"], float(_look["line_energy"])))
		_lines.mesh = mesh
	var energy: float = float(_look["line_energy"])
	_marker.mesh = MapShipMarker.mesh(_look["marker_color"], float(_look["marker_radius_m"]), energy)
	_exit.mesh = MapShapes.exit_cube(_look)
	_reactor.mesh = MapShapes.reactor_ball(_look, _reactor_destroyed, energy)
	_place_markers()
	_place_route()


## Number of line segments drawn by the last `build`.
func segment_count() -> int:
	var mesh: ArrayMesh = _lines.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / 2


## Moves the marker to the ship's level-space `position` (a copy), fitted like the lines.
func set_ship_position(position: Vector3) -> void:
	_ship_at = position
	_marker.position = _view() * position


## The marker's position in the hologram.
func marker_position() -> Vector3:
	return _marker.position


## Turns the marker to the ship's `orientation` (a copy); the fit only scales, so it carries over.
func set_ship_orientation(orientation: Basis) -> void:
	_marker.basis = orientation.orthonormalized()


## Marks the exit (the entrance, RUN-3) and the reactor at level-space copies of
## their positions, fitted like the lines; the reactor shows only while `reactor_known`,
## in the look's dead colour once `reactor_destroyed` (#913).
func set_markers(exit_at: Vector3, reactor_at: Vector3, reactor_known: bool, reactor_destroyed: bool = false) -> void:
	_exit_at = exit_at
	_reactor_at = reactor_at
	_reactor_known = reactor_known
	if reactor_destroyed != _reactor_destroyed:
		_reactor_destroyed = reactor_destroyed
		_reactor.mesh = MapShapes.reactor_ball(_look, _reactor_destroyed, float(_look["line_energy"]))
	_markers_set = true
	_place_markers()


## The exit and reactor markers' nodes, for reading their meshes and materials.
func marker_nodes() -> Array[MeshInstance3D]:
	return [_exit, _reactor]


## The exit marker's position in the hologram.
func exit_marker_position() -> Vector3:
	return _exit.position


## The reactor marker's position in the hologram.
func reactor_marker_position() -> Vector3:
	return _reactor.position


## Draws the suggested route through `points_m` and a cross at each of `blocked_m`
## (level-space copies, as `KnownRoute` gives them), fitted like the lines.
func show_route(points_m: PackedVector3Array, blocked_m: PackedVector3Array) -> void:
	_route_at = points_m.duplicate()
	_blocked_at = blocked_m.duplicate()
	_place_route()


## Removes the route and the blocked markers.
func clear_route() -> void:
	show_route(PackedVector3Array(), PackedVector3Array())


## The route's node, for reading what it drew.
func route() -> MapRoute:
	return _route


## Marks each burning fire entry at `centres_m` with radius `radii_m` (level-
## space copies), fitted like the lines; see `MapFires`. Empty arrays remove them.
func show_fires(centres_m: PackedVector3Array, radii_m: PackedFloat32Array) -> void:
	_fire_at = centres_m.duplicate()
	_fire_radii = radii_m.duplicate()
	_place_route()


## The node drawing the fire markers, for reading what it drew.
func fires() -> MapFires:
	return _fires


## Pins a trapped miner at each of `at_m` (level-space copies); none when empty (#1072).
func show_miners(at_m: PackedVector3Array) -> void:
	_miners.at_m = at_m.duplicate()
	_place_route()


## Whether the exit marker is drawn: once `set_markers` was called.
func exit_marker_shown() -> bool:
	return _exit.visible


## Whether the reactor marker is drawn: once `set_markers` said it is known.
func reactor_marker_shown() -> bool:
	return _reactor.visible


## Closes the map; the wiring calls it on a restart, a level switch and a
## destroyed ship, so the map never greets a new level open (#914).
func close() -> void:
	visible = false


## One frame of `show_map` down or up, when no label toggle shares it; see `MapToggle.press`.
func press(pressed: bool) -> void:
	visible = _toggle.press(pressed, visible)


## Opens or closes the map from `show_map` in `buttons`; see `MapToggle.read`.
func read(mapping: ThumbstickMapping, buttons: Dictionary, shared: ClickHold = null) -> void:
	visible = _toggle.read(mapping, buttons, shared, visible)


## The hand that clicks `show_map`, which holds the map: left unless left-handed mode or a remap.
static func hand_for(mapping: ThumbstickMapping) -> String:
	for control: String in mapping.physical_controls("show_map"):
		if control.begins_with("right_"):
			return "right"
	return "left"


## Hangs this map under the `LeftHand` or `RightHand` node of `rig`, as
## `hand_for` picks, at `HAND_OFFSET`. Returns false when the rig has no such hand.
func attach_to(rig: Node, mapping: ThumbstickMapping) -> bool:
	var node_name: String = "RightHand" if hand_for(mapping) == "right" else "LeftHand"
	var hand: Node3D = rig.get_node_or_null(node_name) as Node3D
	if hand == null:
		return false
	if get_parent() != null:
		get_parent().remove_child(self)
	hand.add_child(self)
	position = HAND_OFFSET
	return true


## Scales the map by `factor`, clamped to the look's limits, about the hand anchor
## (its origin), so the held point stays put. Marker sizes keep their floors; `build` keeps it.
func set_zoom(factor: float) -> void:
	_zoom = clampf(factor, float(_look["min_zoom"]), float(_look["max_zoom"]))
	_lines.scale = Vector3.ONE * _zoom
	_marker.position = _view() * _ship_at
	_place_markers()
	_place_route()


func zoom() -> float:
	return _zoom


## Level space -> hologram space; see `MapShapes.fit_transform`.
static func fit_transform(points: PackedVector3Array, edge_m: float) -> Transform3D:
	return MapShapes.fit_transform(points, edge_m)


func _place_markers() -> void:
	_exit.visible = _markers_set
	_reactor.visible = _markers_set and _reactor_known
	_exit.position = _view() * _exit_at
	_reactor.position = _view() * _reactor_at


func _place_route() -> void:
	_route.draw_fitted(_view(), _route_at, _blocked_at, _look)
	var shown: Array = [_fire_at, _fire_radii]
	if _look["fires_explored_only"]:
		shown = MapFires.inside(_fire_at, _fire_radii, _explored_boxes)
	_fires.draw_fitted(_view(), shown[0], shown[1], _look)
	_miners.draw_fitted(_view(), _look)


func _view() -> Transform3D:
	return MapZoom.scaled(_fit, _zoom)

