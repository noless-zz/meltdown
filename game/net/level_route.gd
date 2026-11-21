class_name LevelRoute
extends RefCounted

## A route through a hand-built level's boxes for a sphere of given radius, so
## the bot pilot can reach a target round a corner instead of flying into rock
## (CMB-3, GEN-5, #289).
##
## The route is the shortest chain of joined boxes (`LevelDef.neighbours`)
## from the boxes holding the start to the boxes holding the target, passing
## through the centre of each opening. Both ends of each leg lie in one box
## with room for the sphere, and a box is convex, so every leg is clear.
## The centre of an opening is at least half of `LevelDef.MIN_OVERLAP_M` from
## the walls of both boxes, so this holds for radii up to that.
##
## Only reads the level; no randomness, and boxes are visited in index order,
## so the same inputs give the same route (ARC-1, ARC-2).
##
## During the meltdown `close_blocked` shuts the openings that solid debris
## blocks (RUN-4, #443), by `OpeningClearance.blocked`, the test `KnownRoute`
## uses, and a straight segment then also has to pass the solid debris. A solid
## box entry across a box's whole cross-section splits that box (`BoxSplit`, the
## helper `KnownRoute` uses, #870): the chain then moves between parts of boxes,
## and from one opening of a split box to the next only within the same part.
##
## Once `weigh_fire` is called (the bot's escape, #498), a route through fire
## that burns before the ship gets there gives way to a fire-free one that is
## not much longer (`FireDetour`). Until then fire changes nothing.

## Slack on the segment test, as a fraction of the segment, so that legs
## ending exactly on a shrunk wall still count as held.
const EPSILON: float = 0.000001

var _union: BoxUnion = null
## `_neighbours[i]` lists the boxes joined to box i, lowest first.
var _neighbours: Array = []
## Openings shut by debris, as `_pair_key(i, j)` for joined boxes i < j.
var _closed: Dictionary[int, bool] = {}
## The debris last passed to `close_blocked`; null until then.
var _debris: MeltdownDebris = null
## `_cuts[i]` lists the splits (`BoxSplit`) solid debris makes in box i.
var _cuts: Array[Array] = []
## Ship radius last passed to `close_blocked`, metres.
var _debris_radius: float = 0.0
## The debris whose fire the route weighs; null until `weigh_fire`.
var _fire: MeltdownDebris = null
## Speed the ship is assumed to fly at when judging whether a fire will burn
## by the time it gets there, metres per second.
var _fire_speed: float = 0.0
## A fire-free route is taken when at most this many times as long.
var _detour_factor: float = 1.0


func _init(level: LevelDef) -> void:
	_union = level.union
	for index: int in _union.boxes.size():
		_neighbours.append(level.neighbours(index))
		_cuts.append([] as Array[Vector3i])


## True if a sphere of `radius` is held whole by the union at every point of
## the segment from `from` to `to`: the parts of the segment inside each box
## shrunk by `radius` together cover all of it.
static func segment_held(union: BoxUnion, from: Vector3, to: Vector3, radius: float) -> bool:
	var spans: Array[Vector2] = []
	for box: BoxBounds in union.boxes:
		var span: Vector2 = _span_in(box, from, to, radius)
		if span.x <= span.y:
			spans.append(span)
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var covered: float = 0.0
	for span: Vector2 in spans:
		if span.x > covered + EPSILON:
			return false
		covered = maxf(covered, span.y)
	return covered >= 1.0 - EPSILON


## Centre of the opening between two joined boxes: the middle of their overlap.
static func opening_centre(a: BoxBounds, b: BoxBounds) -> Vector3:
	var low: Vector3 = Vector3(maxf(a.min_corner.x, b.min_corner.x),
		maxf(a.min_corner.y, b.min_corner.y), maxf(a.min_corner.z, b.min_corner.z))
	var high: Vector3 = Vector3(minf(a.max_corner.x, b.max_corner.x),
		minf(a.max_corner.y, b.max_corner.y), minf(a.max_corner.z, b.max_corner.z))
	return (low + high) * 0.5


