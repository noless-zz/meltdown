extends RefCounted

## The hologram map's geometry (#313, MAP-1, GEN-5, ARC-1): explored boxes are
## marked by position, each explored box's outline is drawn with openings left
## open, the outline fits a cube, and the view reads no layer above core.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SCRIPT_PATHS: Array[String] = ["res://view/explored_boxes.gd", "res://view/map_wireframe.gd"]
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
## Pinned outline size of the whole G2 level; a change to the level file or to
## the outline rules shows up here.
const G2_SEGMENT_COUNT: int = 90
const EPSILON: float = 1e-3


func _g2() -> BoxUnion:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE)).union


func _one_box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	return BoxUnion.new(boxes)


## A tunnel (box 0) with a narrower tunnel (box 1) leaving its far end: the
## opening is the square x, y in [-1, 1] on the plane z = -10.
func _joined() -> BoxUnion:
	var boxes: Array[BoxBounds] = [
		BoxBounds.new(Vector3(-2, -2, -10), Vector3(2, 2, 0)),
		BoxBounds.new(Vector3(-1, -1, -14), Vector3(1, 1, -8)),
	]
	return BoxUnion.new(boxes)


func _has_segment(points: PackedVector3Array, a: Vector3, b: Vector3) -> bool:
	for i: int in range(0, points.size(), 2):
		if (points[i].is_equal_approx(a) and points[i + 1].is_equal_approx(b)) \
				or (points[i].is_equal_approx(b) and points[i + 1].is_equal_approx(a)):
			return true
	return false


func test_an_empty_set_gives_no_segments() -> String:
	var none: Array[int] = []
	var points: PackedVector3Array = MapWireframe.segments(_g2(), none)
	if not points.is_empty():
		return "nothing explored gave %d points" % points.size()
	return ""


func test_one_box_gives_its_twelve_edges() -> String:
	var only: Array[int] = [0]
	var points: PackedVector3Array = MapWireframe.segments(_one_box(), only)
	if points.size() != 24:
		return "one box gave %d segments, not 12" % (points.size() / 2)
	var low: Vector3 = Vector3(-2, -3, -4)
	var high: Vector3 = Vector3(2, 3, 4)
	for i: int in range(0, points.size(), 2):
		var length: float = points[i].distance_to(points[i + 1])
		var along: Vector3 = (points[i + 1] - points[i]).abs()
		var axis: int = along.max_axis_index()
		if absf(length - (high[axis] - low[axis])) > EPSILON:
			return "segment %s-%s is not a whole box edge" % [points[i], points[i + 1]]
		for corner: Vector3 in [points[i], points[i + 1]]:
			for c: int in 3:
				if absf(corner[c] - low[c]) > EPSILON and absf(corner[c] - high[c]) > EPSILON:
					return "endpoint %s is not a box corner" % corner
	return ""


func test_joined_boxes_outline_the_opening_and_draw_nothing_across_it() -> String:
	var both: Array[int] = [0, 1]
	var points: PackedVector3Array = MapWireframe.segments(_joined(), both)
	var rim: Array[Vector3] = [Vector3(-1, -1, -10), Vector3(1, -1, -10), Vector3(1, 1, -10), Vector3(-1, 1, -10)]
	for i: int in 4:
		if not _has_segment(points, rim[i], rim[(i + 1) % 4]):
			return "opening rim %s-%s missing" % [rim[i], rim[(i + 1) % 4]]
	for i: int in range(0, points.size(), 2):
		var middle: Vector3 = (points[i] + points[i + 1]) * 0.5
		if absf(middle.z + 10.0) < EPSILON and absf(middle.x) < 1.0 - EPSILON and absf(middle.y) < 1.0 - EPSILON:
			return "segment %s-%s runs across the opening" % [points[i], points[i + 1]]
		# Box 1's walls inside box 0 are open space, so nothing is drawn there.
		if middle.z > -10.0 + EPSILON and absf(middle.x) <= 1.0 + EPSILON and absf(middle.y) <= 1.0 + EPSILON:
			return "segment %s-%s lies inside the joined space" % [points[i], points[i + 1]]
	# Box 0: 12 edges and the 4-sided rim. Box 1: its far end (4) and the 4 edges
	# from it to the rim, which it shares with box 0.
	if points.size() != 2 * 24:
		return "two joined boxes gave %d segments, not 24" % (points.size() / 2)
	return ""


