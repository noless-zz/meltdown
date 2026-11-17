extends RefCounted

## The suggested route and blocked openings on the map hologram (#400, MAP-2,
## MAP-1): a route of three points is one line of two segments and a blocked
## centre one cross, both at the map's scale; `clear_route` and an empty route
## draw nothing; the look comes from the look file and stands apart from the
## wireframe and the other markers.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const EPSILON: float = 1e-4
## Colours closer than this (summed over r, g, b) are too alike to tell apart.
const MIN_COLOR_DISTANCE: float = 0.5
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _route(start: Vector3) -> PackedVector3Array:
	return PackedVector3Array([start, start + Vector3(0.0, 0.0, -6.0), start + Vector3(4.0, 0.0, -6.0)])


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func test_three_points_and_one_blocked_centre_at_the_map_scale() -> String:
	var level: LevelDef = _level()
	if level.error != "":
		return "g2 level did not load: %s" % level.error
	var explored: Array[int] = [0]
	var map: MapHologram = MapHologram.new()
	map.build(level.union, explored)
	var fit: Transform3D = MapHologram.fit_transform(MapWireframe.segments(level.union, explored),
			float(map.look()["size_m"]))
	var points: PackedVector3Array = _route(level.start_position())
	var blocked: Vector3 = level.start_position() + Vector3(0.0, 3.0, -6.0)
	map.show_route(points, PackedVector3Array([blocked]))
	var segments: int = map.route().segment_count()
	var ends: PackedVector3Array = map.route().segment_ends()
	var crosses: PackedVector3Array = map.route().blocked_positions()
	map.free()
	if segments != 2:
		return "route drawn as %d segments, want 2" % segments
	var want: PackedVector3Array = PackedVector3Array([fit * points[0], fit * points[1], fit * points[1],
			fit * points[2]])
	if ends.size() != want.size():
		return "segment ends %s, want %s" % [ends, want]
	for i: int in want.size():
		if ends[i].distance_to(want[i]) > EPSILON:
			return "segment end %d at %s, want %s" % [i, ends[i], want[i]]
	if crosses.size() != 1:
		return "%d blocked markers, want 1" % crosses.size()
	if crosses[0].distance_to(fit * blocked) > EPSILON:
		return "blocked marker at %s, want %s" % [crosses[0], fit * blocked]
	return ""


func test_clear_route_removes_the_line_and_the_markers() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	map.show_route(_route(level.start_position()), PackedVector3Array([level.start_position()]))
	var children_with: int = map.route().get_child_count()
	map.clear_route()
	var segments: int = map.route().segment_count()
	var crosses: int = map.route().blocked_positions().size()
	var children_after: int = map.route().get_child_count()
	map.free()
	if segments != 0 or crosses != 0:
		return "after clear_route: %d segments, %d blocked markers" % [segments, crosses]
	if children_after != children_with - 1:
		return "after clear_route %d child nodes remain of %d, want the marker node gone" % [children_after, children_with]
	return ""


func test_an_empty_route_draws_nothing() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.show_route(PackedVector3Array(), PackedVector3Array())
	var before_build: int = map.route().segment_count() + map.route().blocked_positions().size()
	map.build(level.union, [0])
	map.show_route(PackedVector3Array([level.start_position()]), PackedVector3Array())
	var one_point: int = map.route().segment_count()
	var mesh: Mesh = (map.route().get_node(MapRoute.LINE_NAME) as MeshInstance3D).mesh
	map.free()
	if before_build != 0:
		return "an empty route before any build drew %d things" % before_build
	if one_point != 0 or mesh != null:
		return "a one-point route drew %d segments" % one_point
	return ""


