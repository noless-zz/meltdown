class_name KnownRoute
extends RefCounted

## The shortest route out that the player knows of during the meltdown (MAP-2):
## through explored boxes only, and around openings that falling debris has
## blocked (RUN-4). Plain data for the map to draw; it reads the level and the
## debris and changes neither, so the meltdown timer and every state hash stand.
##
## The search is `EscapePath.length_mm`'s on fewer nodes: the start, the exit,
## the centre of every explored box and the centre of every open opening between
## two explored boxes, numbered in that order (boxes and openings in box order),
## with Dijkstra settling the lowest node on a tie. With every box explored and
## no debris the nodes are exactly `length_mm`'s, so the lengths agree. Box
## centres are left out of `points_mm`: inside one box the straight line is never
## longer, so the route bends only at openings.
##
## Openings are numbered over the whole level, explored or not: every pair of
## boxes i < j that share volume, in order of i then j. That number stays the
## same as the player explores, so the map can key a mark on it.
##
## Solid box debris that closes an explored box's whole cross-section splits that
## box (`BoxSplit`, #868): nodes in the box join only when they lie in the same
## part of it, and the start or exit inside it belongs to its own part. Splits
## are listed apart from openings, in `blocked_splits`, so opening numbers never
## change; their centres follow the openings' in `blocked_centres_mm`, so the map
## draws a cross at each with no change of its own. With nothing split every node
## and every length is what it was before.

## The route's corners in whole millimetres: start, opening centres, exit.
## Empty when no route is known.
var points_mm: Array[Vector3i] = []
## Length of the route in millimetres, or `EscapePath.UNREACHABLE` when none.
var length_mm: int = EscapePath.UNREACHABLE
## Openings between two explored boxes that debris blocks, lowest number first.
var blocked_openings: Array[int] = []
## Explored boxes split by debris, as (box, debris entry) pairs: by box, then
## entry, then axis (an entry splitting a box on two axes is listed twice).
var blocked_splits: Array[Vector2i] = []
## Centre of each blocked opening in millimetres, in the same order, followed by
## the centre of each split in the order of `blocked_splits`.
var blocked_centres_mm: Array[Vector3i] = []


## The route from `from` to the exit `to` through the boxes of `walls` listed in
## `explored` (in any order; repeats and indices that are not boxes are ignored),
## for a ship of `ship_radius` metres. Debris that is not yet solid blocks
## nothing; `debris` may be null. No route is known when either point lies in no
## explored box or no open opening joins them.
static func find(walls: BoxUnion, explored: Array[int], from: Vector3, to: Vector3,
		debris: MeltdownDebris, ship_radius: float) -> KnownRoute:
	var route: KnownRoute = KnownRoute.new()
	if walls == null:
		return route
	var count: int = walls.boxes.size()
	var known: Array[bool] = []
	known.resize(count)
	known.fill(false)
	for index: int in explored:
		if index >= 0 and index < count:
			known[index] = true
	var mins: Array[Vector3i] = []
	var maxs: Array[Vector3i] = []
	for box: BoxBounds in walls.boxes:
		mins.append(EscapePath.to_mm(box.min_corner))
		maxs.append(EscapePath.to_mm(box.max_corner))
	var radius_mm: int = roundi(ship_radius * RobotSpawn.SCALE)
	var points: Array[Vector3i] = [EscapePath.to_mm(from), EscapePath.to_mm(to)]
	var cuts: Array[Array] = _cuts(mins, maxs, known, debris, radius_mm, points)
	var members: Array[Array] = [
		_parts(cuts, _known_holding(walls, known, points[0]), points[0]),
		_parts(cuts, _known_holding(walls, known, points[1]), points[1])]
	var is_opening: Array[bool] = [false, false]
	for i: int in count:
		if known[i]:
			points.append((mins[i] + maxs[i]) / 2)
			members.append(_parts(cuts, [i], points[-1]))
			is_opening.append(false)
	var opening: int = 0
	for i: int in count:
		for j: int in range(i + 1, count):
			var low: Vector3i = mins[i].max(mins[j])
			var high: Vector3i = maxs[i].min(maxs[j])
			if not (low.x < high.x and low.y < high.y and low.z < high.z):
				continue
			opening += 1
			if not known[i] or not known[j]:
				continue
			var centre: Vector3i = (low + high) / 2
			if OpeningClearance.blocked(mins[i], maxs[i], mins[j], maxs[j], debris, radius_mm):
				route.blocked_openings.append(opening - 1)
				route.blocked_centres_mm.append(centre)
				continue
			points.append(centre)
			members.append(_parts(cuts, [i, j], centre))
			is_opening.append(true)
	for i: int in count:
		for cut: Vector3i in cuts[i]:
			route.blocked_splits.append(Vector2i(i, cut.x))
			route.blocked_centres_mm.append(BoxSplit.centre(mins[i], maxs[i], cut))
	if members[0].is_empty() or members[1].is_empty():
		return route
	route._search(points, members, is_opening)
	return route


