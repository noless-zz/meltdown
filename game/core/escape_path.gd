class_name EscapePath
extends RefCounted

## The shortest way out of the level, for scaling the meltdown timer (RUN-5).
##
## The level's walls are a union of boxes. Each box is convex, so a straight line
## between two points inside one box stays inside it. The path graph therefore has
## the start point, the exit, every box centre and the centre of every opening (the
## overlap of two joined boxes) as nodes, and joins any two nodes that share a box.
## Points are whole millimetres and every edge is rounded to whole millimetres, so
## the length is the same on every device (ARC-1, ARC-2). Nodes are numbered in box
## order and Dijkstra settles the lowest-numbered node on a tie, so the search is
## deterministic too.

const UNREACHABLE: int = -1


## Shortest path length in millimetres from `from` to `to` through `walls`, or
## UNREACHABLE when either point lies outside every box or no opening joins them.
static func length_mm(walls: BoxUnion, from: Vector3, to: Vector3) -> int:
	var points: Array[Vector3i] = [_to_mm(from), _to_mm(to)]
	var members: Array[Array] = [_boxes_holding(walls, points[0]), _boxes_holding(walls, points[1])]
	if members[0].is_empty() or members[1].is_empty():
		return UNREACHABLE
	var count: int = walls.boxes.size()
	var mins: Array[Vector3i] = []
	var maxs: Array[Vector3i] = []
	for box: BoxBounds in walls.boxes:
		mins.append(_to_mm(box.min_corner))
		maxs.append(_to_mm(box.max_corner))
	for i: int in count:
		points.append((mins[i] + maxs[i]) / 2)
		members.append([i])
	for i: int in count:
		for j: int in range(i + 1, count):
			var low: Vector3i = mins[i].max(mins[j])
			var high: Vector3i = maxs[i].min(maxs[j])
			if low.x < high.x and low.y < high.y and low.z < high.z:
				points.append((low + high) / 2)
				members.append([i, j])
	return _dijkstra(points, members)


## The longest of the live ships' escape paths in millimetres: from each ship that
## has neither escaped nor been destroyed to its own start, which is its exit
## (RUN-3). Without walls the path is the straight line. A ship outside every box
## is skipped; with no path at all the result is 0.
static func longest_for_ships(sim: Sim) -> int:
	var longest: int = 0
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.escaped or ship.hull <= 0.0:
			continue
		var length: int = UNREACHABLE
		if sim.walls == null:
			length = _edge(_to_mm(ship.position), _to_mm(sim.start_positions[i]))
		else:
			length = length_mm(sim.walls, ship.position, sim.start_positions[i])
		longest = maxi(longest, length)
	return longest


static func _to_mm(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * RobotSpawn.SCALE), roundi(point.y * RobotSpawn.SCALE),
		roundi(point.z * RobotSpawn.SCALE))


static func _boxes_holding(walls: BoxUnion, point_mm: Vector3i) -> Array:
	var held: Array = []
	if walls == null:
		return held
	var point: Vector3 = Vector3(point_mm) / float(RobotSpawn.SCALE)
	for i: int in walls.boxes.size():
		if walls.boxes[i].holds(point, 0.0):
			held.append(i)
	return held


static func _edge(a: Vector3i, b: Vector3i) -> int:
	return roundi(Vector3(b - a).length())


static func _share_a_box(a: Array, b: Array) -> bool:
	for box: Variant in a:
		if b.has(box):
			return true
	return false


## Node 0 is the start and node 1 the exit. A plain O(n²) search: levels have tens
## of boxes, and it runs once per run, on the tick the reactor dies.
static func _dijkstra(points: Array[Vector3i], members: Array[Array]) -> int:
	var size: int = points.size()
	var distance: Array[int] = []
	var settled: Array[bool] = []
	distance.resize(size)
	distance.fill(UNREACHABLE)
	settled.resize(size)
	settled.fill(false)
	distance[0] = 0
	while true:
		var current: int = -1
		for n: int in size:
			# Strictly less keeps the lowest-numbered node on a tie.
			if not settled[n] and distance[n] >= 0 \
					and (current < 0 or distance[n] < distance[current]):
				current = n
		if current < 0:
			return UNREACHABLE
		if current == 1:
			return distance[1]
		settled[current] = true
		for n: int in size:
			if settled[n] or not _share_a_box(members[current], members[n]):
				continue
			var through: int = distance[current] + _edge(points[current], points[n])
			if distance[n] < 0 or through < distance[n]:
				distance[n] = through
	return UNREACHABLE
