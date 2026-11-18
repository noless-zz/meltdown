extends RefCounted

## Fire marks only in explored tunnels (#562, MAP-1, MAP-2, ARC-4): with the
## look's `fires_explored_only` on, a fire in an explored box is marked and one
## outside is not; a rebuild that explores its box marks it without another
## `show_fires`; with the switch off both are marked; the key is optional,
## defaults to true and must be a bool.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SCRATCH_PATH: String = "user://test_map_fires_explored.json"
const EPSILON: float = 1e-4
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _centre(box: BoxBounds) -> Vector3:
	return (box.min_corner + box.max_corner) / 2.0


## Index of the first box whose centre box 0 does not hold, or -1.
func _outside_box(union: BoxUnion) -> int:
	for index: int in range(1, union.boxes.size()):
		if not union.boxes[0].holds(_centre(union.boxes[index]), 0.0):
			return index
	return -1


func _fit(map: MapHologram, union: BoxUnion, explored: Array[int]) -> Transform3D:
	return MapHologram.fit_transform(MapWireframe.segments(union, explored), float(map.look()["size_m"]))


## A g2 map explored in box 0 with one fire there and one in box `outside`.
func _map_with_two_fires(level: LevelDef, outside: int) -> MapHologram:
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	map.show_fires(PackedVector3Array([_centre(level.union.boxes[0]), _centre(level.union.boxes[outside])]),
			PackedFloat32Array([0.5, 0.5]))
	return map


func _write_look(extra: Dictionary) -> void:
	var data: Dictionary = JSON.parse_string(OLD_LOOK)
	data.merge(extra, true)
	var file: FileAccess = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _remove_scratch() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))


func test_only_the_fire_in_an_explored_box_is_marked() -> String:
	var level: LevelDef = _level()
	if level.error != "":
		return "g2 level did not load: %s" % level.error
	var outside: int = _outside_box(level.union)
	if outside < 0:
		return "g2 has no box outside box 0"
	var map: MapHologram = _map_with_two_fires(level, outside)
	var on: bool = map.look()["fires_explored_only"]
	var at: PackedVector3Array = map.fires().marker_positions()
	var want: Vector3 = _fit(map, level.union, [0]) * _centre(level.union.boxes[0])
	map.free()
	if not on:
		return "the shipped look does not mark fires in explored space only"
	if at.size() != 1:
		return "%d fire markers with one fire explored, want 1" % at.size()
	if at[0].distance_to(want) > EPSILON:
		return "the marker is at %s, want the explored fire at %s" % [at[0], want]
	return ""


func test_a_rebuild_that_explores_the_box_marks_its_fire() -> String:
	var level: LevelDef = _level()
	var outside: int = _outside_box(level.union)
	var map: MapHologram = _map_with_two_fires(level, outside)
	var before: int = map.fires().marker_count()
	var explored: Array[int] = [0, outside]
	map.build(level.union, explored)
	var at: PackedVector3Array = map.fires().marker_positions()
	var fit: Transform3D = _fit(map, level.union, explored)
	map.free()
	if before != 1:
		return "%d markers before the rebuild, want 1" % before
	if at.size() != 2:
		return "%d markers after exploring the fire's box, want 2" % at.size()
	if at[1].distance_to(fit * _centre(level.union.boxes[outside])) > EPSILON:
		return "the newly explored fire is at %s" % at[1]
	return ""


func test_the_switch_off_marks_every_fire() -> String:
	var level: LevelDef = _level()
	var outside: int = _outside_box(level.union)
	_write_look({"fires_explored_only": false})
	var map: MapHologram = MapHologram.new()
	var error: String = map.load_look(SCRATCH_PATH)
	_remove_scratch()
	map.build(level.union, [0])
	map.show_fires(PackedVector3Array([_centre(level.union.boxes[0]), _centre(level.union.boxes[outside])]),
			PackedFloat32Array([0.5, 0.5]))
	var count: int = map.fires().marker_count()
	map.free()
	if error != "":
		return "the look was rejected: %s" % error
	if count != 2:
		return "%d markers with the switch off, want 2" % count
	return ""


func test_turning_the_switch_on_by_reloading_hides_the_unexplored_fire_at_once() -> String:
	var level: LevelDef = _level()
	var outside: int = _outside_box(level.union)
	_write_look({"fires_explored_only": false})
	var map: MapHologram = MapHologram.new()
	map.load_look(SCRATCH_PATH)
	_remove_scratch()
	map.build(level.union, [0])
	map.show_fires(PackedVector3Array([_centre(level.union.boxes[0]), _centre(level.union.boxes[outside])]),
			PackedFloat32Array([0.5, 0.5]))
	var off: int = map.fires().marker_count()
	_write_look({"fires_explored_only": true})
	map.load_look(SCRATCH_PATH)
	_remove_scratch()
	var on: int = map.fires().marker_count()
	map.free()
	if off != 2 or on != 1:
		return "%d then %d markers, want 2 with the switch off and 1 with it on" % [off, on]
	return ""


func test_inside_keeps_order_and_radii() -> String:
	var boxes: Array[AABB] = [AABB(Vector3.ZERO, Vector3.ONE * 2.0), AABB(Vector3(10.0, 0.0, 0.0), Vector3.ONE)]
	var kept: Array = MapFires.inside(
		PackedVector3Array([Vector3(10.5, 0.5, 0.5), Vector3(5.0, 0.0, 0.0), Vector3.ONE]),
		PackedFloat32Array([3.0, 2.0]), boxes)
	if kept[0] != PackedVector3Array([Vector3(10.5, 0.5, 0.5), Vector3.ONE]):
		return "kept centres %s" % [kept[0]]
	if kept[1] != PackedFloat32Array([3.0, 0.0]):
		return "kept radii %s" % [kept[1]]
	return ""


func test_the_key_is_optional_defaults_on_and_must_be_a_bool() -> String:
	var old: Dictionary = MapLook.parse(OLD_LOOK)
	if old.has("error") or old["fires_explored_only"] != true:
		return "a look without the key gives %s, want fires_explored_only true" % [old]
	var data: Dictionary = JSON.parse_string(OLD_LOOK)
	data["fires_explored_only"] = false
	var off: Dictionary = MapLook.parse(JSON.stringify(data))
	if off.has("error") or off["fires_explored_only"] != false:
		return "false was not kept: %s" % [off]
	for bad: Variant in [1, 0, "true"]:
		data["fires_explored_only"] = bad
		var rejected: Dictionary = MapLook.parse(JSON.stringify(data))
		if not rejected.has("error") or not str(rejected["error"]).contains("fires_explored_only"):
			return "%s was not rejected by name: %s" % [bad, rejected]
	return ""
