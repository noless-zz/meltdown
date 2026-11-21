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
	var points: Array[Vector3i] = [to_mm(from), to_mm(to)]
	var members: Array[Array] = [_boxes_holding(walls, points[0]), _boxes_holding(walls, points[1])]
	if members[0].is_empty() or members[1].is_empty():
		return UNREACHABLE
	_add_box_nodes(walls, points, members)
	return _dijkstra(points, members)


## `length_mm` from each of `sources_mm` (whole millimetres) to `to`, in one
## search, UNREACHABLE for a source outside every box or cut off (#912: every
## module the reactor could go to, measured on each generated level). Each
## length equals `length_mm` for that source: the search runs from `to`, and
## the sources are ends it never routes through, so the graph between `to`
## and one source is the one `length_mm` builds, and edges measure the same
## both ways.
static func lengths_mm(walls: BoxUnion, to: Vector3, sources_mm: Array[Vector3i]) -> Array[int]:
	var found: Array[int] = []
	found.resize(sources_mm.size())
	found.fill(UNREACHABLE)
	var points: Array[Vector3i] = [to_mm(to)]
	var members: Array[Array] = [_boxes_holding(walls, points[0])]
	if members[0].is_empty():
		return found
	for source: Vector3i in sources_mm:
		points.append(source)
		members.append(_boxes_holding(walls, source))
	_add_box_nodes(walls, points, members)
	var distance: Array[int] = _distances(points, members, sources_mm.size())
	for index: int in sources_mm.size():
		if not members[index + 1].is_empty():
			found[index] = distance[index + 1]
	return found


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
			length = edge_mm(to_mm(ship.position), to_mm(sim.start_positions[i]))
		else:
			length = length_mm(sim.walls, ship.position, sim.start_positions[i])
		longest = maxi(longest, length)
	return longest


## The shortest route the player knows from `from` to the exit `to` during the
## meltdown (MAP-2): only through the boxes in `explored` (box indices, as the
## map's `ExploredBoxes.explored` lists them) and only through openings that
## solid `debris` leaves a ship of `ship_radius` room to cross. See `KnownRoute`.
static func known_route(walls: BoxUnion, explored: Array[int], from: Vector3, to: Vector3,
		debris: MeltdownDebris, ship_radius: float) -> KnownRoute:
	return KnownRoute.find(walls, explored, from, to, debris, ship_radius)


## A point in metres as whole millimetres, the unit every path is measured in.
static func to_mm(point: Vector3) -> Vector3i:
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


## One straight edge of a path, rounded to whole millimetres.
static func edge_mm(a: Vector3i, b: Vector3i) -> int:
	return roundi(Vector3(b - a).length())


## Appends every box centre and the centre of every opening to the nodes.
static func _add_box_nodes(walls: BoxUnion, points: Array[Vector3i], members: Array[Array]) -> void:
	var count: int = walls.boxes.size()
	var mins: Array[Vector3i] = []
	var maxs: Array[Vector3i] = []
	for box: BoxBounds in walls.boxes:
		mins.append(to_mm(box.min_corner))
		maxs.append(to_mm(box.max_corner))
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


## Every node's distance from node 0, UNREACHABLE where none; nodes 1 to
## `ends` are reached but never passed through. With `stop_at_first` the search
## ends once node 1 is settled, so only its distance is final. A plain O(n²)
## search; on a tie the lowest-numbered node is settled first.
static func _distances(points: Array[Vector3i], members: Array[Array], ends: int,
		stop_at_first: bool = false) -> Array[int]:
	var size: int = points.size()
	var distance: Array[int] = []
	var settled: Array[bool] = []
	distance.resize(size)
	distance.fill(UNREACHABLE)
	settled.resize(size)
	settled.fill(false)
	var in_box: Dictionary[int, Array] = {}
	for n: int in size:
		for box: Variant in members[n]:
			if not in_box.has(box):
				in_box[box] = []
			in_box[box].append(n)
	distance[0] = 0
	while true:
		var current: int = -1
		for n: int in size:
			if not settled[n] and distance[n] >= 0 \
					and (current < 0 or distance[n] < distance[current]):
				current = n
		if current < 0:
			break
		settled[current] = true
		if stop_at_first and current == 1:
			break
		if current >= 1 and current <= ends:
			continue
		# The nodes sharing a box with this one, box by box, rather than
		# testing every pair: the sweep runs this for every candidate module.
		for box: Variant in members[current]:
			for n: int in in_box[box]:
				if settled[n]:
					continue
				var through: int = distance[current] + edge_mm(points[current], points[n])
				if distance[n] < 0 or through < distance[n]:
					distance[n] = through
	return distance


## Node 0 is the start and node 1 the exit; the search stops once the exit
## is settled. Levels have tens of boxes, and it runs once per run, on the tick
## the reactor dies.
static func _dijkstra(points: Array[Vector3i], members: Array[Array]) -> int:
	return _distances(points, members, 1, true)[1]
