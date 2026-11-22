extends RefCounted

## The map's overlay helper (MAP-1, #1120): it adds the markers, route, fires and
## miners under the hologram as the hologram used to, and places them with the
## view transform it is handed.

const EPSILON: float = 1e-5


static func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < EPSILON


func test_add_to_adds_the_overlay_children_in_order() -> String:
	var parent: Node3D = Node3D.new()
	var overlays: MapOverlays = MapOverlays.new()
	overlays.add_to(parent)
	var names: Array[String] = []
	for child: Node in parent.get_children():
		names.append(child.name)
	var expected: Array[String] = [MapOverlays.MARKER_NAME, MapOverlays.EXIT_NAME, MapOverlays.REACTOR_NAME,
		str(overlays.route.name), str(overlays.fires.name), MapMinerMarkers.NODE_NAME]
	var shadows: bool = overlays.exit.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.free()
	if names != expected:
		return "children are %s, expected %s" % [names, expected]
	if shadows:
		return "the exit marker casts a shadow"
	return ""


func test_the_hologram_keeps_its_children_in_the_old_order() -> String:
	var map: MapHologram = MapHologram.new()
	var names: Array[String] = []
	for child: Node in map.get_children():
		names.append(child.name)
	var route_at: int = names.find(str(map.route().name))
	map.free()
	if names.slice(0, 4) != ([MapHologram.LINES_NAME, MapHologram.MARKER_NAME, MapHologram.EXIT_NAME,
			MapHologram.REACTOR_NAME] as Array[String]) or route_at != 4 or names.size() != 7:
		return "hologram children are %s" % [names]
	return ""


func test_markers_and_ship_are_placed_by_the_view() -> String:
	var parent: Node3D = Node3D.new()
	var overlays: MapOverlays = MapOverlays.new()
	overlays.add_to(parent)
	var view: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.01), Vector3(0.0, 0.1, 0.0))
	var failure: String = ""
	overlays.place_markers(view)
	if overlays.exit.visible or overlays.reactor.visible:
		failure = "markers show before they were set"
	overlays.set_markers(Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, -20.0), false, false, MapLook.FALLBACK, view)
	if failure == "" and (not overlays.exit.visible or overlays.reactor.visible):
		failure = "exit shown %s, unknown reactor shown %s" % [overlays.exit.visible, overlays.reactor.visible]
	if failure == "" and not _near(overlays.exit.position, Vector3(0.1, 0.1, 0.0)):
		failure = "exit placed at %s" % overlays.exit.position
	overlays.set_markers(Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, -20.0), true, false, MapLook.FALLBACK, view)
	if failure == "" and (not overlays.reactor.visible or not _near(overlays.reactor.position, Vector3(0.0, 0.1, -0.2))):
		failure = "known reactor at %s shown %s" % [overlays.reactor.position, overlays.reactor.visible]
	overlays.set_ship_position(Vector3(0.0, 5.0, 0.0), view)
	if failure == "" and not _near(overlays.marker.position, Vector3(0.0, 0.15, 0.0)):
		failure = "ship marker at %s" % overlays.marker.position
	overlays.place_ship(Transform3D.IDENTITY)
	if failure == "" and not _near(overlays.marker.position, Vector3(0.0, 5.0, 0.0)):
		failure = "re-placed ship marker at %s" % overlays.marker.position
	parent.free()
	return failure


func test_rebuilding_gives_every_marker_a_mesh() -> String:
	var overlays: MapOverlays = MapOverlays.new()
	overlays.rebuild_meshes(MapLook.FALLBACK)
	var failure: String = ""
	for node: MeshInstance3D in [overlays.marker, overlays.exit, overlays.reactor]:
		if node.mesh == null:
			failure = "%s has no mesh" % node.name
	for node: Node in [overlays.marker, overlays.exit, overlays.reactor, overlays.route, overlays.fires, overlays.miners]:
		node.free()
	return failure


func test_an_empty_outline_has_no_mesh() -> String:
	if MapShapes.outline(PackedVector3Array(), 0.25, MapLook.FALLBACK) != null:
		return "an empty outline made a mesh"
	var mesh: ArrayMesh = MapShapes.outline(PackedVector3Array([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)]), 0.25, MapLook.FALLBACK)
	if mesh == null or mesh.surface_get_array_len(0) != 2:
		return "one segment did not make a two-point line mesh"
	return ""