## Explored boxes holding `point_mm`, walls included, as `EscapePath` counts them.
static func _known_holding(walls: BoxUnion, known: Array[bool], point_mm: Vector3i) -> Array:
	var held: Array = []
	var point: Vector3 = Vector3(point_mm) / float(RobotSpawn.SCALE)
	for i: int in walls.boxes.size():
		if known[i] and walls.boxes[i].holds(point, 0.0):
			held.append(i)
	return held


## Each box's splits (empty for a box not explored), keeping only those that
## separate two of the box's own points: its openings' centres, and the start and
## exit in `ends` when inside it. A door already sealing the box's one opening at
## the end of a corridor separates nothing, so it adds no second mark.
static func _cuts(mins: Array[Vector3i], maxs: Array[Vector3i], known: Array[bool],
		debris: MeltdownDebris, radius_mm: int, ends: Array[Vector3i]) -> Array[Array]:
	var cuts: Array[Array] = []
	for i: int in mins.size():
		var kept: Array[Vector3i] = []
		cuts.append(kept)
		if not known[i]:
			continue
		var found: Array[Vector3i] = BoxSplit.splits(mins[i], maxs[i], debris, radius_mm)
		if found.is_empty():
			continue
		var own: Array[Vector3i] = []
		for end: Vector3i in ends:
			if BoxSplit.holds(mins[i], maxs[i], end):
				own.append(end)
		for j: int in mins.size():
			var low: Vector3i = mins[i].max(mins[j])
			var high: Vector3i = maxs[i].min(maxs[j])
			if j != i and low.x < high.x and low.y < high.y and low.z < high.z:
				own.append((low + high) / 2)
		for cut: Vector3i in found:
			if BoxSplit.separates(cut, own):
				kept.append(cut)
	return cuts


## The parts of `boxes` that `point_mm` lies in, as (box, part along x, y, z).
static func _parts(cuts: Array[Array], boxes: Array, point_mm: Vector3i) -> Array:
	var parts: Array = []
	for box: Variant in boxes:
		var box_cuts: Array[Vector3i] = []
		box_cuts.assign(cuts[box])
		var part: Vector3i = BoxSplit.part(box_cuts, point_mm)
		parts.append(Vector4i(box, part.x, part.y, part.z))
	return parts


static func _share_a_box(a: Array, b: Array) -> bool:
	for box: Variant in a:
		if b.has(box):
			return true
	return false


## Dijkstra from node 0 to node 1, as in `EscapePath`, keeping each node's
## predecessor so the route can be read back. A predecessor changes only on a
## strictly shorter distance, so ties keep the node settled first.
func _search(points: Array[Vector3i], members: Array[Array], is_opening: Array[bool]) -> void:
	var size: int = points.size()
	var distance: Array[int] = []
	var previous: Array[int] = []
	var settled: Array[bool] = []
	distance.resize(size)
	distance.fill(EscapePath.UNREACHABLE)
	previous.resize(size)
	previous.fill(-1)
	settled.resize(size)
	settled.fill(false)
	distance[0] = 0
	while true:
		var current: int = -1
		for n: int in size:
			if not settled[n] and distance[n] >= 0 \
					and (current < 0 or distance[n] < distance[current]):
				current = n
		if current < 0:
			return
		if current == 1:
			break
		settled[current] = true
		for n: int in size:
			if settled[n] or not _share_a_box(members[current], members[n]):
				continue
			var through: int = distance[current] + EscapePath.edge_mm(points[current], points[n])
			if distance[n] < 0 or through < distance[n]:
				distance[n] = through
				previous[n] = current
	length_mm = distance[1]
	var reversed: Array[Vector3i] = [points[1]]
	var node: int = previous[1]
	while node > 0:
		if is_opening[node]:
			reversed.append(points[node])
		node = previous[node]
	reversed.append(points[0])
	reversed.reverse()
	points_mm = reversed
