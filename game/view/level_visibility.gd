class_name LevelVisibility
extends RefCounted

## Which boxes of a box-union level can be seen from an eye (#1364, GFX-3,
## PRF-2): the box holding the eye, and every box seen through the openings
## (portals) between boxes. An opening is the shared volume of two boxes that
## overlap, as `LevelFaces` leaves it open and `OpeningGraph` counts it.
##
## From each box holding the eye the search passes through an opening only when
## the opening lies inside the view window narrowed by the openings already
## passed, and narrows the window to it. The window is a rectangle of view
## tangents (x / depth, y / depth). Every step is conservative, so a box that
## could be seen is never hidden:
##
## - an opening is grown by `margin_m` on every side before it is projected, so
##   an eye up to that far from the one given (each eye of a headset, or a head
##   that moved after the pose was read) sees nothing outside the result;
## - the window of an opening is the bounding rectangle of its part at least
##   `near_m` in front of the eye, which holds everything seen through it; an
##   eye so near an opening that the cut could lose a sight line gets no
##   narrowing there, and an opening with nothing in front of the cut is skipped;
## - a box reached again with a window inside one it was already searched with
##   is not searched again; past `max_steps` every box is drawn;
## - an eye outside every box (grown by `margin_m`) draws every box.
##
## It reads the union once and keeps its own copy; the simulation is never
## touched (MP-2). Pure maths, so tests drive it without a scene.

const EPSILON_M: float = LevelFaces.EPSILON_M

## The settings `visible` uses when none are given; see `LevelVisibilitySettings`.
const DEFAULTS: Dictionary = {
	"enabled": true,
	"tan_half_width": 1.8,
	"tan_half_height": 1.6,
	"near_m": 0.02,
	"margin_m": 0.15,
	"max_steps": 4096,
}

var _mins: Array[Vector3] = []
var _maxs: Array[Vector3] = []
## Per box, the openings out of it: [other box, opening min, opening max].
var _openings: Array[Array] = []
var _opening_count: int = 0

## Steps the last `visible` call took; `max_steps` + 1 when it gave up.
var last_steps: int = 0


func _init(union: BoxUnion) -> void:
	for box: BoxBounds in union.boxes:
		_mins.append(box.min_corner)
		_maxs.append(box.max_corner)
		_openings.append([])
	for i: int in _mins.size():
		for j: int in range(i + 1, _mins.size()):
			var low: Vector3 = _mins[i].max(_mins[j])
			var high: Vector3 = _maxs[i].min(_maxs[j])
			var size: Vector3 = high - low
			if size.x > EPSILON_M and size.y > EPSILON_M and size.z > EPSILON_M:
				_openings[i].append([j, low, high])
				_openings[j].append([i, low, high])
				_opening_count += 1


func box_count() -> int:
	return _mins.size()


func opening_count() -> int:
	return _opening_count


## The boxes holding `point` grown by `margin`, lowest first.
func boxes_at(point: Vector3, margin: float) -> Array[int]:
	var result: Array[int] = []
	for index: int in _mins.size():
		var low: Vector3 = _mins[index] - Vector3.ONE * margin
		var high: Vector3 = _maxs[index] + Vector3.ONE * margin
		if point.x >= low.x and point.y >= low.y and point.z >= low.z \
				and point.x <= high.x and point.y <= high.y and point.z <= high.z:
			result.append(index)
	return result


## One flag per box, true where the box may be seen from an eye at `eye`
## looking along -Z of `basis` (both in the level's space), under `settings`
## (`DEFAULTS` layout). With `enabled` false every box is drawn.
func visible(eye: Vector3, basis: Basis, settings: Dictionary = DEFAULTS) -> Array[bool]:
	var flags: Array[bool] = []
	flags.resize(_mins.size())
	flags.fill(false)
	last_steps = 0
	var margin: float = float(settings["margin_m"])
	var starts: Array[int] = boxes_at(eye, margin)
	if not bool(settings["enabled"]) or starts.is_empty():
		flags.fill(true)
		return flags
	var to_view: Basis = basis.orthonormalized().inverse()
	var full: Rect2 = Rect2(-float(settings["tan_half_width"]), -float(settings["tan_half_height"]),
			2.0 * float(settings["tan_half_width"]), 2.0 * float(settings["tan_half_height"]))
	var near: float = float(settings["near_m"])
	# The farthest a point in the window at depth `near` can be from the eye.
	var reach: float = near * Vector3(full.end.x, full.end.y, 1.0).length()
	var max_steps: int = int(settings["max_steps"])
	var searched: Array[Array] = []
	for index: int in _mins.size():
		searched.append([])
	var stack: Array[Array] = []
	for start: int in starts:
		flags[start] = true
		searched[start].append(full)
		stack.append([start, full])
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var window: Rect2 = top[1]
		for opening: Array in _openings[int(top[0])]:
			last_steps += 1
			if last_steps > max_steps:
				flags.fill(true)
				return flags
			var seen: Array = window_through(opening[1], opening[2], eye, to_view, margin, near, reach)
			if not bool(seen[0]):
				continue
			var narrowed: Rect2 = window
			if seen[1] != null:
				var cut: Rect2 = seen[1]
				var low: Vector2 = window.position.max(cut.position)
				var high: Vector2 = window.end.min(cut.end)
				# Touching edges still count, so a sight line along the edge is kept.
				if high.x < low.x or high.y < low.y:
					continue
				narrowed = Rect2(low, high - low)
			var other: int = opening[0]
			if _covered(searched[other], narrowed):
				continue
			flags[other] = true
			searched[other].append(narrowed)
			stack.append([other, narrowed])
	return flags


## Whether an opening from `low` to `high` can be seen from `eye` (with
## `to_view` taking level directions into the eye's frame), as [seen, window]:
## window is the rectangle of view tangents the grown opening covers, or null
## when it cannot narrow the view. The opening is cut at `near` in front of the
## eye and the part beyond is projected exactly (its corners and where its
## edges cross the cut). Any part nearer than the cut that lies in the window
## is within `reach` of the eye, so an eye that close to the opening gets no
## narrowing; farther away, nothing in the window is lost by the cut.
static func window_through(low: Vector3, high: Vector3, eye: Vector3, to_view: Basis, margin: float,
		near: float, reach: float) -> Array:
	var grown: AABB = AABB(low, high - low).grow(margin)
	var closest: Vector3 = eye.clamp(grown.position, grown.end)
	if closest.distance_to(eye) <= reach:
		return [true, null]
	var points: Array[Vector3] = []
	for corner: int in 8:
		points.append(to_view * (grown.get_endpoint(corner) - eye))
	var tangents: Array[Vector2] = []
	for corner: int in 8:
		var depth: float = -points[corner].z
		if depth >= near:
			tangents.append(Vector2(points[corner].x, points[corner].y) / depth)
		for axis: int in 3:
			var other: int = corner | (1 << axis)
			if other == corner:
				continue
			var other_depth: float = -points[other].z
			if (depth - near) * (other_depth - near) < 0.0:
				var share: float = (depth - near) / (depth - other_depth)
				var cut: Vector3 = points[corner].lerp(points[other], share)
				tangents.append(Vector2(cut.x, cut.y) / near)
	if tangents.is_empty():
		return [false, null]
	var bounds: Rect2 = Rect2(tangents[0], Vector2.ZERO)
	for tangent: Vector2 in tangents:
		bounds = bounds.expand(tangent)
	return [true, bounds]


static func _covered(windows: Array, window: Rect2) -> bool:
	for known: Rect2 in windows:
		if known.encloses(window):
			return true
	return false
