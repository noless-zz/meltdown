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

## Slack on the segment test, as a fraction of the segment, so that legs
## ending exactly on a shrunk wall still count as held.
const EPSILON: float = 0.000001

var _union: BoxUnion = null
## `_neighbours[i]` lists the boxes joined to box i, lowest first.
var _neighbours: Array = []


func _init(level: LevelDef) -> void:
	_union = level.union
	for index: int in _union.boxes.size():
		_neighbours.append(level.neighbours(index))


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


## The points to fly through from `from` to `to`, ending with `to`. Just
## `[to]` when the straight segment is held, or when no chain joins the two
## ends (the caller then flies straight, as without a level).
func waypoints(from: Vector3, to: Vector3, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not segment_held(_union, from, to, radius):
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
## lower indices.
func chain(from: Vector3, to: Vector3, radius: float) -> Array[int]:
	var starts: Array[int] = _holding(from, radius)
	var goals: Array[int] = _holding(to, radius)
	var previous: Array[int] = []
	previous.resize(_union.boxes.size())
	previous.fill(-2)
	var queue: Array[int] = []
	for index: int in starts:
		previous[index] = -1
		queue.append(index)
	var found: int = -1
	while not queue.is_empty() and found < 0:
		var index: int = queue.pop_front()
		if goals.has(index):
			found = index
			break
		for other: int in _neighbours[index]:
			if previous[other] == -2:
				previous[other] = index
				queue.append(other)
	var boxes: Array[int] = []
	while found >= 0:
		boxes.push_front(found)
		found = previous[found]
	return boxes


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
