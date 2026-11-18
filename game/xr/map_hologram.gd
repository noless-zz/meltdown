class_name MapHologram
extends Node3D

## The map of the explored mine as a small hologram held in the hand (MAP-1,
## #314): the `MapWireframe` outline of the explored boxes as one emissive line
## mesh, fitted into a cube of `size_m`, with a marker where the ship is.
##
## It hangs under a controller, so it turns with the hand. It shows only while
## the `show_map` action has been held for `HOLD_SECONDS`; a shorter click of
## the same button stays the label toggle. When both share that button, the
## map takes its answer from the label wiring's `ClickHold` (#335), so one
## press can never both show the map and flip the labels.
##
## It is handed copies (the union, the explored indices, the ship position) and
## keeps no reference to the session, so it can never write simulation state
## or comfort settings (ARC-3, CMF-6, MP-2).
##
## An exit marker (a cube) and a reactor marker (a ball) show where to leave
## the mine and what to destroy (#338, MAP-2, RUN-3); they are fitted like the
## lines, so they move with the map when more boxes are explored. The
## suggested route and blocked openings (MAP-2, #400) are drawn by a `MapRoute`
## child, fitted the same way, and burning fire entries (#519) by a `MapFires`
## child. The shared geometry lives in `MapShapes`.
##
## The look lives in `res://xr/map_look.json` (ARC-4), parsed by `MapLook`.

const NODE_NAME: String = "MapHologram"
const LINES_NAME: String = "Lines"
const MARKER_NAME: String = "Marker"
const EXIT_NAME: String = "Exit"
const REACTOR_NAME: String = "Reactor"
const DEFAULT_LOOK_FILE: String = "res://xr/map_look.json"
## How long `show_map` must be held before the map shows. Long enough that a
## click for the labels never flashes the map, short enough not to feel slow.
const HOLD_SECONDS: float = 0.4
## The map's centre from the controller: above the hand and a little ahead,
## so the hand does not cover it and lowering the hand takes it out of view.
const HAND_OFFSET: Vector3 = Vector3(0.0, 0.12, -0.08)
## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = MapLook.FALLBACK

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## How long `show_map` has been held; 0 while it is released.
var held_seconds: float = 0.0

var _look: Dictionary = FALLBACK_LOOK
## Level space -> hologram space, as `MapWireframe.fit_to_cube` fits the lines.
var _fit: Transform3D = Transform3D.IDENTITY
var _lines: MeshInstance3D = MeshInstance3D.new()
var _marker: MeshInstance3D = MeshInstance3D.new()
var _exit: MeshInstance3D = MeshInstance3D.new()
var _reactor: MeshInstance3D = MeshInstance3D.new()
var _route: MapRoute = MapRoute.new()
var _fires: MapFires = MapFires.new()
## The route's level-space points and blocked centres, kept so `build` can re-fit them.
var _route_at: PackedVector3Array = PackedVector3Array()
var _blocked_at: PackedVector3Array = PackedVector3Array()
var _fire_at: PackedVector3Array = PackedVector3Array()
var _fire_radii: PackedFloat32Array = PackedFloat32Array()
## The markers' level-space positions, kept so `build` can re-fit them.
var _exit_at: Vector3 = Vector3.ZERO
var _reactor_at: Vector3 = Vector3.ZERO
var _markers_set: bool = false
var _reactor_known: bool = false


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
	_exit.visible = false
	_reactor.visible = false
	load_look()


## Parses the text of a look file; see `MapLook.parse`.
static func parse_look(text: String) -> Dictionary:
	return MapLook.parse(text)


## Applies the look file at `path`. A missing or rejected file leaves the
## built-in look, sets `look_error` and pushes a warning naming the field.
## Takes effect on the next `build`. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = MapLook.parse(FileAccess.get_file_as_string(path))
	else:
		values = _rejected("file not found")
	_look = FALLBACK_LOOK
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("MapHologram uses the built-in look; %s" % look_error)
	else:
		_look = values
	return look_error


## The look the next `build` uses.
func look() -> Dictionary:
	return _look


