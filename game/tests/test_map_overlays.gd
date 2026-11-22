extends RefCounted

## The map hologram's overlays split into `MapOverlays` (#1120, MAP-1, MAP-2):
## it adds the ship, exit, reactor, route, fire and miner nodes under its parent
## in the hologram's old order and names, places each through the view it is
## handed, and the hologram still holds them as direct children.

const EPSILON: float = 1e-4
## The child names the hologram always had, after its `Lines`.
const ORDER: Array[String] = [
	"Marker", "Exit", "Reactor", "MapRoute", "MapFires", MapMinerMarkers.NODE_NAME,
]


func _names(parent: Node) -> Array[String]:
	var names: Array[String] = []
	for child: Node in parent.get_children():
		names.append(String(child.name))
	return names


func _box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -2, -2), Vector3(2, 2, 2))]
	return BoxUnion.new(boxes)


func test_adds_the_overlay_children_in_the_old_order() -> String:
	var parent: Node3D = Node3D.new()
	var overlays: MapOverlays = MapOverlays.new()
	overlays.add_to(parent)
	var names: Array[String] = _names(parent)
	var shadowless: bool = overlays.marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and overlays.exit.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and overlays.reactor.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.free()
	if names != ORDER:
		return "children were %s, expected %s" % [str(names), str(ORDER)]
	if not shadowless:
		return "a marker casts a shadow"
	return ""


func test_the_hologram_keeps_them_as_direct_children() -> String:
	var map: MapHologram = MapHologram.new()
	var names: Array[String] = _names(map)
	map.free()
	var expected: Array[String] = [MapHologram.LINES_NAME]
	expected.append_array(ORDER)
	if names != expected:
		return "hologram children were %s, expected %s" % [str(names), str(expected)]
	return ""


func test_places_ship_and_markers_through_the_view() -> String:
	var parent: Node3D = Node3D.new()
	var overlays: MapOverlays = MapOverlays.new()
	overlays.add_to(parent)
	var view: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), Vector3(1, 0, 0))
	overlays.ship_at = Vector3(2, 4, 6)
	overlays.place_ship(view)
	overlays.place_markers(view)
	var before_set: bool = overlays.exit.visible or overlays.reactor.visible
	overlays.set_markers(Vector3(0, 0, -8), Vector3(4, 0, 0), false, false, MapLook.FALLBACK, view)
	var exit_shown: bool = overlays.exit.visible
	var reactor_hidden: bool = not overlays.reactor.visible
	overlays.set_markers(Vector3(0, 0, -8), Vector3(4, 0, 0), true, false, MapLook.FALLBACK, view)
	var reactor_shown: bool = overlays.reactor.visible
	var ship: Vector3 = overlays.marker.position
	var exit: Vector3 = overlays.exit.position
	var reactor: Vector3 = overlays.reactor.position
	parent.free()
	if before_set:
		return "exit or reactor shown before set_markers"
	if not (exit_shown and reactor_hidden and reactor_shown):
		return "exit shown %s, reactor hidden while unknown %s, shown once known %s" % [exit_shown, reactor_hidden, reactor_shown]
	if not ship.is_equal_approx(Vector3(2, 2, 3)):
		return "ship marker at %s, expected (2, 2, 3)" % str(ship)
	if not exit.is_equal_approx(Vector3(1, 0, -4)) or not reactor.is_equal_approx(Vector3(3, 0, 0)):
		return "exit at %s, reactor at %s" % [str(exit), str(reactor)]
	return ""


func test_draws_route_fires_and_miners_through_the_view() -> String:
	var parent: Node3D = Node3D.new()
	var overlays: MapOverlays = MapOverlays.new()
	overlays.add_to(parent)
	overlays.keep_explored(_box(), [0])
	var view: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), Vector3.ZERO)
	var route: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -1)])
	overlays.show_route(route, PackedVector3Array(), view, MapLook.FALLBACK)
	var fire_at: PackedVector3Array = PackedVector3Array([Vector3(1, 0, 0), Vector3(50, 0, 0)])
	overlays.show_fires(fire_at, PackedFloat32Array([0.5, 0.5]), view, MapLook.FALLBACK)
	overlays.show_miners(PackedVector3Array([Vector3(0, 2, 0)]), view, MapLook.FALLBACK)
	var has_line: bool = overlays.route.get_node_or_null(MapRoute.LINE_NAME) != null \
		and (overlays.route.get_node(MapRoute.LINE_NAME) as MeshInstance3D).mesh != null
	var fires: PackedVector3Array = overlays.fires.marker_positions()
	var miners: PackedVector3Array = overlays.miners.marker_positions()
	var boxes: int = overlays.explored_boxes.size()
	parent.free()
	if boxes != 1:
		return "kept %d explored boxes, expected 1" % boxes
	if not has_line:
		return "no route line drawn"
	var expected_fires: int = 1 if bool(MapLook.FALLBACK["fires_explored_only"]) else 2
	if fires.size() != expected_fires or not fires[0].is_equal_approx(Vector3(0.5, 0, 0)):
		return "fires drawn at %s, expected %d starting at (0.5, 0, 0)" % [str(fires), expected_fires]
	if miners.size() != 1 or not miners[0].is_equal_approx(Vector3(0, 1, 0)):
		return "miners drawn at %s, expected [(0, 1, 0)]" % str(miners)
	return ""
