extends RefCounted

## The shortest known escape route over explored boxes, around openings that
## falling debris blocks (#379, MAP-2, RUN-3, RUN-4, ARC-1, ARC-2).

const G2_LEVEL: String = "res://data/levels/g2_level.json"
const SHIP_RADIUS: float = 1.0


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))


func _all_boxes(walls: BoxUnion) -> Array[int]:
	var all: Array[int] = []
	for index: int in walls.boxes.size():
		all.append(index)
	return all


## A ring in the xz plane, 4 m high (y -2..2). Box 0 is the near room (z -4..0),
## box 3 the far room (z -23..-19), joined by a left corridor (box 1, x -10..-6)
## and a right one (box 2, x 6..10). Openings, numbered by box pair: 0 is 0-1,
## 1 is 0-2, 2 is 1-3, 3 is 2-3. Opening 2 spans x -10..-6, y -2..2, z -21..-19,
## centred on (-8, 0, -20). Without box 2 there is no loop.
func _ring(with_right: bool = true) -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -2, -4), Vector3(10, 2, 0)),
		BoxBounds.new(Vector3(-10, -2, -21), Vector3(-6, 2, -2))]
	if with_right:
		boxes.append(BoxBounds.new(Vector3(6, -2, -21), Vector3(10, 2, -2)))
	boxes.append(BoxBounds.new(Vector3(-10, -2, -23), Vector3(10, 2, -19)))
	return BoxUnion.new(boxes)


## Solid debris spheres: entries of [x, y, z, radius], all fallen.
func _debris(entries: Array) -> MeltdownDebris:
	var data: Array = []
	for entry: Array in entries:
		data.append({"position": [entry[0], entry[1], entry[2]], "radius": entry[3],
			"after_seconds": 1})
	var debris: MeltdownDebris = MeltdownDebris.parse(data)
	debris.elapsed_ticks = 60
	return debris


func _route(walls: BoxUnion, explored: Array[int], from: Vector3, debris: MeltdownDebris = null) -> KnownRoute:
	return EscapePath.known_route(walls, explored, from, Vector3(0, 0, -1), debris, SHIP_RADIUS)


func _goes_right(route: KnownRoute) -> bool:
	for point: Vector3i in route.points_mm:
		if point.x > 5000:
			return true
	return false


func test_fully_explored_g2_matches_length_mm() -> String:
	var level: LevelDef = _g2()
	if level.error != "":
		return level.error
	var all: Array[int] = _all_boxes(level.union)
	for from: Vector3 in [Vector3(0, -40, -46), Vector3(0, -39, -110.5), Vector3(5, -40, -80),
			Vector3(0, 5, -130), Vector3(1, 1, -3)]:
		var route: KnownRoute = EscapePath.known_route(level.union, all, from,
			level.start_position(), null, SHIP_RADIUS)
		var expected: int = EscapePath.length_mm(level.union, from, level.start_position())
		if route.length_mm != expected:
			return "from %s: %d mm, length_mm gives %d" % [from, route.length_mm, expected]
		if route.points_mm.front() != EscapePath.to_mm(from) \
				or route.points_mm.back() != EscapePath.to_mm(level.start_position()):
			return "from %s: the route runs %s" % [from, route.points_mm]
	return ""


func test_the_route_bends_only_at_opening_centres() -> String:
	# Foot of the G2 shaft to the start: up the shaft, through the opening of
	# boxes 0 and 1 (x -5..5, y -4..4, z -40..-36, centre (0, 0, -38)), along the tunnel.
	var level: LevelDef = _g2()
	var route: KnownRoute = EscapePath.known_route(level.union, _all_boxes(level.union),
		Vector3(0, -40, -46), level.start_position(), null, SHIP_RADIUS)
	var expected: Array[Vector3i] = [Vector3i(0, -40000, -46000), Vector3i(0, 0, -38000),
		EscapePath.to_mm(level.start_position())]
	if route.points_mm != expected:
		return "points %s, expected %s" % [route.points_mm, expected]
	var along: int = 0
	for index: int in range(1, route.points_mm.size()):
		along += EscapePath.edge_mm(route.points_mm[index - 1], route.points_mm[index])
	if along != route.length_mm:
		return "the points measure %d mm, the length is %d" % [along, route.length_mm]
	return ""