## Redraws the map from the boxes of `union` listed in `explored`.
func build(union: BoxUnion, explored: Array[int]) -> void:
	var points: PackedVector3Array = MapWireframe.segments(union, explored)
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
	_marker.mesh = MapShapes.ball(_look["marker_color"], float(_look["marker_radius_m"]), energy)
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE * float(_look["exit_radius_m"]) * 2.0
	cube.material = MapShapes.glow(_look["exit_color"], energy)
	_exit.mesh = cube
	_reactor.mesh = MapShapes.ball(_look["reactor_color"], float(_look["reactor_radius_m"]), energy)
	_place_markers()
	_place_route()


## Number of line segments drawn by the last `build`.
func segment_count() -> int:
	var mesh: ArrayMesh = _lines.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / 2


## Moves the marker to the ship's level-space `position` (a copy), fitted
## like the lines.
func set_ship_position(position: Vector3) -> void:
	_marker.position = _fit * position


## The marker's position in the hologram.
func marker_position() -> Vector3:
	return _marker.position


## Marks the exit (the entrance, RUN-3) and the reactor at their level-space
## positions (copies), fitted like the lines. The reactor marker shows only
## while `reactor_known`.
func set_markers(exit_position: Vector3, reactor_position: Vector3, reactor_known: bool) -> void:
	_exit_at = exit_position
	_reactor_at = reactor_position
	_reactor_known = reactor_known
	_markers_set = true
	_place_markers()


## The exit marker's position in the hologram.
func exit_marker_position() -> Vector3:
	return _exit.position


## The reactor marker's position in the hologram.
func reactor_marker_position() -> Vector3:
	return _reactor.position


## Draws the suggested route through `points_m` and a cross at each of
## `blocked_m` (level-space copies, as `KnownRoute` gives them), fitted like
## the lines. Empty arrays draw nothing.
func show_route(points_m: PackedVector3Array, blocked_m: PackedVector3Array) -> void:
	_route_at = points_m.duplicate()
	_blocked_at = blocked_m.duplicate()
	_place_route()


## Removes the route and the blocked markers.
func clear_route() -> void:
	show_route(PackedVector3Array(), PackedVector3Array())


## The node drawing the route, for reading what it drew.
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


## Whether the exit marker is drawn: once `set_markers` was called.
func exit_marker_shown() -> bool:
	return _exit.visible


## Whether the reactor marker is drawn: once `set_markers` said it is known.
func reactor_marker_shown() -> bool:
	return _reactor.visible


## Records whether `show_map` is held this frame of `delta` seconds. The map
## shows once the hold reaches `HOLD_SECONDS` and hides on release.
func hold(held: bool, delta: float) -> void:
	held_seconds = held_seconds + delta if held else 0.0
	visible = held and held_seconds >= HOLD_SECONDS


## Reads `show_map` through `mapping` from sampled `buttons` and calls `hold`.
## With `shared` (the label button's `ClickHold`, given only while that button
## also shows the map), the map shows exactly while `shared` reports a long
## hold instead; call this after `shared` was fed for the frame.
func read(mapping: ThumbstickMapping, buttons: Dictionary, delta: float,
		shared: ClickHold = null) -> void:
	if shared == null:
		hold(mapping.action_held("show_map", buttons), delta)
		return
	held_seconds = held_seconds + delta if shared.is_held() else 0.0
	visible = shared.is_long_hold()


## The hand that clicks `show_map`, so the map sits in the hand that holds it:
## left by default, right when left-handed mode or a remap moves the click.
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


## Level space -> hologram space; see `MapShapes.fit_transform`.
static func fit_transform(points: PackedVector3Array, edge_m: float) -> Transform3D:
	return MapShapes.fit_transform(points, edge_m)


static func _rejected(message: String) -> Dictionary:
	return {"error": message}


func _place_markers() -> void:
	_exit.visible = _markers_set
	_reactor.visible = _markers_set and _reactor_known
	_exit.position = _fit * _exit_at
	_reactor.position = _fit * _reactor_at


func _place_route() -> void:
	_route.draw_fitted(_fit, _route_at, _blocked_at, _look)
	_fires.draw_fitted(_fit, _fire_at, _fire_radii, _look)

