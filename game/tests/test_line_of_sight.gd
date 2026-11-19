extends RefCounted

## `LineOfSight`: where a line leaves the open space of a box union (#615,
## CMB-2, CMB-3, GEN-5). A line crosses from one box into another only through
## the volume they share; boxes face to face, or apart, have a wall between.


func _union(boxes: Array[BoxBounds]) -> BoxUnion:
	return BoxUnion.new(boxes)


## Two corridors along x, side by side on z with a 2 m wall between them.
func _parallel(gap: float) -> Array[BoxBounds]:
	var near: BoxBounds = BoxBounds.new(Vector3(0.0, 0.0, 0.0), Vector3(40.0, 6.0, 6.0))
	var far: BoxBounds = BoxBounds.new(Vector3(0.0, 0.0, 6.0 + gap), Vector3(40.0, 6.0, 12.0 + gap))
	return [near, far]


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-4


func test_null_walls_are_open_everywhere() -> String:
	if LineOfSight.exit_fraction(null, Vector3.ZERO, Vector3(100.0, 5.0, -3.0)) != -1.0:
		return "a line in open space was cut"
	return ""


func test_a_line_inside_one_box_is_clear() -> String:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3.ZERO, Vector3(10.0, 10.0, 10.0))]
	var walls: BoxUnion = _union(boxes)
	if not LineOfSight.clear(walls, Vector3(1.0, 1.0, 1.0), Vector3(9.0, 9.0, 9.0)):
		return "a diagonal inside the box was cut"
	# Ending exactly on a wall still counts as inside, as `BoxUnion.holds` does.
	if not LineOfSight.clear(walls, Vector3(5.0, 5.0, 5.0), Vector3(10.0, 5.0, 5.0)):
		return "a line ending on the wall was cut"
	if not LineOfSight.clear(walls, Vector3(5.0, 5.0, 5.0), Vector3(5.0, 5.0, 5.0)):
		return "a point inside was not clear"
	return ""


func test_a_line_leaving_one_box_is_cut_at_the_wall() -> String:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3.ZERO, Vector3(10.0, 10.0, 10.0))]
	var at: float = LineOfSight.exit_fraction(_union(boxes), Vector3(5.0, 5.0, 5.0), Vector3(15.0, 5.0, 5.0))
	if not _near(at, 0.5):
		return "cut at %f, expected 0.5" % at
	return ""


func test_a_line_starting_outside_is_cut_at_once() -> String:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3.ZERO, Vector3(10.0, 10.0, 10.0))]
	var at: float = LineOfSight.exit_fraction(_union(boxes), Vector3(-1.0, 5.0, 5.0), Vector3(5.0, 5.0, 5.0))
	if at != 0.0:
		return "cut at %f, expected 0.0" % at
	if LineOfSight.exit_fraction(_union(boxes), Vector3(-1.0, 5.0, 5.0), Vector3(-1.0, 5.0, 5.0)) != 0.0:
		return "a point outside was clear"
	return ""


func test_parallel_corridors_with_a_wall_between_block_the_line() -> String:
	var walls: BoxUnion = _union(_parallel(2.0))
	var at: float = LineOfSight.exit_fraction(walls, Vector3(20.0, 3.0, 3.0), Vector3(20.0, 3.0, 11.0))
	# Leaves the near corridor at z 6, three eighths of the way.
	if not _near(at, 0.375):
		return "cut at %f, expected 0.375" % at
	return ""


## Generated levels place boxes face to face; that face is a wall too.
func test_corridors_face_to_face_block_the_line() -> String:
	var walls: BoxUnion = _union(_parallel(0.0))
	var at: float = LineOfSight.exit_fraction(walls, Vector3(20.0, 3.0, 3.0), Vector3(20.0, 3.0, 9.0))
	if not _near(at, 0.5):
		return "cut at %f, expected 0.5" % at
	# The same from the other side, in the other box order.
	var swapped: Array[BoxBounds] = _parallel(0.0)
	swapped.reverse()
	at = LineOfSight.exit_fraction(_union(swapped), Vector3(20.0, 3.0, 9.0), Vector3(20.0, 3.0, 3.0))
	if not _near(at, 0.5):
		return "reversed: cut at %f, expected 0.5" % at
	return ""


func test_a_connector_overlapping_both_opens_the_line() -> String:
	var boxes: Array[BoxBounds] = _parallel(2.0)
	boxes.append(BoxBounds.new(Vector3(18.0, 0.0, 4.0), Vector3(22.0, 6.0, 10.0)))
	var walls: BoxUnion = _union(boxes)
	if not LineOfSight.clear(walls, Vector3(20.0, 3.0, 3.0), Vector3(20.0, 3.0, 11.0)):
		return "the line through the connector was cut"
	# Beside the connector the wall is still there.
	var at: float = LineOfSight.exit_fraction(walls, Vector3(10.0, 3.0, 3.0), Vector3(10.0, 3.0, 11.0))
	if not _near(at, 0.375):
		return "beside the connector: cut at %f, expected 0.375" % at
	# A slanted line that leaves the near corridor beside the connector.
	if LineOfSight.clear(walls, Vector3(10.0, 3.0, 3.0), Vector3(20.0, 3.0, 11.0)):
		return "a slanted line through the wall beside the connector was clear"
	return ""


## An L of two corridors: round the corner there is no line, along each arm
## and across the shared corner there is.
func test_an_l_corner_hides_what_is_round_it() -> String:
	var down: BoxBounds = BoxBounds.new(Vector3(-3.0, -3.0, -30.0), Vector3(3.0, 3.0, 0.0))
	var across: BoxBounds = BoxBounds.new(Vector3(-3.0, -3.0, -30.0), Vector3(40.0, 3.0, -24.0))
	var boxes: Array[BoxBounds] = [down, across]
	var walls: BoxUnion = _union(boxes)
	if LineOfSight.clear(walls, Vector3(0.0, 0.0, -2.0), Vector3(30.0, 0.0, -27.0)):
		return "a line through the inside corner was clear"
	if not LineOfSight.clear(walls, Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -27.0)):
		return "the line down the first arm was cut"
	if not LineOfSight.clear(walls, Vector3(0.0, 0.0, -27.0), Vector3(30.0, 0.0, -27.0)):
		return "the line along the second arm was cut"
	# Starts in the shared corner, so both boxes hold it from the first point.
	if not LineOfSight.clear(walls, Vector3(0.0, 0.0, -26.0), Vector3(30.0, 0.0, -25.0)):
		return "a slanted line from the shared corner was cut"
	return ""


func test_same_inputs_give_the_same_answer_whatever_the_box_order() -> String:
	var boxes: Array[BoxBounds] = _parallel(2.0)
	boxes.append(BoxBounds.new(Vector3(18.0, 0.0, 4.0), Vector3(22.0, 6.0, 10.0)))
	var reversed: Array[BoxBounds] = boxes.duplicate()
	reversed.reverse()
	var from: Vector3 = Vector3(5.0, 1.0, 1.0)
	for x: int in range(0, 41, 4):
		for z: int in range(0, 15, 2):
			var to: Vector3 = Vector3(float(x), 4.0, float(z))
			var a: float = LineOfSight.exit_fraction(_union(boxes), from, to)
			var b: float = LineOfSight.exit_fraction(_union(reversed), from, to)
			if a != b:
				return "to %s: %f in one order, %f in the other" % [to, a, b]
	return ""