## Shuts every opening between joined boxes that the solid entries of `debris`
## block for a ship of `ship_radius`, and opens again any they no longer block.
## Held entries are never solid, so they block nothing. Call it again when more
## entries turn solid; the route reads `debris` live for straight segments.
func close_blocked(debris: MeltdownDebris, ship_radius: float) -> void:
	_closed.clear()
	_debris = debris
	_debris_radius = ship_radius
	for i: int in _union.boxes.size():
		_cuts[i] = [] as Array[Vector3i]
	if debris == null:
		return
	var radius_mm: int = roundi(ship_radius * RobotSpawn.SCALE)
	for i: int in _union.boxes.size():
		var a: BoxBounds = _union.boxes[i]
		_cuts[i] = BoxSplit.splits(EscapePath.to_mm(a.min_corner), EscapePath.to_mm(a.max_corner),
			debris, radius_mm)
		for j: int in _neighbours[i]:
			if j <= i:
				continue
			var b: BoxBounds = _union.boxes[j]
			if OpeningClearance.blocked(EscapePath.to_mm(a.min_corner), EscapePath.to_mm(a.max_corner),
					EscapePath.to_mm(b.min_corner), EscapePath.to_mm(b.max_corner), debris, radius_mm):
				_closed[_pair_key(i, j)] = true


## Whether `close_blocked` shut the opening between boxes `a` and `b`.
func is_closed(a: int, b: int) -> bool:
	return _closed.has(_pair_key(mini(a, b), maxi(a, b)))


## From now on, routes through fire entries of `debris` that burn, or will
## by the time a ship flying at `speed` gets there, give way to a fire-free
## route at most `detour_factor` times as long. Pass null to stop.
func weigh_fire(debris: MeltdownDebris, speed: float, detour_factor: float) -> void:
	_fire = debris
	_fire_speed = speed
	_detour_factor = detour_factor


