extends RefCounted

## A fire is marked by its sphere, not its centre (#577, MAP-1, MAP-2, ARC-4):
## with `fires_explored_only` on, a fire centred in rock whose sphere reaches
## into an explored tunnel is marked, since it burns a ship there; one whose
## sphere touches no explored box is not; with the switch off every fire is.

const SCRATCH_PATH: String = "user://test_map_fires_sphere.json"
const EPSILON: float = 1e-4
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'
const BOX: AABB = AABB(Vector3.ZERO, Vector3(10.0, 4.0, 4.0))


## Two tunnels 20 m apart; only the first is explored in these tests.
func _union() -> BoxUnion:
	var boxes: Array[BoxBounds] = [
		BoxBounds.new(Vector3.ZERO, Vector3(10.0, 4.0, 4.0)),
		BoxBounds.new(Vector3(30.0, 0.0, 0.0), Vector3(40.0, 4.0, 4.0)),
	]
	return BoxUnion.new(boxes)


## Fires: centre in box 0; centre in rock 1 m off box 0 with radius 2 (reaches
## in); centre in rock 5 m off box 0 with radius 2 (touches no box).
func _fires() -> Array:
	return [PackedVector3Array([Vector3(5.0, 2.0, 2.0), Vector3(11.0, 2.0, 2.0), Vector3(15.0, 2.0, 2.0)]),
			PackedFloat32Array([0.5, 2.0, 2.0])]


func _write_look(extra: Dictionary) -> void:
	var data: Dictionary = JSON.parse_string(OLD_LOOK)
	data.merge(extra, true)
	var file: FileAccess = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _remove_scratch() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))


func test_a_fire_centred_in_the_box_is_kept() -> String:
	var kept: Array = MapFires.inside(PackedVector3Array([Vector3(5.0, 2.0, 2.0)]),
			PackedFloat32Array([0.5]), [BOX])
	if kept[0].size() != 1:
		return "a fire centred in the box was dropped"
	return ""


func test_a_fire_centred_outside_whose_sphere_reaches_in_is_kept() -> String:
	# Off a face, and off a corner where only the sphere's edge crosses in.
	var centres: PackedVector3Array = PackedVector3Array([Vector3(11.0, 2.0, 2.0), Vector3(11.0, 5.0, 5.0)])
	var kept: Array = MapFires.inside(centres, PackedFloat32Array([2.0, 1.8]), [BOX])
	if kept[0] != centres:
		return "kept %s, want both fires reaching into the box" % [kept[0]]
	if kept[1] != PackedFloat32Array([2.0, 1.8]):
		return "kept radii %s" % [kept[1]]
	return ""


func test_a_sphere_touching_no_box_is_dropped() -> String:
	# Off the corner (11, 5, 5) is sqrt(3) = 1.73 m from the box: radius 1.7 misses.
	var kept: Array = MapFires.inside(
			PackedVector3Array([Vector3(15.0, 2.0, 2.0), Vector3(11.0, 5.0, 5.0), Vector3(-3.0, 2.0, 2.0)]),
			PackedFloat32Array([2.0, 1.7]), [BOX])
	if not kept[0].is_empty():
		return "kept %s, want no fire" % [kept[0]]
	return ""


func test_a_sphere_just_touching_the_box_is_kept() -> String:
	var kept: Array = MapFires.inside(PackedVector3Array([Vector3(12.0, 2.0, 2.0)]),
			PackedFloat32Array([2.0]), [BOX])
	if kept[0].size() != 1:
		return "a sphere touching the face was dropped"
	return ""


func test_a_negative_radius_counts_as_zero() -> String:
	var kept: Array = MapFires.inside(PackedVector3Array([Vector3(5.0, 2.0, 2.0), Vector3(10.5, 2.0, 2.0)]),
			PackedFloat32Array([-1.0, -1.0]), [BOX])
	if kept[0] != PackedVector3Array([Vector3(5.0, 2.0, 2.0)]):
		return "kept %s, want only the fire centred in the box" % [kept[0]]
	return ""


func test_the_map_marks_a_fire_reaching_into_an_explored_tunnel() -> String:
	var map: MapHologram = MapHologram.new()
	var union: BoxUnion = _union()
	var explored: Array[int] = [0]
	map.build(union, explored)
	var fires: Array = _fires()
	map.show_fires(fires[0], fires[1])
	var on: bool = map.look()["fires_explored_only"]
	var at: PackedVector3Array = map.fires().marker_positions()
	var fit: Transform3D = MapHologram.fit_transform(MapWireframe.segments(union, explored),
			float(map.look()["size_m"]))
	map.free()
	if not on:
		return "the shipped look does not mark fires in explored space only"
	if at.size() != 2:
		return "%d markers, want the fire in the tunnel and the one reaching in" % at.size()
	if at[1].distance_to(fit * Vector3(11.0, 2.0, 2.0)) > EPSILON:
		return "the second marker is at %s, want the fire reaching in" % at[1]
	return ""


func test_the_switch_off_marks_every_fire() -> String:
	_write_look({"fires_explored_only": false})
	var map: MapHologram = MapHologram.new()
	var error: String = map.load_look(SCRATCH_PATH)
	_remove_scratch()
	map.build(_union(), [0])
	var fires: Array = _fires()
	map.show_fires(fires[0], fires[1])
	var count: int = map.fires().marker_count()
	map.free()
	if error != "":
		return "the look was rejected: %s" % error
	if count != 3:
		return "%d markers with the switch off, want 3" % count
	return ""