func test_partly_explored_g2_stays_inside_the_explored_boxes() -> String:
	var level: LevelDef = _g2()
	var full: int = EscapePath.length_mm(level.union, Vector3(0, -39, -110.5), level.start_position())
	var found: int = 0
	for mask: int in range(1, 1 << level.union.boxes.size()):
		var explored: Array[int] = []
		for index: int in level.union.boxes.size():
			if mask & (1 << index):
				explored.append(index)
		var route: KnownRoute = EscapePath.known_route(level.union, explored,
			Vector3(0, -39, -110.5), level.start_position(), null, SHIP_RADIUS)
		if route.points_mm.is_empty():
			if route.length_mm != EscapePath.UNREACHABLE:
				return "explored %s: no points but length %d" % [explored, route.length_mm]
			continue
		found += 1
		if route.length_mm < full:
			return "explored %s: %d mm, shorter than the full %d" % [explored, route.length_mm, full]
		for index: int in range(1, route.points_mm.size()):
			if not _one_explored_box_holds(level.union, explored, route.points_mm[index - 1],
					route.points_mm[index]):
				return "explored %s: leg %d leaves the explored boxes" % [explored, index]
	if found == 0:
		return "no explored set gave a route"
	return ""


func _one_explored_box_holds(walls: BoxUnion, explored: Array[int], a: Vector3i, b: Vector3i) -> bool:
	for index: int in explored:
		var box: BoxBounds = walls.boxes[index]
		if box.holds(Vector3(a) / 1000.0, 0.0) and box.holds(Vector3(b) / 1000.0, 0.0):
			return true
	return false


func test_unexplored_start_or_exit_gives_no_route() -> String:
	var walls: BoxUnion = _ring()
	var route: KnownRoute = _route(walls, [0, 1], Vector3(-1, 0, -21))
	if not route.points_mm.is_empty() or route.length_mm != EscapePath.UNREACHABLE:
		return "a route from an unexplored box: %s" % [route.points_mm]
	route = _route(walls, [1, 3], Vector3(-1, 0, -21))
	if not route.points_mm.is_empty():
		return "a route to an unexplored exit"
	return ""


func test_debris_across_an_opening_sends_the_route_round_the_loop() -> String:
	var walls: BoxUnion = _ring()
	var all: Array[int] = [3, 2, 1, 0, 1]
	var from: Vector3 = Vector3(-1, 0, -21)
	var clear: KnownRoute = _route(walls, all, from)
	if clear.points_mm.is_empty() or _goes_right(clear) or not clear.blocked_openings.is_empty():
		return "without debris the route should take the left corridor: %s" % [clear.points_mm]
	var route: KnownRoute = _route(walls, all, from, _debris([[-8, 0, -20, 1.5]]))
	if route.blocked_openings != [2]:
		return "blocked openings %s, expected [2]" % [route.blocked_openings]
	if route.blocked_centres_mm != [Vector3i(-8000, 0, -20000)]:
		return "blocked centres %s" % [route.blocked_centres_mm]
	if route.points_mm.is_empty() or not _goes_right(route):
		return "the route should go round by the right corridor: %s" % [route.points_mm]
	if route.length_mm <= clear.length_mm:
		return "the way round is %d mm, not longer than %d" % [route.length_mm, clear.length_mm]
	return ""


func test_debris_across_the_only_way_leaves_no_route() -> String:
	var walls: BoxUnion = _ring(false)
	var route: KnownRoute = _route(walls, [0, 1, 2], Vector3(-1, 0, -21), _debris([[-8, 0, -20, 1.5]]))
	if not route.points_mm.is_empty() or route.length_mm != EscapePath.UNREACHABLE:
		return "a route through blocked debris: %s" % [route.points_mm]
	if route.blocked_openings != [1]:
		return "blocked openings %s, expected [1] (boxes 1 and 2)" % [route.blocked_openings]
	return ""


