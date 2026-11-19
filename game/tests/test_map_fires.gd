extends RefCounted

## Burning fire entries on the map hologram (#519, MAP-2, RUN-4): two fires are
## two markers in one draw call at the fitted positions; empty arrays remove
## them; a re-fit moves them; the route and blocked markers stay as they were;
## the look comes from the look file and stands apart from the other markers.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const EPSILON: float = 1e-4
## Colours closer than this (summed over r, g, b) are too alike to tell apart.
const MIN_COLOR_DISTANCE: float = 0.5
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _all(level: LevelDef) -> Array[int]:
	var all: Array[int] = []
	for i: int in level.union.boxes.size():
		all.append(i)
	return all


func _fit(map: MapHologram, level: LevelDef, explored: Array[int]) -> Transform3D:
	return MapHologram.fit_transform(MapWireframe.segments(level.union, explored), float(map.look()["size_m"]))


func _fires(level: LevelDef) -> PackedVector3Array:
	var start: Vector3 = level.start_position()
	return PackedVector3Array([start + Vector3(0.0, 0.0, -6.0), start + Vector3(2.0, 1.0, -3.0)])


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func test_two_fires_are_two_markers_in_one_draw_call_at_the_fitted_positions() -> String:
	var level: LevelDef = _level()
	if level.error != "":
		return "g2 level did not load: %s" % level.error
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var fit: Transform3D = _fit(map, level, [0])
	var centres: PackedVector3Array = _fires(level)
	map.show_fires(centres, PackedFloat32Array([0.5, 0.5]))
	var count: int = map.fires().marker_count()
	var at: PackedVector3Array = map.fires().marker_positions()
	var mesh: ArrayMesh = map.fires().mesh_node().mesh as ArrayMesh
	var surfaces: int = mesh.get_surface_count() if mesh != null else 0
	var glow: Color = (mesh.surface_get_material(0) as StandardMaterial3D).emission if mesh != null else Color.BLACK
	var look: Dictionary = map.look()
	map.free()
	if count != 2 or at.size() != 2:
		return "%d markers at %s, want 2" % [count, at]
	if surfaces != 1:
		return "fires drawn as %d surfaces, want one draw call" % surfaces
	for i: int in 2:
		if at[i].distance_to(fit * centres[i]) > EPSILON:
			return "fire %d at %s, want %s" % [i, at[i], fit * centres[i]]
	if glow != look["fire_color"]:
		return "fires glow %s, the look says %s" % [glow, look["fire_color"]]
	return ""


func test_a_marker_spans_the_fitted_fire_but_never_less_than_fire_size() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var scale_fit: float = _fit(map, level, [0]).basis.get_scale().x
	var least: float = float(map.look()["fire_size_m"])
	# One fire too small to see at the map's scale, one far larger than the floor.
	var big: float = least * 4.0 / scale_fit
	map.show_fires(_fires(level), PackedFloat32Array([0.0, big]))
	var sizes: PackedFloat32Array = map.fires().marker_sizes()
	var span: float = (map.fires().mesh_node().mesh as ArrayMesh).get_aabb().size.y
	map.free()
	if absf(sizes[0] - least) > 1e-6:
		return "small fire spans %s, want fire_size_m %s" % [sizes[0], least]
	if absf(sizes[1] - big * 2.0 * scale_fit) > 1e-5:
		return "big fire spans %s, want its fitted diameter %s" % [sizes[1], big * 2.0 * scale_fit]
	if span < sizes[1] - 1e-5:
		return "mesh spans %s m, smaller than the big marker %s" % [span, sizes[1]]
	return ""


func test_empty_arrays_remove_the_fires_and_a_missing_radius_counts_as_zero() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	map.show_fires(_fires(level), PackedFloat32Array())
	var without_radii: int = map.fires().marker_count()
	var sizes: PackedFloat32Array = map.fires().marker_sizes()
	map.show_fires(PackedVector3Array(), PackedFloat32Array())
	var after: int = map.fires().marker_count()
	var mesh: Mesh = map.fires().mesh_node().mesh
	var positions: int = map.fires().marker_positions().size()
	var least: float = float(map.look()["fire_size_m"])
	map.free()
	if without_radii != 2 or absf(sizes[1] - least) > 1e-6:
		return "fires without radii drew %d markers sized %s, want 2 at fire_size_m" % [without_radii, sizes]
	if after != 0 or mesh != null or positions != 0:
		return "after clearing: %d markers, mesh %s" % [after, mesh]
	return ""


func test_the_fires_are_refitted_when_more_boxes_are_explored() -> String:
	var level: LevelDef = _level()
	var all: Array[int] = _all(level)
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var centres: PackedVector3Array = _fires(level)
	map.show_fires(centres, PackedFloat32Array([0.5, 0.5]))
	var before: PackedVector3Array = map.fires().marker_positions()
	map.build(level.union, all)
	var fit: Transform3D = _fit(map, level, all)
	var after: PackedVector3Array = map.fires().marker_positions()
	map.free()
	if after.size() != 2:
		return "%d fires after exploring all, want 2" % after.size()
	if before[0].distance_to(after[0]) < EPSILON:
		return "fire did not move when the map re-fitted; the test needs a different fit"
	for i: int in 2:
		if after[i].distance_to(fit * centres[i]) > EPSILON:
			return "fire %d at %s after exploring all, want %s" % [i, after[i], fit * centres[i]]
	return ""


