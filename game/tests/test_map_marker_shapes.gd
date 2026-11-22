extends RefCounted

## The map's four point markers differ by shape as well as colour (#1219, MAP-1,
## SLV-3, PLT-2, ARC-4): the ship's dart, the reactor, a trapped miner and a fire
## each have an outline no other uses, the shapes and colours come from
## `map_look.json`, and no two of the four colours sit within
## `MIN_HUE_DEGREES` of each other, so the owner cannot again take a fire for a
## second reactor.

## An eighth of the colour wheel and a little more. The owner's yellow fire sat
## 28 degrees from the ship's orange and was taken for another marker; the
## reactor's magenta and the miner's violet, the closest pair shipped, sit
## about 46 apart and also differ by outline.
const MIN_HUE_DEGREES: float = 40.0
## Below this saturation a colour reads as white or grey and its hue says little.
const MIN_SATURATION: float = 0.4
## The four markers' colour keys, in the order the messages name them.
const COLOR_KEYS: Array[String] = ["marker_color", "reactor_color", "miner_color", "fire_color"]
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'
const EPSILON: float = 1e-5


static func _hue_distance(a: Color, b: Color) -> float:
	var apart: float = absf(a.h - b.h) * 360.0
	return minf(apart, 360.0 - apart)


static func _shipped() -> Dictionary:
	return MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))


## The distinct corner points of `points`, rounded so shared corners count once.
static func _corners(points: PackedVector3Array) -> Array[Vector3]:
	var seen: Array[Vector3] = []
	for point: Vector3 in points:
		var key: Vector3 = point.snapped(Vector3.ONE * 1e-6)
		if not seen.has(key):
			seen.append(key)
	return seen


static func _vertices(mesh: Mesh) -> PackedVector3Array:
	if mesh == null or mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


## Each of the four markers drawn from `look`, one apiece at the origin, as
## `{name: vertices}`.
static func _drawn(look: Dictionary) -> Dictionary:
	var energy: float = float(look["line_energy"])
	var fires: MapFires = MapFires.new()
	fires.draw_fitted(Transform3D.IDENTITY, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([0.0]), look)
	var miners: MapMinerMarkers = MapMinerMarkers.new()
	miners.at_m = PackedVector3Array([Vector3.ZERO])
	miners.draw_fitted(Transform3D.IDENTITY, look)
	var drawn: Dictionary = {
		"ship": _vertices(MapShipMarker.mesh(look["marker_color"], float(look["marker_radius_m"]), energy)),
		"reactor": _vertices(MapShapes.reactor_marker(look, false, energy)),
		"miner": _vertices(miners.mesh_node().mesh),
		"fire": _vertices(fires.mesh_node().mesh),
	}
	fires.free()
	miners.free()
	return drawn


func test_the_four_markers_have_four_different_outlines() -> String:
	var look: Dictionary = _shipped()
	if look.has("error"):
		return "map_look.json rejected: %s" % look["error"]
	var drawn: Dictionary = _drawn(look)
	var counts: Dictionary = {}
	for name: String in drawn:
		var corners: int = _corners(drawn[name]).size()
		if corners == 0:
			return "the %s marker drew nothing" % name
		for other: String in counts:
			if counts[other] == corners:
				return "the %s and %s markers both have %d corners: the same kind of outline" % [other, name, corners]
		counts[name] = corners
	return ""


func test_the_shipped_shapes_are_a_diamond_a_pin_and_a_flame() -> String:
	var look: Dictionary = _shipped()
	if look.has("error"):
		return "map_look.json rejected: %s" % look["error"]
	var want: Dictionary = {"reactor_shape": MapMarkerShapes.DIAMOND, "miner_shape": MapMarkerShapes.PIN,
			"fire_shape": MapMarkerShapes.FLAME}
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	for key: String in want:
		if not raw.has(key):
			return "map_look.json does not name %s" % key
		if look[key] != want[key] or MapLook.FALLBACK[key] != want[key]:
			return "%s ships as %s (built-in %s), want %s" % [key, look[key], MapLook.FALLBACK[key], want[key]]
	return ""


func test_each_marker_draws_the_shape_its_key_names() -> String:
	var look: Dictionary = _shipped().duplicate()
	# A rotation of the shipped shapes: every marker gets one it did not have.
	look["reactor_shape"] = MapMarkerShapes.FLAME
	look["miner_shape"] = MapMarkerShapes.DIAMOND
	look["fire_shape"] = MapMarkerShapes.PIN
	var drawn: Dictionary = _drawn(look)
	for name: String in ["reactor", "miner", "fire"]:
		var shape: String = look[name + "_shape"]
		var want: int = _corners(MapMarkerShapes.triangles(shape, Vector3.ZERO, 1.0)).size()
		var got: int = _corners(drawn[name]).size()
		if got != want or (drawn[name] as PackedVector3Array).size() != MapMarkerShapes.VERTICES[shape]:
			return "the %s marker drew %d corners in %d vertices, want the %s's %d in %d" % [
				name, got, (drawn[name] as PackedVector3Array).size(), shape, want, MapMarkerShapes.VERTICES[shape]]
	return ""