func test_a_narrowed_opening_still_ship_wide_stays_open() -> String:
	# Opening 2 is 4 m across in x (-10..-6) and y (-2..2). Debris on its wall at
	# x -10, y 0 with radius 1.9 m leaves 2.1 m beside it, more than a ship's 2 m.
	# At 2.3 m only 1.7 m is left beside it, and above or below the sphere a ship
	# hugging the corner is still sqrt(3² + 1²) = 3.16 m from its centre, under the
	# 3.3 m it needs.
	var walls: BoxUnion = _ring()
	var all: Array[int] = [0, 1, 2, 3]
	var from: Vector3 = Vector3(-1, 0, -21)
	var narrowed: KnownRoute = _route(walls, all, from, _debris([[-10, 0, -20, 1.9]]))
	if not narrowed.blocked_openings.is_empty() or _goes_right(narrowed):
		return "2.1 m left clear, yet blocked %s, route %s" % [narrowed.blocked_openings, narrowed.points_mm]
	var exact: KnownRoute = _route(walls, all, from, _debris([[-10, 0, -20, 2.0]]))
	if not exact.blocked_openings.is_empty():
		return "exactly a ship's diameter left clear counts as blocked"
	var closed: KnownRoute = _route(walls, all, from, _debris([[-10, 0, -20, 2.3]]))
	if closed.blocked_openings != [2]:
		return "1.7 m left clear, yet not blocked: %s" % [closed.blocked_openings]
	# Two spheres from opposite walls, each leaving room alone. Two 1 m spheres
	# leave exactly 2 m between them; two 1.3 m spheres leave 1.4 m, and a ship
	# passing over them is at most sqrt(2² + 1²) = 2.24 m from either centre,
	# under the 2.3 m it needs.
	var pair: KnownRoute = _route(walls, all, from, _debris([[-10, 0, -20, 1.0], [-6, 0, -20, 1.0]]))
	if not pair.blocked_openings.is_empty():
		return "two 1 m spheres leave 2 m, yet blocked"
	var pinch: KnownRoute = _route(walls, all, from, _debris([[-10, 0, -20, 1.3], [-6, 0, -20, 1.3]]))
	if pinch.blocked_openings != [2]:
		return "two 1.3 m spheres leave 1.4 m, yet not blocked: %s" % [pinch.blocked_openings]
	return ""


func test_debris_beside_or_not_yet_fallen_blocks_nothing() -> String:
	var walls: BoxUnion = _ring()
	var all: Array[int] = [0, 1, 2, 3]
	var from: Vector3 = Vector3(-1, 0, -21)
	# Opening 2 spans z -21..-19; a 1.5 m sphere centred 3.6 m short of it
	# reaches 2.5 m with the ship's radius, so it misses the ship's sweep.
	var beside: KnownRoute = _route(walls, all, from, _debris([[-8, 0, -15.4, 1.5]]))
	if not beside.blocked_openings.is_empty():
		return "a sphere clear of the crossing blocked %s" % [beside.blocked_openings]
	# 1.5 m short, it is 2 m wide across the crossing and covers the whole
	# 2 m by 2 m square a ship's centre may cross in.
	var near: KnownRoute = _route(walls, all, from, _debris([[-8, 0, -17.5, 1.5]]))
	if near.blocked_openings != [2]:
		return "a sphere reaching into the crossing blocked %s" % [near.blocked_openings]
	var waiting: MeltdownDebris = _debris([[-8, 0, -20, 1.5]])
	waiting.elapsed_ticks = 0
	if not _route(walls, all, from, waiting).blocked_openings.is_empty():
		return "debris that has not fallen blocked an opening"
	return ""


func test_blocked_openings_are_reported_only_between_explored_boxes() -> String:
	var walls: BoxUnion = _ring()
	var route: KnownRoute = _route(walls, [0, 1], Vector3(-8, 0, -10), _debris([[-8, 0, -20, 1.5]]))
	if not route.blocked_openings.is_empty():
		return "an opening into an unexplored box reported blocked"
	if route.points_mm.is_empty():
		return "no route from the explored left corridor"
	return ""


func test_same_inputs_same_route() -> String:
	var level: LevelDef = _g2()
	var debris: MeltdownDebris = _debris([[0, 0, -38, 2.0], [3, -40, -80, 1.0]])
	var first: KnownRoute = EscapePath.known_route(level.union, [5, 4, 3, 2, 1, 0],
		Vector3(0, -39, -110.5), level.start_position(), debris, SHIP_RADIUS)
	for attempt: int in 3:
		var again: KnownRoute = EscapePath.known_route(level.union, [0, 1, 2, 3, 4, 5],
			Vector3(0, -39, -110.5), level.start_position(), debris, SHIP_RADIUS)
		if again.points_mm != first.points_mm or again.length_mm != first.length_mm \
				or again.blocked_openings != first.blocked_openings:
			return "attempt %d differs" % attempt
	return ""
