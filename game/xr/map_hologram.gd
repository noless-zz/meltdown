class_name MapHologram
extends Node3D

## The explored mine as a small hologram held in the hand (MAP-1, #314): the
## `MapWireframe` outline of the explored boxes as one emissive line mesh fitted
## into a cube of `size_m`. It hangs
## under a controller; a click of `show_map` opens it and the next closes it
## (#914). Sharing the label button, a click toggles the map and a hold the
## labels (#335). It is handed copies and holds no session, so it never writes
## simulation state or comfort settings (ARC-3, CMF-6, MP-2).
##
## The ship dart, exit, reactor, route, fires and miners are `MapOverlays` (#1120),
## fitted like the lines. `set_zoom` scales it all about the hand (#549). The look
## is `res://xr/map_look.json` (ARC-4), parsed by `MapLook`.
##
## Since #1321 the pilot may mount it in the cockpit instead (`mount_on`, placed
## by `MapPlacement`), shrunk to the cockpit's `map_mount` size, and may have it
## follow the ship: turned against the ship's orientation, so ahead on the map
## is always ahead of the nose. Both only move this node (ARC-3, CMF-6).

const NODE_NAME: String = "MapHologram"
const LINES_NAME: String = "Lines"
const MARKER_NAME: String = MapOverlays.MARKER_NAME
const EXIT_NAME: String = MapOverlays.EXIT_NAME
const REACTOR_NAME: String = MapOverlays.REACTOR_NAME
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
var _overlays: MapOverlays = MapOverlays.new()
var _zoom: float = MapZoom.START
var _toggle: MapToggle = MapToggle.new()
## The ship's orientation last handed to `set_ship_orientation` (a copy).
var _ship_turn: Basis = Basis.IDENTITY
## Whether the map turns against `_ship_turn` (`MapChoice.TURN_FOLLOWS`).
var _follows_ship: bool = false
## This node's scale: 1 in the hand, the mount's size over the look's in the cockpit.
var _mount_scale: float = 1.0


func _init() -> void:
	name = NODE_NAME
	visible = false
	_lines.name = LINES_NAME
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_overlays.add_to(self)
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
	_overlays.set_explored(union, explored)
	var size: float = float(_look["size_m"])
	_fit = fit_transform(points, size)
	_lines.mesh = MapShapes.outline(points, size, _look)
	_overlays.rebuild_meshes(_look)
	_overlays.place_markers(_view())
	_place_route()


## Number of line segments drawn by the last `build`.
func segment_count() -> int:
	var mesh: ArrayMesh = _lines.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / 2


## Moves the marker to the ship's level-space `position` (a copy), fitted like the lines.
func set_ship_position(position: Vector3) -> void:
	_overlays.set_ship_position(position, _view())


## The marker's position in the hologram.
func marker_position() -> Vector3:
	return _overlays.marker.position


## Turns the marker to the ship's `orientation` (a copy); the fit only scales, so it carries over.
func set_ship_orientation(orientation: Basis) -> void:
	_overlays.set_ship_orientation(orientation)
	_ship_turn = orientation.orthonormalized()
	_apply_basis()


## Turns the map against the ship's orientation while `follows` (#1321), so
## the marker always points ahead; otherwise its level axes stay fixed to its holder.
func set_follows_ship(follows: bool) -> void:
	_follows_ship = follows
	_apply_basis()


func follows_ship() -> bool:
	return _follows_ship


## This node's scale: 1 in the hand, below 1 when mounted in a cockpit.
func mount_scale() -> float:
	return _mount_scale


## Hangs this map under `holder` (the cockpit frame, eye at its origin) with
## its centre at `at`, fitted into a cube of `edge_m` rather than the look's
## `size_m` (#1321).
func mount_on(holder: Node3D, at: Vector3, edge_m: float) -> void:
	if get_parent() != holder:
		if get_parent() != null:
			get_parent().remove_child(self)
		holder.add_child(self)
	position = at
	_mount_scale = edge_m / maxf(float(_look["size_m"]), 0.001)
	_apply_basis()


## Marks the exit (the entrance, RUN-3) and the reactor at level-space copies of
## their positions, fitted like the lines; the reactor shows only while `reactor_known`,
## in the look's dead colour once `reactor_destroyed` (#913).
func set_markers(exit_at: Vector3, reactor_at: Vector3, reactor_known: bool, reactor_destroyed: bool = false) -> void:
	_overlays.set_markers(exit_at, reactor_at, reactor_known, reactor_destroyed, _look, _view())


## The exit and reactor markers' nodes, for reading their meshes and materials.
func marker_nodes() -> Array[MeshInstance3D]:
	return [_overlays.exit, _overlays.reactor]


## The exit marker's position in the hologram.
func exit_marker_position() -> Vector3:
	return _overlays.exit.position


## The reactor marker's position in the hologram.
func reactor_marker_position() -> Vector3:
	return _overlays.reactor.position


## Draws the suggested route through `points_m` and a cross at each of `blocked_m`
## (level-space copies, as `KnownRoute` gives them), fitted like the lines.
func show_route(points_m: PackedVector3Array, blocked_m: PackedVector3Array) -> void:
	_overlays.set_route(points_m, blocked_m)
	_place_route()


## Removes the route and the blocked markers.
func clear_route() -> void:
	show_route(PackedVector3Array(), PackedVector3Array())


## The route's node, for reading what it drew.
func route() -> MapRoute:
	return _overlays.route


## Marks each burning fire entry at `centres_m` with radius `radii_m` (level-
## space copies), fitted like the lines; see `MapFires`. Empty arrays remove them.
func show_fires(centres_m: PackedVector3Array, radii_m: PackedFloat32Array) -> void:
	_overlays.set_fires(centres_m, radii_m)
	_place_route()


## The node drawing the fire markers, for reading what it drew.
func fires() -> MapFires:
	return _overlays.fires


## Pins a trapped miner at each of `at_m` (level-space copies); none when empty (#1072).
func show_miners(at_m: PackedVector3Array) -> void:
	_overlays.set_miners(at_m)
	_place_route()


## Whether the exit marker is drawn: once `set_markers` was called.
func exit_marker_shown() -> bool:
	return _overlays.exit.visible


## Whether the reactor marker is drawn: once `set_markers` said it is known.
func reactor_marker_shown() -> bool:
	return _overlays.reactor.visible


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
	_mount_scale = 1.0
	_apply_basis()
	return true


## Scales the map by `factor`, clamped to the look's limits, about the hand anchor
## (its origin), so the held point stays put. Marker sizes keep their floors; `build` keeps it.
func set_zoom(factor: float) -> void:
	_zoom = clampf(factor, float(_look["min_zoom"]), float(_look["max_zoom"]))
	_lines.scale = Vector3.ONE * _zoom
	_overlays.place_ship(_view())
	_overlays.place_markers(_view())
	_place_route()


func zoom() -> float:
	return _zoom


## Level space -> hologram space; see `MapShapes.fit_transform`.
static func fit_transform(points: PackedVector3Array, edge_m: float) -> Transform3D:
	return MapShapes.fit_transform(points, edge_m)


func _apply_basis() -> void:
	var turn: Basis = _ship_turn.inverse() if _follows_ship else Basis.IDENTITY
	basis = turn.scaled(Vector3.ONE * _mount_scale)


func _place_route() -> void:
	_overlays.place_route(_view(), _look)


func _view() -> Transform3D:
	return MapZoom.scaled(_fit, _zoom)