## The points to fly through from `from` to `to`, ending with `to`. Just
## `[to]` when the straight segment is held, or when no chain joins the two
## ends (the caller then flies straight, as without a level). With fire
## weighed, a fire-free route not much longer may replace it, unless it crosses
## a split box, which `FireDetour` does not know about.
func waypoints(from: Vector3, to: Vector3, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = _plain_waypoints(from, to, radius)
	if _fire == null:
		return points
	var detour: Array[Vector3] = FireDetour.reroute(_union, _neighbours, is_closed, _fire, from, to,
		_holding(from, radius), _holding(to, radius), points, _fire_speed, _detour_factor)
	return points if detour.is_empty() or _crosses_split(from, detour) else detour


## `waypoints` without regard to fire.
func _plain_waypoints(from: Vector3, to: Vector3, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not segment_held(_union, from, to, radius) or _meets_debris(from, to, radius):
		var boxes: Array[int] = chain(from, to, radius)
		for i: int in boxes.size() - 1:
			points.append(opening_centre(_union.boxes[boxes[i]], _union.boxes[boxes[i + 1]]))
	points.append(to)
	return points


## The first point of `waypoints`: where to fly next.
func next_waypoint(from: Vector3, to: Vector3, radius: float) -> Vector3:
	return waypoints(from, to, radius)[0]


## Box indices of the shortest chain of joined boxes from a box holding `from`
## to a box holding `to`, both ends included; empty if there is none. A
## breadth-first search from every start box at once, in index order, so the
## chain starts at the start box nearest the target in hops and ties go to
## lower indices. The search runs over parts of boxes (`BoxSplit.part`): an
## opening leads on from a box only from the part its centre lies in, so a
## chain never passes a split. With no splits every part is zero and each box
## is one node, as before splits were known.
func chain(from: Vector3, to: Vector3, radius: float) -> Array[int]:
	var goals: Array[Vector4i] = _nodes(_holding(to, radius), EscapePath.to_mm(to))
	var previous: Dictionary[Vector4i, Vector4i] = {}
	var queue: Array[Vector4i] = []
	for node: Vector4i in _nodes(_holding(from, radius), EscapePath.to_mm(from)):
		previous[node] = Vector4i(-1, 0, 0, 0)
		queue.append(node)
	var found: Vector4i = Vector4i(-1, 0, 0, 0)
	while not queue.is_empty():
		var node: Vector4i = queue.pop_front()
		if goals.has(node):
			found = node
			break
		for other: int in _neighbours[node.x]:
			if is_closed(node.x, other):
				continue
			var centre: Vector3i = EscapePath.to_mm(opening_centre(_union.boxes[node.x],
				_union.boxes[other]))
			if _node(node.x, centre) != node:
				continue
			var next: Vector4i = _node(other, centre)
			if not previous.has(next):
				previous[next] = node
				queue.append(next)
	var boxes: Array[int] = []
	while found.x >= 0:
		boxes.push_front(found.x)
		found = previous[found]
	return boxes


## Whether a sphere of `radius` flying from `from` to `to` would touch solid
## debris given to `close_blocked`. Always false before that is called, so
## routes before the meltdown, and on levels without debris, are unchanged.
## A box entry is grown by `radius` on every side with square corners, a little
## more than the sphere sweeps past its edges, so the bot never takes a straight
## line that would graze a door; at worst it flies through the openings instead.
func _meets_debris(from: Vector3, to: Vector3, radius: float) -> bool:
	if _debris == null:
		return false
	for index: int in _debris.size():
		if not _debris.is_solid(index):
			continue
		var entry: float = DebrisShapes.box_entry(from, to, _debris.position(index),
			_debris.box_size(index) * 0.5 + Vector3.ONE * radius) if _debris.is_box(index) \
			else Projectile.segment_entry(from, to, _debris.position(index), _debris.radius(index) + radius)
		if entry >= 0.0:
			return true
	return false


## The node of box `box` holding `point_mm`: (box, part along x, y, z).
func _node(box: int, point_mm: Vector3i) -> Vector4i:
	var cuts: Array[Vector3i] = []
	cuts.assign(_cuts[box])
	var part: Vector3i = BoxSplit.part(cuts, point_mm)
	return Vector4i(box, part.x, part.y, part.z)


func _nodes(boxes: Array[int], point_mm: Vector3i) -> Array[Vector4i]:
	var nodes: Array[Vector4i] = []
	for box: int in boxes:
		nodes.append(_node(box, point_mm))
	return nodes


## Whether some leg of `points`, flown from `from`, has its two ends in
## different parts of a split box that holds both.
func _crosses_split(from: Vector3, points: Array[Vector3]) -> bool:
	var point: Vector3 = from
	for next: Vector3 in points:
		for box: int in _union.boxes.size():
			if _cuts[box].is_empty() or not _union.boxes[box].holds(point, 0.0) \
					or not _union.boxes[box].holds(next, 0.0):
				continue
			if _node(box, EscapePath.to_mm(point)) != _node(box, EscapePath.to_mm(next)):
				return true
		point = next
	return false


func _pair_key(low: int, high: int) -> int:
	return low * _union.boxes.size() + high


## Boxes holding a sphere of `radius` at `point`, lowest first; when none
## does (a point pressed against a wall), the one `BoxUnion.box_for` picks.
func _holding(point: Vector3, radius: float) -> Array[int]:
	var found: Array[int] = []
	for index: int in _union.boxes.size():
		if _union.boxes[index].holds(point, radius):
			found.append(index)
	if found.is_empty():
		var nearest: BoxBounds = _union.box_for(point, radius)
		if nearest != null:
			found.append(_union.boxes.find(nearest))
	return found


## The part of the segment inside `box` shrunk by `radius`, as segment
## parameters (start, end) in 0..1; start > end when there is none.
static func _span_in(box: BoxBounds, from: Vector3, to: Vector3, radius: float) -> Vector2:
	var start: float = 0.0
	var end: float = 1.0
	for axis: int in 3:
		var low: float = box.min_corner[axis] + radius
		var high: float = box.max_corner[axis] - radius
		var delta: float = to[axis] - from[axis]
		if absf(delta) < EPSILON:
			if from[axis] < low or from[axis] > high:
				return Vector2(1.0, 0.0)
			continue
		var t_low: float = (low - from[axis]) / delta
		var t_high: float = (high - from[axis]) / delta
		start = maxf(start, minf(t_low, t_high))
		end = minf(end, maxf(t_low, t_high))
		if start > end:
			return Vector2(1.0, 0.0)
	return Vector2(start, end)
