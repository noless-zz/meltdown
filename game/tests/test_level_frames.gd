extends RefCounted

## Frames at openings (#1323, GFX-2, ARC-4): every doorway in a wall gets a
## frame as deep as the wall is thick, drawn with the walls; a frame never
## closes an opening, never pokes into the flight space further than the
## wall's thickness, and the sizes are data in the look file.

const SeedSweep := preload("res://tests/seed_sweep.gd")

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SEEDS: Array[int] = [1, 2, 3, 12345]
const DEPTH: float = 0.6
const WIDTH: float = 0.3
const EPSILON: float = 1e-3


func _union(boxes: Array[BoxBounds]) -> BoxUnion:
	return BoxUnion.new(boxes)


## A 10 m room with a 4 m tunnel joining its x = 0 wall from the side.
func _room_and_tunnel(tunnel_low: Vector3, tunnel_high: Vector3) -> BoxUnion:
	return _union([BoxBounds.new(Vector3.ZERO, Vector3(10, 8, 10)), BoxBounds.new(tunnel_low, tunnel_high)])


func _levels() -> Array[BoxUnion]:
	var unions: Array[BoxUnion] = []
	unions.append(LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE)).union)
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	for level_seed: int in SEEDS:
		unions.append(MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT).union)
	return unions


func _area(quads: Array[Dictionary]) -> float:
	var total: float = 0.0
	for quad: Dictionary in quads:
		total += LevelFaces.area(quad)
	return total


