class_name MapOverlays
extends RefCounted

## Everything the held map draws on top of its outline (MAP-1, #1120): the ship
## dart (`MapShipMarker`), the exit and reactor markers (#338, RUN-3), the route
## and blocked openings (`MapRoute`, #400), fires (`MapFires`, #519, #562) and
## trapped miners (`MapMinerMarkers`, #1072). Split out of `MapHologram` so that
## file stays small; the hologram still owns the fit and zoom and hands the view
## transform in. The children are added straight under the hologram with the
## names tests and wiring already look up. Positions are level-space copies, so
## nothing here can reach simulation state (MP-2).

const MARKER_NAME: String = "Marker"
const EXIT_NAME: String = "Exit"
const REACTOR_NAME: String = "Reactor"

var marker: MeshInstance3D = MeshInstance3D.new()
var exit: MeshInstance3D = MeshInstance3D.new()
var reactor: MeshInstance3D = MeshInstance3D.new()
var route: MapRoute = MapRoute.new()
var fires: MapFires = MapFires.new()
var miners: MapMinerMarkers = MapMinerMarkers.new()

## The route's level-space points and blocked centres, kept so a re-fit can re-place them.
var _route_at: PackedVector3Array = PackedVector3Array()
var _blocked_at: PackedVector3Array = PackedVector3Array()
var _fire_at: PackedVector3Array = PackedVector3Array()
var _fire_radii: PackedFloat32Array = PackedFloat32Array()
## The explored boxes of the last build, as copies, for `fires_explored_only`.
var _explored_boxes: Array[AABB] = []
var _exit_at: Vector3 = Vector3.ZERO
var _reactor_at: Vector3 = Vector3.ZERO
var _markers_set: bool = false
var _reactor_known: bool = false
var _reactor_destroyed: bool = false
var _ship_at: Vector3 = Vector3.ZERO


func _init() -> void:
	marker.name = MARKER_NAME
	exit.name = EXIT_NAME
	reactor.name = REACTOR_NAME


## Adds every overlay child under `parent`: the three markers (no shadows), then
## the route, fires and miners, in the order the hologram always had them.
func add_to(parent: Node3D) -> void:
	for child: MeshInstance3D in [marker, exit, reactor]:
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(child)
	parent.add_child(route)
	parent.add_child(fires)
	parent.add_child(miners)


## Keeps copies of the explored boxes of `union` listed in `explored`.
func set_explored(union: BoxUnion, explored: Array[int]) -> void:
	_explored_boxes.clear()
	for index: int in explored:
		if index >= 0 and index < union.boxes.size():
			var box: BoxBounds = union.boxes[index]
			_explored_boxes.append(AABB(box.min_corner, box.max_corner - box.min_corner))


## Remakes the marker meshes from `look` (on each build).
func rebuild_meshes(look: Dictionary) -> void:
	var energy: float = float(look["line_energy"])
	marker.mesh = MapShipMarker.mesh(look["marker_color"], float(look["marker_radius_m"]), energy)
	exit.mesh = MapShapes.exit_cube(look)
	reactor.mesh = MapShapes.reactor_ball(look, _reactor_destroyed, energy)


func set_ship_position(position: Vector3, view: Transform3D) -> void:
	_ship_at = position
	place_ship(view)


func set_ship_orientation(orientation: Basis) -> void:
	marker.basis = orientation.orthonormalized()


## See `MapHologram.set_markers`.
func set_markers(exit_at: Vector3, reactor_at: Vector3, reactor_known: bool, reactor_destroyed: bool,
		look: Dictionary, view: Transform3D) -> void:
	_exit_at = exit_at
	_reactor_at = reactor_at
	_reactor_known = reactor_known
	if reactor_destroyed != _reactor_destroyed:
		_reactor_destroyed = reactor_destroyed
		reactor.mesh = MapShapes.reactor_ball(look, _reactor_destroyed, float(look["line_energy"]))
	_markers_set = true
	place_markers(view)


func set_route(points_m: PackedVector3Array, blocked_m: PackedVector3Array) -> void:
	_route_at = points_m.duplicate()
	_blocked_at = blocked_m.duplicate()


func set_fires(centres_m: PackedVector3Array, radii_m: PackedFloat32Array) -> void:
	_fire_at = centres_m.duplicate()
	_fire_radii = radii_m.duplicate()


func set_miners(at_m: PackedVector3Array) -> void:
	miners.at_m = at_m.duplicate()


func place_ship(view: Transform3D) -> void:
	marker.position = view * _ship_at


## Shows the exit once markers were set and the reactor while it is known.
func place_markers(view: Transform3D) -> void:
	exit.visible = _markers_set
	reactor.visible = _markers_set and _reactor_known
	exit.position = view * _exit_at
	reactor.position = view * _reactor_at


## Re-draws the route, fires and miners fitted by `view`.
func place_route(view: Transform3D, look: Dictionary) -> void:
	route.draw_fitted(view, _route_at, _blocked_at, look)
	var shown: Array = [_fire_at, _fire_radii]
	if look["fires_explored_only"]:
		shown = MapFires.inside(_fire_at, _fire_radii, _explored_boxes)
	fires.draw_fitted(view, shown[0], shown[1], look)
	miners.draw_fitted(view, look)