func test_the_route_and_blocked_markers_are_unchanged_by_fires() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var start: Vector3 = level.start_position()
	map.show_route(PackedVector3Array([start, start + Vector3(0.0, 0.0, -6.0)]),
			PackedVector3Array([start + Vector3(0.0, 3.0, -6.0)]))
	var ends: PackedVector3Array = map.route().segment_ends()
	var crosses: PackedVector3Array = map.route().blocked_positions()
	var label: String = map.route().distance_shown()
	map.show_fires(_fires(level), PackedFloat32Array([0.5, 0.5]))
	var ends_with: PackedVector3Array = map.route().segment_ends()
	var crosses_with: PackedVector3Array = map.route().blocked_positions()
	var label_with: String = map.route().distance_shown()
	map.show_fires(PackedVector3Array(), PackedFloat32Array())
	var crosses_after: PackedVector3Array = map.route().blocked_positions()
	map.clear_route()
	var fires_after_route_cleared: int = map.fires().marker_count()
	map.show_fires(_fires(level), PackedFloat32Array())
	map.clear_route()
	var fires_kept: int = map.fires().marker_count()
	map.free()
	if ends_with != ends or crosses_with != crosses or label_with != label or crosses_after != crosses:
		return "route %s / %s / '%s' became %s / %s / '%s' with fires" % [ends, crosses, label, ends_with,
				crosses_with, label_with]
	if fires_after_route_cleared != 0 or fires_kept != 2:
		return "fires after clearing: %d, after clear_route: %d, want 0 and 2" % [fires_after_route_cleared, fires_kept]
	return ""


func test_the_fire_look_keys_load_fall_back_stand_apart_and_bad_ones_are_named() -> String:
	var shipped: Dictionary = MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if shipped.has("error"):
		return "map_look.json rejected: %s" % shipped["error"]
	for key: String in ["fire_color", "fire_size_m"]:
		if not shipped.has(key) or shipped[key] != MapLook.FALLBACK[key]:
			return "map_look.json %s is %s, want it shipped and equal to the built-in %s" % [key, shipped.get(key), MapLook.FALLBACK[key]]
		if MapLook.parse(OLD_LOOK)[key] != MapLook.FALLBACK[key]:
			return "a look file without %s did not keep the built-in" % key
	for look: Dictionary in [shipped, MapLook.FALLBACK]:
		for other: String in ["line_color", "marker_color", "exit_color", "reactor_color", "route_color",
				"blocked_color", "distance_color"]:
			if _distance(look["fire_color"], look[other]) < MIN_COLOR_DISTANCE:
				return "fire_color %s is too close to %s %s" % [look["fire_color"], other, look[other]]
	var cases: Dictionary = {
		OLD_LOOK.replace("}", ', "fire_color": [1.0, 1.0]}'): "fire_color",
		OLD_LOOK.replace("}", ', "fire_color": [1.0, 2.0, 0.0]}'): "fire_color",
		OLD_LOOK.replace("}", ', "fire_size_m": 0.5}'): "fire_size_m",
		OLD_LOOK.replace("}", ', "fire_size_m": true}'): "fire_size_m",
		OLD_LOOK.replace("}", ', "fire_size_m": 0.001}'): "fire_size_m",
	}
	for text: String in cases:
		var look: Dictionary = MapLook.parse(text)
		if str(look.get("error", "")).find(str(cases[text])) < 0:
			return "'%s' gave %s, want an error naming %s" % [text, look, cases[text]]
	return ""


## The split keeps the map node under the size limit, and the fire view names
## no simulation class nor any layer above it (MP-2, ARC-3).
func test_the_map_stays_small_and_the_fire_view_reads_no_simulation_class() -> String:
	var lines: int = FileAccess.get_file_as_string("res://xr/map_hologram.gd").split("\n").size()
	if lines >= 300:
		return "map_hologram.gd has %d lines, want under 300" % lines
	var source: String = FileAccess.get_file_as_string("res://view/map_fires.gd")
	for root: String in ["res://core", "res://xr", "res://meta", "res://net"]:
		for file: String in DirAccess.get_files_at(root):
			if not file.ends_with(".gd"):
				continue
			var head: String = FileAccess.get_file_as_string("%s/%s" % [root, file]).get_slice("\n", 0)
			if head.begins_with("class_name "):
				var class_id: String = head.trim_prefix("class_name ").strip_edges()
				if RegEx.create_from_string("\\b%s\\b" % class_id).search(source) != null:
					return "map_fires.gd names %s from %s" % [class_id, root]
	return ""