## Frame quads lying in the face of box `index` at `plane` on `axis` and facing like it.
func _front(frames: Array[Dictionary], index: int, axis: int, plane: float, facing: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for quad: Dictionary in frames:
		if quad["box"] == index and quad["axis"] == axis and (quad["normal"] as Vector3)[axis] == facing \
				and absf((quad["min"] as Vector3)[axis] - plane) < EPSILON:
			found.append(quad)
	return found


## Each hole in each face, worked out here without `LevelFaces`:
## [index, axis, plane, facing, Rect2 in (u, v), Rect2 of the face].
func _holes(union: BoxUnion) -> Array[Array]:
	var found: Array[Array] = []
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		for axis: int in 3:
			var u: int = (axis + 1) % 3
			var v: int = (axis + 2) % 3
			var face: Rect2 = Rect2(box.min_corner[u], box.min_corner[v],
					box.max_corner[u] - box.min_corner[u], box.max_corner[v] - box.min_corner[v])
			for facing: float in [1.0, -1.0]:
				var plane: float = box.min_corner[axis] if facing > 0.0 else box.max_corner[axis]
				for other_index: int in union.boxes.size():
					var other: BoxBounds = union.boxes[other_index]
					if other_index == index or not (other.min_corner[axis] < plane and plane < other.max_corner[axis]):
						continue
					var cover: Rect2 = face.intersection(Rect2(other.min_corner[u], other.min_corner[v],
							other.max_corner[u] - other.min_corner[u], other.max_corner[v] - other.min_corner[v]))
					if cover.size.x > EPSILON and cover.size.y > EPSILON:
						found.append([index, axis, plane, facing, cover, face])
	return found


func _covers(quad: Dictionary, axis: int, point: Vector2) -> bool:
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var low: Vector3 = quad["min"]
	var high: Vector3 = quad["max"]
	return point.x > low[u] and point.x < high[u] and point.y > low[v] and point.y < high[v]


func test_a_doorway_gets_a_frame_all_round_drawn_with_the_walls() -> String:
	var union: BoxUnion = _room_and_tunnel(Vector3(-6, 2, 3), Vector3(1, 6, 7))
	var frames: Array[Dictionary] = LevelFrames.quads(union, DEPTH, WIDTH)
	var front: Array[Dictionary] = _front(frames, 0, 0, 0.0, 1.0)
	var back: Array[Dictionary] = _front(frames, 0, 0, -DEPTH, -1.0)
	# The ring between the 4 m doorway and the 3.4 m one left inside the frame.
	var ring: float = 16.0 - 3.4 * 3.4
	if absf(_area(front) - ring) > EPSILON or absf(_area(back) - ring) > EPSILON:
		return "front %s m² and back %s m², expected %s each" % [_area(front), _area(back), ring]
	var reveals: int = 0
	for quad: Dictionary in frames:
		if quad["axis"] == 0:
			continue
		reveals += 1
		# A reveal faces into the doorway, whose middle is y 4, z 5.
		var centre: Vector3 = ((quad["min"] as Vector3) + (quad["max"] as Vector3)) * 0.5
		if (Vector3(centre.x, 4.0, 5.0) - centre).dot(quad["normal"]) <= 0.0:
			return "the reveal at %s faces away from the doorway" % centre
		if absf(LevelFaces.area(quad) - DEPTH * 3.4) > EPSILON:
			return "the reveal at %s is %s m², expected %s" % [centre, LevelFaces.area(quad), DEPTH * 3.4]
	if reveals != 4 or frames.size() != front.size() + back.size() + 4:
		return "%d reveals among %d frame quads, expected 4 and nothing on the tunnel" % [reveals, frames.size()]
	var view: LevelView = LevelView.new()
	view.build(union)
	var drawn: int = view.frames().size()
	view.free()
	return "" if drawn == frames.size() else "the view drew %d frame quads, expected %d" % [drawn, frames.size()]


func test_a_mouth_on_the_floor_is_framed_on_its_three_walled_sides() -> String:
	var union: BoxUnion = _room_and_tunnel(Vector3(-6, 0, 3), Vector3(1, 4, 7))
	var front: Array[Dictionary] = _front(LevelFrames.quads(union, DEPTH, WIDTH), 0, 0, 0.0, 1.0)
	# Two 4 m jambs and the 3.4 m lintel between them; no sill on the floor.
	var want: float = 2.0 * WIDTH * 4.0 + WIDTH * 3.4
	if absf(_area(front) - want) > EPSILON:
		return "front %s m², expected %s" % [_area(front), want]
	for quad: Dictionary in front:
		if (quad["min"] as Vector3).y < EPSILON and (quad["max"] as Vector3).y < WIDTH + EPSILON:
			return "the floor of the mouth got a sill: %s" % quad
	return ""


func test_a_short_tunnel_or_narrow_slot_keeps_its_opening() -> String:
	# The tunnel reaches 0.8 m behind the wall, so the frame takes half of that.
	var short: Array[Dictionary] = LevelFrames.quads(_room_and_tunnel(Vector3(-0.8, 2, 3), Vector3(1, 6, 7)), DEPTH, WIDTH)
	if _front(short, 0, 0, -0.4, -1.0).is_empty():
		return "the frame of a 0.8 m tunnel is not 0.4 m deep"
	# A 0.8 m slot keeps 0.4 m open between frames 0.2 m wide.
	var slot: Array[Dictionary] = LevelFrames.quads(_room_and_tunnel(Vector3(-6, 2, 3), Vector3(1, 6, 3.8)), DEPTH, WIDTH)
	var area: float = _area(_front(slot, 0, 0, 0.0, 1.0))
	var want: float = 4.0 * 0.8 - 3.6 * 0.4
	if absf(area - want) > EPSILON:
		return "slot frame %s m², expected %s" % [area, want]
	return ""


func test_every_doorway_in_the_shipped_levels_gets_a_frame() -> String:
	var doorways: int = 0
	for union: BoxUnion in _levels():
		var frames: Array[Dictionary] = LevelFrames.quads(union, DEPTH, WIDTH)
		var holes: Array[Array] = _holes(union)
		for hole: Array in holes:
			var rect: Rect2 = hole[4]
			var face: Rect2 = hole[5]
			# A doorway: a hole well inside its face, apart from every other hole there.
			if not face.grow(-EPSILON).encloses(rect):
				continue
			var alone: bool = true
			for other: Array in holes:
				if other != hole and other[0] == hole[0] and other[1] == hole[1] and is_equal_approx(other[2], hole[2]) \
						and (other[4] as Rect2).grow(EPSILON).intersects(rect):
					alone = false
			if not alone:
				continue
			doorways += 1
			var front: Array[Dictionary] = _front(frames, hole[0], hole[1], hole[2], hole[3])
			var centre: Vector2 = rect.get_center()
			for probe: Vector2 in [Vector2(rect.position.x + 0.01, centre.y), Vector2(rect.end.x - 0.01, centre.y),
					Vector2(centre.x, rect.position.y + 0.01), Vector2(centre.x, rect.end.y - 0.01)]:
				var framed: bool = false
				for quad: Dictionary in front:
					framed = framed or _covers(quad, hole[1], probe)
				if not framed:
					return "box %d axis %d: the doorway %s has no frame at %s" % [hole[0], hole[1], rect, probe]
	return "" if doorways > 0 else "no doorway found in the shipped levels"


func test_frames_never_close_an_opening() -> String:
	for union: BoxUnion in _levels():
		var frames: Array[Dictionary] = LevelFrames.quads(union, DEPTH, WIDTH)
		for hole: Array in _holes(union):
			var rect: Rect2 = hole[4]
			var centre: Vector2 = rect.get_center()
			var front: Array[Dictionary] = _front(frames, hole[0], hole[1], hole[2], hole[3])
			for across: int in 2:
				var low: float = rect.position[across]
				var high: float = rect.end[across]
				for quad: Dictionary in front:
					if _covers(quad, hole[1], centre):
						return "box %d axis %d: a frame covers the middle of the opening %s" % [hole[0], hole[1], rect]
					var q_low: Vector3 = quad["min"]
					var q_high: Vector3 = quad["max"]
					var along: int = (hole[1] + 2 - across) % 3
					var lengthwise: int = (hole[1] + 1 + across) % 3
					if q_low[along] > centre[1 - across] or q_high[along] < centre[1 - across]:
						continue
					if q_high[lengthwise] <= centre[across]:
						low = maxf(low, q_high[lengthwise])
					elif q_low[lengthwise] >= centre[across]:
						high = minf(high, q_low[lengthwise])
				var span: float = rect.size[across]
				if high - low < maxf(span * 0.5, span - 2.0 * WIDTH) - EPSILON:
					return "box %d axis %d: the opening %s keeps %.2f m of %.2f m" % [hole[0], hole[1], rect, high - low, span]
	return ""


func test_no_frame_pokes_further_than_the_walls_thickness() -> String:
	for union: BoxUnion in _levels():
		var walls: Array[Dictionary] = LevelFaces.quads(union)
		for quad: Dictionary in LevelFrames.quads(union, DEPTH, WIDTH):
			var low: Vector3 = quad["min"]
			var high: Vector3 = quad["max"]
			for corner: Vector3 in [low, high, Vector3(low.x, high.y, high.z), Vector3(high.x, low.y, low.z)]:
				var nearest: float = INF
				for wall: Dictionary in walls:
					var closest: Vector3 = corner.clamp(wall["min"], wall["max"])
					var gap: Vector3 = (corner - closest).abs()
					nearest = minf(nearest, maxf(gap.x, maxf(gap.y, gap.z)))
				if nearest > DEPTH + EPSILON:
					return "a frame corner at %s stands %.2f m clear of every wall" % [corner, nearest]
				var inside: bool = false
				for box: BoxBounds in union.boxes:
					inside = inside or (corner.clamp(box.min_corner, box.max_corner) - corner).length() < EPSILON
				if not inside:
					return "a frame corner at %s lies in the rock" % corner
	return ""


func test_sizes_are_data_and_a_frame_is_no_wider_than_the_wall_is_deep() -> String:
	var look: Dictionary = LevelLook.load_file()
	if look.has("error") or float(look["frame_depth_m"]) <= 0.0 or float(look["frame_width_m"]) <= 0.0:
		return "the shipped look has no frames: %s" % look
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LevelLook.DEFAULT_FILE))
	data["frame_width_m"] = float(data["frame_depth_m"]) + 0.1
	var error: String = String(LevelLook.parse(JSON.stringify(data)).get("error", ""))
	if not error.contains("frame_width_m"):
		return "a frame wider than deep gave \"%s\"" % error
	var union: BoxUnion = _room_and_tunnel(Vector3(-6, 2, 3), Vector3(1, 6, 7))
	if not LevelFrames.quads(union, 0.0, WIDTH).is_empty() or not LevelFrames.quads(union, DEPTH, 0.0).is_empty():
		return "a depth or width of 0 still drew frames"
	return ""
