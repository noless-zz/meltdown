extends RefCounted

## The shortest way out through the level's boxes (#337, RUN-5, ARC-1, ARC-2),
## checked against lengths worked out by hand.

const G2_LEVEL: String = "res://data/levels/g2_level.json"


## A corridor along z (box 0) and a shaft dropping from its far end (box 1).
## They overlap in x -2..2, y -2..0, z -20..-18, an opening centred on (0, -1, -19).
func _corridor_and_shaft() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -2, -20), Vector3(2, 2, 2)),
		BoxBounds.new(Vector3(-2, -22, -22), Vector3(2, 0, -18))]
	return BoxUnion.new(boxes)


func test_inside_one_box_the_path_is_the_straight_line() -> String:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10))]
	var walls: BoxUnion = BoxUnion.new(boxes)
	# 3, 4, 12 metres: 13 m.
	var length: int = EscapePath.length_mm(walls, Vector3(3, 4, -12), Vector3.ZERO)
	if length != 13000:
		return "got %d mm, expected 13000" % length
	if EscapePath.length_mm(walls, Vector3(1, 1, 1), Vector3(1, 1, 1)) != 0:
		return "a point is not 0 mm from itself"
	return ""


func test_across_two_joined_boxes_the_path_bends_at_the_opening() -> String:
	# (0, -20, -20) to the opening (0, -1, -19) is sqrt(19² + 1²) = 19.0263 m, and the
	# opening to (0, 0, 0) is sqrt(1² + 19²) again: 19026 + 19026 mm.
	var length: int = EscapePath.length_mm(_corridor_and_shaft(), Vector3(0, -20, -20), Vector3.ZERO)
	if length != 38052:
		return "got %d mm, expected 38052" % length
	return ""


func test_the_path_is_the_same_both_ways() -> String:
	var walls: BoxUnion = _corridor_and_shaft()
	var there: int = EscapePath.length_mm(walls, Vector3(1, -15, -21), Vector3(-1, 1, -3))
	var back: int = EscapePath.length_mm(walls, Vector3(-1, 1, -3), Vector3(1, -15, -21))
	if there != back or there <= 0:
		return "%d mm there, %d mm back" % [there, back]
	return ""


func test_a_point_outside_every_box_has_no_path() -> String:
	var walls: BoxUnion = _corridor_and_shaft()
	if EscapePath.length_mm(walls, Vector3(50, 0, 0), Vector3.ZERO) != EscapePath.UNREACHABLE:
		return "a path from outside the level"
	if EscapePath.length_mm(walls, Vector3.ZERO, Vector3(50, 0, 0)) != EscapePath.UNREACHABLE:
		return "a path to outside the level"
	return ""


func test_boxes_that_do_not_overlap_are_not_joined() -> String:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
		BoxBounds.new(Vector3(5, -1, -1), Vector3(7, 1, 1))]
	if EscapePath.length_mm(BoxUnion.new(boxes), Vector3(6, 0, 0), Vector3.ZERO) \
			!= EscapePath.UNREACHABLE:
		return "a path between two separate boxes"
	return ""


func test_the_g2_shaft_path_matches_the_hand_computed_length() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return level.error
	# The foot of the shaft (0, -40, -46) lies in boxes 1 and 2; the start lies in box 0
	# only. Boxes 0 and 1 open onto each other around (0, 0, -38): sqrt(40² + 8²) =
	# 40.792 m up the shaft, then 38 m along the entry tunnel.
	var length: int = EscapePath.length_mm(level.union, Vector3(0, -40, -46), Vector3.ZERO)
	if length != 78792:
		return "got %d mm, expected 78792" % length
	return ""


func test_the_same_question_always_gets_the_same_answer() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	var first: int = EscapePath.length_mm(level.union, Vector3(0, -39, -110.5), Vector3.ZERO)
	for i: int in 3:
		if EscapePath.length_mm(level.union, Vector3(0, -39, -110.5), Vector3.ZERO) != first:
			return "the length changed between calls"
	if first <= 78792:
		return "the reactor room is %d mm out, no further than the shaft foot" % first
	return ""

