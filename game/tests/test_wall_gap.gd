extends RefCounted

## The thinnest wall between tunnels (#1240, GEN-3, GEN-5, ARC-1): hand-built
## unions with a known answer.


func _box(from: Vector3, to: Vector3) -> BoxBounds:
	return BoxBounds.new(from, to)


func _union(boxes: Array[BoxBounds]) -> BoxUnion:
	return BoxUnion.new(boxes)


func test_two_parallel_tunnels_half_a_metre_apart_give_half_a_metre() -> String:
	var union: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 40)),
		_box(Vector3(4.5, 0, 10), Vector3(8.5, 4, 30))])
	var found: Dictionary = WallGap.thinnest(union)
	if absf(float(found["gap_m"]) - 0.5) > 1e-4 or found["box_a"] != 0 or found["box_b"] != 1:
		return "expected 0.5 m between boxes 0 and 1, got %s" % found
	return ""


func test_the_thinnest_of_several_walls_is_found_on_any_axis() -> String:
	var union: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 40)),
		_box(Vector3(6, 0, 0), Vector3(10, 4, 40)),
		_box(Vector3(0, 4.75, 0), Vector3(4, 8, 40))])
	var found: Dictionary = WallGap.thinnest(union)
	if absf(float(found["gap_m"]) - 0.75) > 1e-4 or found["box_a"] != 0 or found["box_b"] != 2:
		return "expected 0.75 m between boxes 0 and 2 (on y), got %s" % found
	return ""


func test_overlapping_boxes_are_an_opening_not_a_wall() -> String:
	var overlapping: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 20)),
		_box(Vector3(2, 0, 10), Vector3(12, 4, 14))])
	if WallGap.thinnest(overlapping)["gap_m"] != INF:
		return "two overlapping boxes were counted: %s" % WallGap.thinnest(overlapping)
	return ""


func test_flush_boxes_with_no_doorway_give_a_zero_metre_wall() -> String:
	# BoxUnion keeps a ship in one box at a time, so a flush face with no doorway
	# box across it is a wall of no thickness.
	var touching: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 20)),
		_box(Vector3(4, 0, 5), Vector3(10, 4, 9))])
	var found: Dictionary = WallGap.thinnest(touching)
	if absf(float(found["gap_m"])) > 1e-4 or found["box_a"] != 0 or found["box_b"] != 1:
		return "expected 0 m between flush boxes 0 and 1, got %s" % found
	return ""


func test_flush_boxes_joined_by_a_doorway_are_an_opening() -> String:
	var joined: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 20)),
		_box(Vector3(4, 0, 5), Vector3(10, 4, 9)),
		_box(Vector3(3, 1, 6), Vector3(5, 3, 8))])
	if WallGap.thinnest(joined)["gap_m"] != INF:
		return "a doorway between flush boxes was counted as a wall: %s" % WallGap.thinnest(joined)
	return ""


func test_an_l_shaped_pair_whose_faces_do_not_overlap_is_not_counted() -> String:
	# Apart on x and on z, so no face of one lies across from a face of the other.
	var union: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 20)),
		_box(Vector3(4.5, 0, 20.5), Vector3(24.5, 4, 24.5))])
	var found: Dictionary = WallGap.thinnest(union)
	if found["gap_m"] != INF or found["box_a"] != -1 or found["box_b"] != -1:
		return "an L-shaped pair was counted: %s" % found
	return ""


func test_a_connector_filling_the_space_between_two_ends_is_not_a_wall() -> String:
	# A - C - B in a line: the 0.5 m between A and B is C's air, not rock.
	var union: BoxUnion = _union([_box(Vector3(0, 0, 0), Vector3(4, 4, 10)),
		_box(Vector3(0, 0, 10.5), Vector3(4, 4, 20)),
		_box(Vector3(0, 0, 9), Vector3(4, 4, 11.5))])
	if WallGap.thinnest(union)["gap_m"] != INF:
		return "a connector's air was counted as a wall: %s" % WallGap.thinnest(union)
	# A narrower connector leaves rock across the rest of the faces.
	union.boxes[2] = _box(Vector3(1, 1, 9), Vector3(3, 3, 11.5))
	var found: Dictionary = WallGap.thinnest(union)
	if absf(float(found["gap_m"]) - 0.5) > 1e-4:
		return "the rock beside a narrow connector was not counted: %s" % found
	return ""


func test_the_same_union_always_gives_the_same_answer() -> String:
	var boxes: Array[BoxBounds] = []
	for k: int in 12:
		var at: Vector3 = Vector3(float(k % 4) * 5.3, float(k / 4) * 4.7, float(k % 3) * 2.1)
		boxes.append(_box(at, at + Vector3(4, 4, 12)))
	var first: Dictionary = WallGap.thinnest(_union(boxes))
	for i: int in 3:
		var again: Dictionary = WallGap.thinnest(_union(boxes.duplicate()))
		if again != first:
			return "run %d gave %s, the first %s" % [i, again, first]
	if first["gap_m"] == INF:
		return "the grid of boxes has no wall: %s" % first
	return ""