func test_an_unexplored_neighbour_still_leaves_the_opening() -> String:
	var first: Array[int] = [0]
	var points: PackedVector3Array = MapWireframe.segments(_joined(), first)
	if not _has_segment(points, Vector3(-1, -1, -10), Vector3(1, -1, -10)):
		return "the rim of a passage into an unexplored box is missing"
	if points.size() != 2 * 16:
		return "box 0 alone gave %d segments, not 16" % (points.size() / 2)
	return ""


func test_visiting_a_shared_wall_marks_both_boxes() -> String:
	var touching: Array[BoxBounds] = [
		BoxBounds.new(Vector3(0, 0, 0), Vector3(4, 4, 4)),
		BoxBounds.new(Vector3(4, 0, 0), Vector3(8, 4, 4)),
		BoxBounds.new(Vector3(20, 20, 20), Vector3(24, 24, 24)),
	]
	var explored: ExploredBoxes = ExploredBoxes.new(BoxUnion.new(touching))
	if not explored.explored().is_empty():
		return "a new map already marks %s" % [explored.explored()]
	explored.visit(Vector3(4, 2, 2))
	if explored.explored() != [0, 1]:
		return "a point in the shared wall marked %s, not [0, 1]" % [explored.explored()]
	explored.visit(Vector3(50, 50, 50))
	explored.visit(Vector3(22, 22, 22))
	explored.visit(Vector3(1, 1, 1))
	if explored.explored() != [0, 1, 2]:
		return "after visiting box 2 and empty space the marks are %s" % [explored.explored()]
	return ""


func test_fitting_keeps_proportions_and_stays_in_the_cube() -> String:
	var only: Array[int] = [0]
	var points: PackedVector3Array = MapWireframe.segments(_one_box(), only)
	var fitted: PackedVector3Array = MapWireframe.fit_to_cube(points, 0.3)
	if fitted.size() != points.size():
		return "fitting changed the point count"
	var low: Vector3 = fitted[0]
	var high: Vector3 = fitted[0]
	for point: Vector3 in fitted:
		low = low.min(point)
		high = high.max(point)
	if not low.is_equal_approx(-high):
		return "fitted bounds %s..%s are not centred on the origin" % [low, high]
	if absf(high.z - 0.15) > EPSILON or high.x > 0.15 + EPSILON or high.y > 0.15 + EPSILON:
		return "fitted bounds %s..%s do not fill a 0.3 m cube along the longest side" % [low, high]
	# The box is 4 x 6 x 8; scaled evenly it stays 2 : 3 : 4.
	var size: Vector3 = high - low
	if absf(size.x / size.z - 0.5) > EPSILON or absf(size.y / size.z - 0.75) > EPSILON:
		return "fitted size %s lost the box's proportions" % size
	if not MapWireframe.fit_to_cube(PackedVector3Array(), 0.3).is_empty():
		return "fitting nothing gave points"
	return ""


func test_the_g2_level_fully_explored_gives_a_fixed_count() -> String:
	var union: BoxUnion = _g2()
	var all: Array[int] = []
	for index: int in union.boxes.size():
		all.append(index)
	var first: PackedVector3Array = MapWireframe.segments(union, all)
	var second: PackedVector3Array = MapWireframe.segments(_g2(), all)
	if first != second:
		return "two builds of the G2 outline differ"
	if first.size() / 2 != G2_SEGMENT_COUNT:
		return "the G2 outline has %d segments, not %d" % [first.size() / 2, G2_SEGMENT_COUNT]
	for i: int in range(0, first.size(), 2):
		if first[i].distance_to(first[i + 1]) < EPSILON:
			return "zero-length segment at %s" % first[i]
		# A segment through open space would cross a passage.
		var middle: Vector3 = (first[i] + first[i + 1]) * 0.5
		for box: BoxBounds in union.boxes:
			if box.holds(middle, EPSILON):
				return "segment %s-%s runs through open space" % [first[i], first[i + 1]]
	return ""


func test_reads_no_layer_above_core() -> String:
	for path: String in SCRIPT_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		for root: String in OUTSIDE_DIRS:
			for file: String in DirAccess.get_files_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray():
				if not file.ends_with(".gd"):
					continue
				var head: String = FileAccess.get_file_as_string("%s/%s" % [root, file]).get_slice("\n", 0)
				if head.begins_with("class_name "):
					var class_id: String = head.trim_prefix("class_name ").strip_edges()
					var found: RegEx = RegEx.create_from_string("\\b%s\\b" % class_id)
					if found.search(source) != null:
						return "%s references %s from %s" % [path, class_id, root]
	return ""
