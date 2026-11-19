extends RefCounted

## Reloading the map hologram's look (#561, MAP-1, ARC-4): `load_look` re-clamps
## the zoom to the limits now in force and re-places every marker at once, so
## the hologram never sits outside the limits its own look file states; a look
## whose limits hold the zoom leaves it alone; `MapLook.load_file` reports a
## missing or rejected file and hands back the built-in look.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SCRATCH_PATH: String = "user://test_map_look_reload.json"
const EPSILON: float = 1e-4
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


## Writes `OLD_LOOK` with `extra` keys added to the scratch file.
func _write_look(extra: Dictionary) -> void:
	var data: Dictionary = JSON.parse_string(OLD_LOOK)
	data.merge(extra, true)
	var file: FileAccess = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _remove_scratch() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))


## A g2 map with ship, exit, reactor, route and fire placed, zoomed to `factor`.
func _zoomed_map(level: LevelDef, factor: float) -> MapHologram:
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0, 1])
	var start: Vector3 = level.start_position()
	map.set_ship_position(start + Vector3(0.0, 0.0, -3.0))
	map.set_markers(start + Vector3(1.0, 0.0, -2.0), start + Vector3(0.0, -3.0, -20.0), true)
	map.show_route(PackedVector3Array([start, start + Vector3(0.0, 0.0, -10.0)]), PackedVector3Array())
	map.show_fires(PackedVector3Array([start + Vector3(0.0, 1.0, -5.0)]), PackedFloat32Array([0.5]))
	map.set_zoom(factor)
	return map


func _positions(map: MapHologram) -> Array[Vector3]:
	return [map.marker_position(), map.exit_marker_position(), map.reactor_marker_position(),
			map.fires().marker_positions()[0]]


func test_a_narrower_look_re_clamps_the_zoom_and_re_places_at_once() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = _zoomed_map(level, 3.0)
	var at_three: Array[Vector3] = _positions(map)
	_write_look({"max_zoom": 2.0})
	var error: String = map.load_look(SCRATCH_PATH)
	_remove_scratch()
	var zoomed: float = map.zoom()
	var after: Array[Vector3] = _positions(map)
	var lines_scale: Vector3 = map.get_node(MapHologram.LINES_NAME).scale
	map.free()
	if error != "":
		return "the narrower look was rejected: %s" % error
	if absf(zoomed - 2.0) > EPSILON:
		return "after a look with max_zoom 2 the zoom is %s, want 2" % zoomed
	if lines_scale.distance_to(Vector3.ONE * 2.0) > EPSILON:
		return "the lines are scaled %s, want 2" % lines_scale
	# Zoom scales about the hand anchor, so going from 3 to 2 scales by 2/3.
	for i: int in at_three.size():
		var want: Vector3 = at_three[i] * (2.0 / 3.0)
		if after[i].distance_to(want) > EPSILON:
			return "marker %d is at %s, want %s at zoom 2 without a set_zoom" % [i, after[i], want]
	return ""


func test_a_rejected_look_re_clamps_to_the_built_in_limits() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	_write_look({"min_zoom": 0.2, "max_zoom": 5.0})
	map.load_look(SCRATCH_PATH)
	map.build(level.union, [0])
	map.set_zoom(5.0)
	var wide: float = map.zoom()
	_write_look({"max_zoom": "big"})
	var error: String = map.load_look(SCRATCH_PATH)
	_remove_scratch()
	var zoomed: float = map.zoom()
	map.free()
	if absf(wide - 5.0) > EPSILON:
		return "the wide look let the zoom reach only %s, want 5" % wide
	if not error.contains("max_zoom"):
		return "a bad max_zoom gave error \"%s\", want it named" % error
	if absf(zoomed - float(MapLook.FALLBACK["max_zoom"])) > EPSILON:
		return "after a rejected look the zoom is %s, want the built-in max %s" % [zoomed, MapLook.FALLBACK["max_zoom"]]
	return ""


func test_a_look_whose_limits_hold_the_zoom_leaves_it_unchanged() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = _zoomed_map(level, 1.5)
	var before: Array[Vector3] = _positions(map)
	_write_look({"min_zoom": 0.25, "max_zoom": 2.0})
	var error: String = map.load_look(SCRATCH_PATH)
	_remove_scratch()
	var zoomed: float = map.zoom()
	var after: Array[Vector3] = _positions(map)
	map.free()
	if error != "":
		return "the look was rejected: %s" % error
	if absf(zoomed - 1.5) > EPSILON:
		return "a look holding 1.5 moved the zoom to %s" % zoomed
	for i: int in before.size():
		if after[i].distance_to(before[i]) > EPSILON:
			return "marker %d moved from %s to %s" % [i, before[i], after[i]]
	return ""


func test_load_file_reports_a_missing_or_rejected_file_with_the_built_in_look() -> String:
	var missing: Dictionary = MapLook.load_file("user://no_such_map_look.json")
	if missing["look"] != MapLook.FALLBACK or not String(missing["error"]).contains("file not found"):
		return "a missing file gave %s, want the built-in look and \"file not found\"" % missing
	_write_look({"fire_size_m": 9.0})
	var rejected: Dictionary = MapLook.load_file(SCRATCH_PATH)
	_write_look({"fire_size_m": 0.02})
	var accepted: Dictionary = MapLook.load_file(SCRATCH_PATH)
	_remove_scratch()
	if rejected["look"] != MapLook.FALLBACK or not String(rejected["error"]).contains(SCRATCH_PATH) \
			or not String(rejected["error"]).contains("fire_size_m"):
		return "a bad fire_size_m gave %s, want the built-in look and an error naming path and key" % rejected
	if accepted["error"] != "" or absf(float(accepted["look"]["fire_size_m"]) - 0.02) > EPSILON:
		return "a good file gave %s, want its fire_size_m 0.02 and no error" % accepted
	return ""


func test_the_shipped_look_loads_and_keeps_the_start_zoom() -> String:
	var map: MapHologram = MapHologram.new()
	var error: String = map.load_look()
	var zoomed: float = map.zoom()
	map.free()
	if error != "":
		return "the shipped look was rejected: %s" % error
	if absf(zoomed - MapZoom.START) > EPSILON:
		return "a fresh map with the shipped look has zoom %s, want %s" % [zoomed, MapZoom.START]
	return ""