func test_the_route_is_refitted_when_more_boxes_are_explored() -> String:
	var level: LevelDef = _level()
	var all: Array[int] = []
	for i: int in level.union.boxes.size():
		all.append(i)
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var points: PackedVector3Array = _route(level.start_position())
	map.show_route(points, PackedVector3Array([points[2]]))
	map.build(level.union, all)
	var fit: Transform3D = MapHologram.fit_transform(MapWireframe.segments(level.union, all), float(map.look()["size_m"]))
	var ends: PackedVector3Array = map.route().segment_ends()
	var crosses: PackedVector3Array = map.route().blocked_positions()
	map.free()
	if ends.size() != 4 or ends[3].distance_to(fit * points[2]) > EPSILON:
		return "route ends %s after exploring all, want the last at %s" % [ends, fit * points[2]]
	if crosses.size() != 1 or crosses[0].distance_to(fit * points[2]) > EPSILON:
		return "blocked markers %s after exploring all, want one at %s" % [crosses, fit * points[2]]
	return ""


func test_the_look_comes_from_the_file_and_stands_apart() -> String:
	var shipped: Dictionary = MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if shipped.has("error"):
		return "map_look.json rejected: %s" % shipped["error"]
	for key: String in ["route_color", "route_width_m", "blocked_color", "blocked_size_m"]:
		if not shipped.has(key) or shipped[key] != MapLook.FALLBACK[key]:
			return "map_look.json %s is %s, want it shipped and equal to the built-in %s" % [key, shipped.get(key), MapLook.FALLBACK[key]]
	for look: Dictionary in [shipped, MapLook.FALLBACK]:
		for own: String in ["route_color", "blocked_color"]:
			for other: String in ["line_color", "marker_color", "exit_color", "reactor_color"]:
				if _distance(look[own], look[other]) < MIN_COLOR_DISTANCE:
					return "%s %s is too close to %s %s" % [own, look[own], other, look[other]]
		if _distance(look["route_color"], look["blocked_color"]) < MIN_COLOR_DISTANCE:
			return "route and blocked colours are too alike"
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	map.show_route(_route(level.start_position()), PackedVector3Array([level.start_position()]))
	var line: MeshInstance3D = map.route().get_node(MapRoute.LINE_NAME) as MeshInstance3D
	var line_glow: Color = (line.mesh.surface_get_material(0) as StandardMaterial3D).emission
	var cross: MeshInstance3D = map.route().get_node(MapRoute.BLOCKED_PREFIX + "0") as MeshInstance3D
	var cross_glow: Color = (cross.mesh.surface_get_material(0) as StandardMaterial3D).emission
	var cross_reach: float = cross.mesh.get_aabb().size.x
	var look_now: Dictionary = map.look()
	map.free()
	if line_glow != look_now["route_color"] or cross_glow != look_now["blocked_color"]:
		return "route glows %s and cross %s, the look says %s and %s" % [line_glow, cross_glow, look_now["route_color"], look_now["blocked_color"]]
	# Each diagonal bar of length s spans s / sqrt(3) per axis, plus its width.
	var want_reach: float = float(look_now["blocked_size_m"]) / sqrt(3.0)
	if cross_reach < want_reach or cross_reach > want_reach + float(look_now["route_width_m"]) * 2.0:
		return "cross spans %s m, want about %s m from blocked_size_m" % [cross_reach, want_reach]
	return ""


func test_a_look_file_without_the_route_keys_still_loads_and_bad_ones_are_named() -> String:
	var old: Dictionary = MapLook.parse(OLD_LOOK)
	if old.has("error"):
		return "a look file without the route keys was rejected: %s" % old["error"]
	if old["route_width_m"] != MapLook.FALLBACK["route_width_m"]:
		return "route_width_m %s, want the built-in" % old["route_width_m"]
	var cases: Dictionary = {
		OLD_LOOK.replace("}", ', "route_color": [1.0, 1.0]}'): "route_color",
		OLD_LOOK.replace("}", ', "route_width_m": 0.5}'): "route_width_m",
		OLD_LOOK.replace("}", ', "blocked_size_m": true}'): "blocked_size_m",
		OLD_LOOK.replace("}", ', "blocked_color": [2.0, 0.0, 0.0]}'): "blocked_color",
	}
	for text: String in cases:
		var look: Dictionary = MapLook.parse(text)
		if str(look.get("error", "")).find(str(cases[text])) < 0:
			return "'%s' gave %s, want an error naming %s" % [text, look, cases[text]]
	return ""