func test_each_shape_is_as_tall_as_asked_with_its_own_width() -> String:
	for shape: String in MapMarkerShapes.NAMES:
		var points: PackedVector3Array = MapMarkerShapes.triangles(shape, Vector3(1.0, 2.0, 3.0), 0.02)
		if points.size() != MapMarkerShapes.VERTICES[shape]:
			return "%s has %d vertices, want %d" % [shape, points.size(), MapMarkerShapes.VERTICES[shape]]
		var box: AABB = AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points:
			box = box.expand(point)
		if absf(box.size.y - 0.02) > EPSILON or box.get_center().distance_to(Vector3(1.0, 2.0, 3.0)) > 0.02 * 0.2:
			return "%s spans %s around %s, want 0.02 tall around (1, 2, 3)" % [shape, box.size, box.get_center()]
		# The flame's three-sided base is a little narrower across than the
		# circle it sits in, so its width may fall short of the ratio, never past.
		var width: float = maxf(box.size.x, box.size.z) / 0.02
		var ratio: float = MapMarkerShapes.WIDTH_PER_HEIGHT[shape]
		if width > ratio + 0.01 or width < ratio * 0.85:
			return "%s is %.3f wide per height, want %.2f" % [shape, width, ratio]
	if not MapMarkerShapes.triangles("ball", Vector3.ZERO, 1.0).is_empty():
		return "an unknown shape drew triangles"
	return ""


func test_the_flame_points_up_and_the_pin_points_down() -> String:
	var flame: Array[Vector3] = _corners(MapMarkerShapes.triangles(MapMarkerShapes.FLAME, Vector3.ZERO, 1.0))
	var pin: Array[Vector3] = _corners(MapMarkerShapes.triangles(MapMarkerShapes.PIN, Vector3.ZERO, 1.0))
	var flame_top: int = flame.filter(func(p: Vector3) -> bool: return p.y > 0.49).size()
	var pin_bottom: int = pin.filter(func(p: Vector3) -> bool: return p.y < -0.49).size()
	if flame_top != 1 or pin_bottom != 1:
		return "flame has %d points on top, pin %d at the bottom; want one each" % [flame_top, pin_bottom]
	return ""


func test_no_two_of_the_four_colours_are_close_in_hue() -> String:
	var shipped: Dictionary = _shipped()
	if shipped.has("error"):
		return "map_look.json rejected: %s" % shipped["error"]
	for look: Dictionary in [shipped, MapLook.FALLBACK]:
		for i: int in COLOR_KEYS.size():
			var a: Color = look[COLOR_KEYS[i]]
			if a.s < MIN_SATURATION:
				return "%s %s is too grey (saturation %.2f) for its hue to show" % [COLOR_KEYS[i], a, a.s]
			for j: int in range(i + 1, COLOR_KEYS.size()):
				var b: Color = look[COLOR_KEYS[j]]
				var apart: float = _hue_distance(a, b)
				if apart < MIN_HUE_DEGREES:
					return "%s %s and %s %s are %.0f degrees of hue apart, under %.0f" % [
						COLOR_KEYS[i], a, COLOR_KEYS[j], b, apart, MIN_HUE_DEGREES]
	return ""


func test_the_old_yellow_fire_would_fail_the_hue_check() -> String:
	# The fire colour of the owner's playtest (#1208) against the ship's orange.
	var apart: float = _hue_distance(Color(1.0, 1.0, 0.0), MapLook.FALLBACK["marker_color"])
	return "" if apart < MIN_HUE_DEGREES else "the old yellow fire is %.0f degrees from the ship; the check would miss it" % apart


func test_bad_or_shared_shapes_are_rejected_by_name() -> String:
	var cases: Dictionary = {
		OLD_LOOK.replace("}", ', "reactor_shape": "ball"}'): "reactor_shape",
		OLD_LOOK.replace("}", ', "fire_shape": 3}'): "fire_shape",
		OLD_LOOK.replace("}", ', "miner_shape": "flame"}'): "miner_shape",
		OLD_LOOK.replace("}", ', "reactor_shape": "pin", "fire_shape": "diamond"}'): "reactor_shape",
	}
	for text: String in cases:
		var look: Dictionary = MapLook.parse(text)
		if str(look.get("error", "")).find(str(cases[text])) < 0:
			return "'%s' gave %s, want an error naming %s" % [text, look, cases[text]]
	var old: Dictionary = MapLook.parse(OLD_LOOK)
	if old.has("error") or old["fire_shape"] != MapMarkerShapes.FLAME:
		return "a look file without shape keys did not keep the built-in shapes: %s" % old
	return ""
