class_name MapOverlays
extends RefCounted

## The markers and overlays drawn over the map hologram's lines (MAP-1, MAP-2,
## #1120): the ship dart (`MapShipMarker`), the exit and reactor (#338, RUN-3),
## the route and blocked openings (`MapRoute`, #400), fires (`MapFires`, #519,
## #562) and trapped miners (`MapMinerMarkers`, #1072). Split out of
## `MapHologram` so the hologram stays under the file-size limit; it keeps the
## level-space positions each overlay was handed and moves them into the
## hologram with the view the hologram passes in. It holds copies only, never
## a simulation object (MP-2).

const MARKER_NAME: String = "Marker"
const EXIT_NAME: String = "Exit"
const REACTOR_NAME: String = "Reactor"

var marker: MeshInstance3D = MeshInstance3D.new()
var exit: MeshInstance3D = MeshInstance3D.new()
var reactor: MeshInstance3D = MeshInstance3D.new()
var route: MapRoute = MapRoute.new()
var fires: MapFires = MapFires.new()
var miners: MapMinerMarkers = MapMinerMarkers.new()

## Level-space copies of what each overlay marks, kept so a new fit or zoom re-places them.
var ship_at: Vector3 = Vector3.ZERO
var exit_at: Vector3 = Vector3.ZERO
var reactor_at: Vector3 = Vector3.ZERO
var route_at: PackedVector3Array = PackedVector3Array()
var blocked_at: PackedVector3Array = PackedVector3Array()
var fire_at: PackedVector3Array = PackedVector3Array()
var fire_radii: PackedFloat32Array = PackedFloat32Array()
## The explored boxes of the last build, as copies, for `fires_explored_only`.
var explored_boxes: Array[AABB] = []
var markers_set: bool = false
var reactor_known: bool = false
var reactor_destroyed: bool = false


func _init() -> void:
	marker.name = MARKER_NAME
	exit.name = EXIT_NAME
	reactor.name = REACTOR_NAME
	for child: MeshInstance3D in [marker, exit, reactor]:
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Adds every overlay node under `parent`, in the order the hologram always had
## them: ship, exit, reactor, route, fires, miners.
func add_to(parent: Node3D) -> void:
	for child: Node3D in [marker, exit, reactor, route, fires, miners]:
		parent.add_child(child)


## Remakes the ship, exit and reactor meshes from `look` (a build or a look reload).
func make_meshes(look: Dictionary) -> void:
	var energy: float = float(look["line_energy"])
	marker.mesh = MapShipMarker.mesh(look["marker_color"], float(look["marker_radius_m"]), energy)
	exit.mesh = MapShapes.exit_cube(look)
	reactor.mesh = MapShapes.reactor_ball(look, reactor_destroyed, energy)


## Records the exit and reactor and places them through `view`; the reactor shows
## only while `known`, and its mesh changes colour only when `destroyed` changes (#913).
func set_markers(at_exit: Vector3, at_reactor: Vector3, known: bool, destroyed: bool, look: Dictionary, view: Transform3D) -> void:
	exit_at = at_exit
	reactor_at = at_reactor
	reactor_known = known
	if destroyed != reactor_destroyed:
		reactor_destroyed = destroyed
		reactor.mesh = MapShapes.reactor_ball(look, reactor_destroyed, float(look["line_energy"]))
	markers_set = true
	place_markers(view)


## Remakes the ship, exit and reactor meshes and re-places the exit, reactor and
## overlays through a new `view`; the ship dart waits for its next position, as before #1120.
func rebuild(view: Transform3D, look: Dictionary) -> void:
	make_meshes(look)
	place_markers(view)
	place_overlays(view, look)


## Keeps copies of the route's `points_m` and `blocked_m` and redraws the overlays.
func show_route(points_m: PackedVector3Array, blocked_m: PackedVector3Array, view: Transform3D, look: Dictionary) -> void:
	route_at = points_m.duplicate()
	blocked_at = blocked_m.duplicate()
	place_overlays(view, look)


## Keeps copies of the fires' `centres_m` and `radii_m` and redraws the overlays.
func show_fires(centres_m: PackedVector3Array, radii_m: PackedFloat32Array, view: Transform3D, look: Dictionary) -> void:
	fire_at = centres_m.duplicate()
	fire_radii = radii_m.duplicate()
	place_overlays(view, look)


## Keeps a copy of the trapped miners `at_m` and redraws the overlays.
func show_miners(at_m: PackedVector3Array, view: Transform3D, look: Dictionary) -> void:
	miners.at_m = at_m.duplicate()
	place_overlays(view, look)


## Keeps copies of the boxes of `union` listed in `explored`, for `fires_explored_only`.
func keep_explored(union: BoxUnion, explored: Array[int]) -> void:
	explored_boxes.clear()
	for index: int in explored:
		if index >= 0 and index < union.boxes.size():
			var box: BoxBounds = union.boxes[index]
			explored_boxes.append(AABB(box.min_corner, box.max_corner - box.min_corner))


## Re-places every overlay through `view`, as a zoom or a look reload needs.
func place_all(view: Transform3D, look: Dictionary) -> void:
	place_ship(view)
	place_markers(view)
	place_overlays(view, look)


## Moves the ship dart to `ship_at` through `view`.
func place_ship(view: Transform3D) -> void:
	marker.position = view * ship_at


## Shows the exit once markers were set and the reactor while known, at their
## positions through `view`.
func place_markers(view: Transform3D) -> void:
	exit.visible = markers_set
	reactor.visible = markers_set and reactor_known
	exit.position = view * exit_at
	reactor.position = view * reactor_at


## Redraws the route, fires and miners through `view` with `look`; fires outside
## `explored_boxes` are left out while `fires_explored_only` is on (#562).
func place_overlays(view: Transform3D, look: Dictionary) -> void:
	route.draw_fitted(view, route_at, blocked_at, look)
	var shown: Array = [fire_at, fire_radii]
	if look["fires_explored_only"]:
		shown = MapFires.inside(fire_at, fire_radii, explored_boxes)
	fires.draw_fitted(view, shown[0], shown[1], look)
	miners.draw_fitted(view, look)
