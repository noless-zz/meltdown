extends RefCounted

## The exit and reactor markers on the map hologram (#338, MAP-1, MAP-2,
## RUN-3): fitted like the lines, the reactor marker only while it is known,
## re-fitted when more boxes are explored, an older look file without the new
## keys still loads, and the marker colours never read as the ship marker.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SCRATCH_PATH: String = "user://test_map_markers_look.json"
const EPSILON: float = 1e-4
## The look file as it was before #338.
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'
## Colours closer than this (summed over r, g, b) are too alike to tell apart.
const MIN_COLOR_DISTANCE: float = 0.5


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _reactor_position(level: LevelDef) -> Vector3:
	return Vector3(level.reactor.position_mm) / float(RobotSpawn.SCALE)


func _all(union: BoxUnion) -> Array[int]:
	var indices: Array[int] = []
	for i: int in union.boxes.size():
		indices.append(i)
	return indices


func _fit(map: MapHologram, union: BoxUnion, explored: Array[int]) -> Transform3D:
	return MapHologram.fit_transform(MapWireframe.segments(union, explored), float(map.look()["size_m"]))


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_both_markers_sit_at_the_fitted_positions_for_g2() -> String:
	var level: LevelDef = _level()
	if level.error != "" or level.reactor == null:
		return "g2 level did not load with a reactor: %s" % level.error
	var explored: Array[int] = [0]
	var map: MapHologram = MapHologram.new()
	map.build(level.union, explored)
	var fit: Transform3D = _fit(map, level.union, explored)
	map.set_markers(level.start_position(), _reactor_position(level), true)
	map.set_ship_position(level.start_position())
	var exit_at: Vector3 = map.exit_marker_position()
	var reactor_at: Vector3 = map.reactor_marker_position()
	var ship_at: Vector3 = map.marker_position()
	var shown: bool = map.exit_marker_shown() and map.reactor_marker_shown()
	map.free()
	if not shown:
		return "a marker is hidden although both were set and the reactor is known"
	if exit_at.distance_to(fit * level.start_position()) > EPSILON:
		return "exit marker at %s, want %s" % [exit_at, fit * level.start_position()]
	if reactor_at.distance_to(fit * _reactor_position(level)) > EPSILON:
		return "reactor marker at %s, want %s" % [reactor_at, fit * _reactor_position(level)]
	if exit_at.distance_to(ship_at) > EPSILON:
		return "ship at the entrance gave %s, exit marker %s: not fitted alike" % [ship_at, exit_at]
	return ""


func test_the_reactor_marker_shows_only_while_known() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, _all(level.union))
	var before: Array[bool] = [map.exit_marker_shown(), map.reactor_marker_shown()]
	map.set_markers(level.start_position(), _reactor_position(level), false)
	var unknown: Array[bool] = [map.exit_marker_shown(), map.reactor_marker_shown()]
	map.set_markers(level.start_position(), _reactor_position(level), true)
	var known: Array[bool] = [map.exit_marker_shown(), map.reactor_marker_shown()]
	map.build(level.union, _all(level.union))
	var rebuilt: Array[bool] = [map.exit_marker_shown(), map.reactor_marker_shown()]
	map.free()
	if before != [false, false]:
		return "markers %s before set_markers, want both hidden" % [before]
	if unknown != [true, false]:
		return "with the reactor unknown: exit %s, reactor %s" % unknown
	if known != [true, true] or rebuilt != [true, true]:
		return "with the reactor known: %s, after a rebuild %s" % [known, rebuilt]
	return ""


func test_markers_are_refitted_when_more_boxes_are_explored() -> String:
	var level: LevelDef = _level()
	var first: Array[int] = [0]
	var all: Array[int] = _all(level.union)
	var map: MapHologram = MapHologram.new()
	map.build(level.union, first)
	map.set_markers(level.start_position(), _reactor_position(level), true)
	var old_reactor: Vector3 = map.reactor_marker_position()
	map.build(level.union, all)
	var fit: Transform3D = _fit(map, level.union, all)
	var exit_at: Vector3 = map.exit_marker_position()
	var reactor_at: Vector3 = map.reactor_marker_position()
	map.free()
	if exit_at.distance_to(fit * level.start_position()) > EPSILON:
		return "exit marker at %s after exploring all, want %s" % [exit_at, fit * level.start_position()]
	if reactor_at.distance_to(fit * _reactor_position(level)) > EPSILON:
		return "reactor marker at %s after exploring all, want %s" % [reactor_at, fit * _reactor_position(level)]
	if reactor_at.distance_to(old_reactor) < EPSILON:
		return "the reactor marker did not move although the bounds changed"
	return ""


func test_a_look_file_without_the_new_keys_still_loads() -> String:
	_write(OLD_LOOK)
	var map: MapHologram = MapHologram.new()
	var error: String = map.load_look(SCRATCH_PATH)
	var look: Dictionary = map.look()
	map.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	if error != "":
		return "the pre-#338 look file was rejected: %s" % error
	for key: String in MapLook.OPTIONAL_KEYS:
		if look[key] != MapLook.FALLBACK[key]:
			return "%s is %s, want the built-in %s" % [key, look[key], MapLook.FALLBACK[key]]
	if look["size_m"] != 0.25:
		return "the old keys were not read"
	return ""


func test_a_bad_new_key_falls_back_and_names_it() -> String:
	var cases: Dictionary = {
		OLD_LOOK.replace("}", ', "exit_color": [0.3, 1.0]}'): "exit_color",
		OLD_LOOK.replace("}", ', "reactor_radius_m": 0.5}'): "reactor_radius_m",
		OLD_LOOK.replace("}", ', "exit_radius_m": true}'): "exit_radius_m",
	}
	for text: String in cases:
		var look: Dictionary = MapLook.parse(text)
		if str(look.get("error", "")).find(str(cases[text])) < 0:
			return "'%s' gave %s, want an error naming %s" % [text, look, cases[text]]
	return ""


func test_the_marker_colours_differ_from_the_ship_marker() -> String:
	var shipped: Dictionary = MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if shipped.has("error"):
		return "map_look.json rejected: %s" % shipped["error"]
	if not shipped.has("exit_color") or not shipped.has("reactor_color"):
		return "map_look.json does not carry the marker keys"
	for look: Dictionary in [shipped, MapLook.FALLBACK]:
		var pairs: Array[Array] = [
			["exit_color", "marker_color"], ["reactor_color", "marker_color"], ["exit_color", "reactor_color"],
			["reactor_dead_color", "marker_color"], ["reactor_dead_color", "exit_color"],
		]
		for pair: Array in pairs:
			if _distance(look[pair[0]], look[pair[1]]) < MIN_COLOR_DISTANCE:
				return "%s %s is too close to %s %s" % [pair[0], look[pair[0]], pair[1], look[pair[1]]]
	var map: MapHologram = MapHologram.new()
	map.build(_level().union, [0])
	# The exit is a see-through unshaded cube since #913: its colour is the albedo's.
	var exit_albedo: Color = ((map.get_node(MapHologram.EXIT_NAME) as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D).albedo_color
	var exit_glow: Color = Color(exit_albedo.r, exit_albedo.g, exit_albedo.b)
	var reactor_glow: Color = ((map.get_node(MapHologram.REACTOR_NAME) as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D).emission
	var look_now: Dictionary = map.look()
	map.free()
	if exit_glow != look_now["exit_color"] or reactor_glow != look_now["reactor_color"]:
		return "markers glow %s and %s, the look says %s and %s" % [exit_glow, reactor_glow, look_now["exit_color"], look_now["reactor_color"]]
	return ""
