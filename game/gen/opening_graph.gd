class_name OpeningGraph
extends RefCounted

## A level's boxes and the openings between them, worked out once so
## `DebrisEscape` can ask many times which openings some debris blocks and
## whether the start can still be reached from the reactor (#493), without a
## full `KnownRoute` search each time: it runs for every generated level.
##
## The openings, the boxes holding each end and the blocking rule are
## `KnownRoute.find`'s with every box explored: every pair of boxes i < j that
## share volume, in order of i then j, blocked by `OpeningClearance.blocked`.
## A route exists exactly when a box holding the reactor and a box holding the
## start are joined through openings that are not blocked, which is when
## `KnownRoute.find` finds one. All in whole millimetres (ARC-2).
##
## Solid box debris across a box's whole cross-section splits that box (#868,
## #869). Which entries split which box is `BoxSplit`'s rule, called here and
## never repeated; as in `KnownRoute`, a split counts only when it separates two
## of the box's own points (its openings' centres, and the reactor or start when
## inside it), and two points of a box are joined only when they lie in the same
## part of it. Without splits every point is in part zero, so the graph is what
## it was before.

var _mins: Array[Vector3i] = []
var _maxs: Array[Vector3i] = []
## The two boxes of each opening.
var _firsts: Array[int] = []
var _seconds: Array[int] = []
var _from_boxes: Array[int] = []
var _to_boxes: Array[int] = []
var _radius_mm: int = 0
## `BoxSplit.splits` answers by (box corners, entry centre and size, ship
## radius), shared by every graph: each level builds a graph several times (the
## generator's trimming, the validator, the sweep's guard check) and `BoxSplit`
## is the dearest step. The answer depends on nothing else, so a remembered one
## is the same on every device. Emptied when it grows past `MEMO_LIMIT`.
static var _split_memo: Dictionary = {}
const MEMO_LIMIT: int = 4096

## The openings of each box, lowest first.
var _by_box: Array[Array] = []
## The centre of each opening's shared region.
var _centres: Array[Vector3i] = []
## The reactor and the start, rounded to millimetres.
var _from_mm: Vector3i = Vector3i.ZERO
var _to_mm: Vector3i = Vector3i.ZERO
## Each box's own points, which a split must separate to count.
var _own: Array[Array] = []


## The graph of `level` for a ship of `ship_radius`, from the reactor to the start.
func _init(level: LevelDef, ship_radius: float) -> void:
	_radius_mm = roundi(ship_radius * RobotSpawn.SCALE)
	var boxes: Array[BoxBounds] = level.union.boxes
	for box: BoxBounds in boxes:
		_mins.append(EscapePath.to_mm(box.min_corner))
		_maxs.append(EscapePath.to_mm(box.max_corner))
		_by_box.append([])
	for i: int in boxes.size():
		for j: int in range(i + 1, boxes.size()):
			var low: Vector3i = _mins[i].max(_mins[j])
			var high: Vector3i = _maxs[i].min(_maxs[j])
			if low.x < high.x and low.y < high.y and low.z < high.z:
				_by_box[i].append(_firsts.size())
				_by_box[j].append(_firsts.size())
				_firsts.append(i)
				_seconds.append(j)
				_centres.append((low + high) / 2)
	# The points are rounded to millimetres first, as `KnownRoute` does.
	_from_mm = EscapePath.to_mm(level.reactor.position())
	_to_mm = EscapePath.to_mm(level.start_position())
	var from: Vector3 = Vector3(_from_mm) / float(RobotSpawn.SCALE)
	var to: Vector3 = Vector3(_to_mm) / float(RobotSpawn.SCALE)
	for i: int in boxes.size():
		if boxes[i].holds(from, 0.0):
			_from_boxes.append(i)
		if boxes[i].holds(to, 0.0):
			_to_boxes.append(i)
		var own: Array[Vector3i] = []
		for end: Vector3i in [_from_mm, _to_mm]:
			if BoxSplit.holds(_mins[i], _maxs[i], end):
				own.append(end)
		for k: int in _by_box[i]:
			own.append(_centres[k])
		_own.append(own)


## How many openings the level has.
func opening_count() -> int:
	return _firsts.size()


## The openings entry `index` of `debris` could narrow, lowest first: those
## whose shared region its bounding box, grown by the ship's radius, meets.
## That is `OpeningClearance`'s reach made coarser: a sphere's disc on the
## opening's plane reaches at most its radius plus the ship's, a box's
## cross-section grows by at most the ship's radius, and each must come within
## that of the region along the crossing axis too. An entry near no opening
## can never block one.
func openings_near(debris: MeltdownDebris, index: int) -> Array[int]:
	var half: Vector3i = debris.sizes_mm[index] / 2 if debris.is_box(index) \
			else Vector3i.ONE * debris.radii_mm[index]
	# One millimetre more covers the rounding of an odd size's half.
	var reach: Vector3i = half + Vector3i.ONE * (_radius_mm + 1)
	var at: Vector3i = debris.positions_mm[index]
	var found: Array[int] = []
	for k: int in _firsts.size():
		var low: Vector3i = _mins[_firsts[k]].max(_mins[_seconds[k]]) - reach
		var high: Vector3i = _maxs[_firsts[k]].min(_maxs[_seconds[k]]) + reach
		if at.x >= low.x and at.x <= high.x and at.y >= low.y and at.y <= high.y \
				and at.z >= low.z and at.z <= high.z:
			found.append(k)
	return found


## True when the solid entries of `solid` block opening `k`.
func blocks(k: int, solid: MeltdownDebris) -> bool:
	var i: int = _firsts[k]
	var j: int = _seconds[k]
	return OpeningClearance.blocked(_mins[i], _maxs[i], _mins[j], _maxs[j], solid, _radius_mm)


## The splits entry `index` of `debris` makes once solid, as (box, entry, axis,
## place in mm), by box then axis: `BoxSplit.splits` on that entry alone, kept
## only where it separates two of the box's own points. Empty for a sphere, fire
## or an entry that splits nothing. Splits never depend on other entries, so
## the splits of any set of fallen entries are those of each one.
func splits_by(debris: MeltdownDebris, index: int) -> Array[Vector4i]:
	var found: Array[Vector4i] = []
	if not debris.is_box(index) or debris.is_fire(index):
		return found
	var one: MeltdownDebris = MeltdownDebris.new()
	one.positions_mm.append(debris.positions_mm[index])
	one.radii_mm.append(0)
	one.sizes_mm.append(debris.sizes_mm[index])
	one.after_ticks.append(1)
	one.skipped.append(false)
	one.elapsed_ticks = 1
	# Doubled so an odd size's half stays whole, as `BoxSplit` tests overlap.
	var low: Vector3i = 2 * one.positions_mm[0] - one.sizes_mm[0]
	var high: Vector3i = 2 * one.positions_mm[0] + one.sizes_mm[0]
	for box: int in _mins.size():
		# This runs for every entry of every level, so boxes the entry could not
		# split are skipped before `BoxSplit` builds anything (see `_may_split`).
		if not _may_split(low, high, 2 * _mins[box], 2 * _maxs[box]):
			continue
		for cut: Vector3i in _box_splits(box, one):
			var own: Array[Vector3i] = []
			own.assign(_own[box])
			if BoxSplit.separates(cut, own):
				found.append(Vector4i(box, index, cut.y, cut.z))
	return found


## `BoxSplit.splits` of box `box` for the one entry of `one`, remembered.
func _box_splits(box: int, one: MeltdownDebris) -> Array[Vector3i]:
	var key: Array = [_mins[box], _maxs[box], one.positions_mm[0], one.sizes_mm[0], _radius_mm]
	if _split_memo.has(key):
		return _split_memo[key]
	if _split_memo.size() >= MEMO_LIMIT:
		_split_memo.clear()
	var cuts: Array[Vector3i] = BoxSplit.splits(_mins[box], _maxs[box], one, _radius_mm)
	_split_memo[key] = cuts
	return cuts


## False when an entry spanning `low`..`high` (doubled mm) surely splits no box
## spanning `box_low`..`box_high` (doubled mm); `BoxSplit` decides the rest. That
## is `BoxSplit`'s reach made coarser, as `openings_near` coarsens
## `OpeningClearance`'s: the entry must share volume with the box, and on some
## axis come within a ship's diameter (one millimetre more for rounding) of the
## box's walls on both sides across both other axes, since the ship's line
## keeps a radius from the walls and from the entry.
func _may_split(low: Vector3i, high: Vector3i, box_low: Vector3i, box_high: Vector3i) -> bool:
	for axis: int in 3:
		if high[axis] <= box_low[axis] or low[axis] >= box_high[axis]:
			return false
	var gap: int = 2 * (2 * _radius_mm + 1)
	for axis: int in 3:
		var spans: bool = true
		for across: int in 3:
			if across != axis and (low[across] > box_low[across] + gap \
					or high[across] < box_high[across] - gap):
				spans = false
		if spans:
			return true
	return false


## True when the start can be reached from the reactor through the openings
## not marked in `closed` (one flag per opening), with the boxes split by
## `splits` (as `splits_by` gives them, in any order).
func connected(closed: Array[bool], splits: Array[Vector4i] = []) -> bool:
	if _from_boxes.is_empty() or _to_boxes.is_empty():
		return false
	if splits.is_empty():
		return _boxes_connected(closed)
	var cuts: Array[Array] = []
	for box: int in _mins.size():
		var none: Array[Vector3i] = []
		cuts.append(none)
	for split: Vector4i in splits:
		cuts[split.x].append(Vector3i(split.y, split.z, split.w))
	# A node is a part of a box: (box, part along x, y, z).
	var reached: Dictionary[Vector4i, bool] = {}
	var queue: Array[Vector4i] = []
	for box: int in _from_boxes:
		var node: Vector4i = _node(cuts, box, _from_mm)
		if not reached.has(node):
			reached[node] = true
			queue.append(node)
	var goals: Dictionary[Vector4i, bool] = {}
	for box: int in _to_boxes:
		goals[_node(cuts, box, _to_mm)] = true
	while not queue.is_empty():
		var node: Vector4i = queue.pop_back()
		if goals.has(node):
			return true
		for k: int in _by_box[node.x]:
			if closed[k] or _node(cuts, node.x, _centres[k]) != node:
				continue
			var other: int = _seconds[k] if _firsts[k] == node.x else _firsts[k]
			var next: Vector4i = _node(cuts, other, _centres[k])
			if not reached.has(next):
				reached[next] = true
				queue.append(next)
	return false


## `connected` with no box split, where every part is the whole box: the walk
## over boxes it always was, kept apart since it runs for most levels and the
## sweep's time is watched.
func _boxes_connected(closed: Array[bool]) -> bool:
	var reached: Array[bool] = []
	reached.resize(_mins.size())
	reached.fill(false)
	var queue: Array[int] = _from_boxes.duplicate()
	for box: int in queue:
		reached[box] = true
	while not queue.is_empty():
		var box: int = queue.pop_back()
		if _to_boxes.has(box):
			return true
		for k: int in _by_box[box]:
			if closed[k]:
				continue
			var other: int = _seconds[k] if _firsts[k] == box else _firsts[k]
			if not reached[other]:
				reached[other] = true
				queue.append(other)
	return false


## The part of box `box` that `point_mm` lies in, as (box, part along x, y, z):
## `BoxSplit.part`, which takes a typed list, so it is called only for a box
## that has splits; every other box is all part zero.
static func _node(cuts: Array[Array], box: int, point_mm: Vector3i) -> Vector4i:
	if cuts[box].is_empty():
		return Vector4i(box, 0, 0, 0)
	var part: Vector3i = BoxSplit.part(cuts[box], point_mm)
	return Vector4i(box, part.x, part.y, part.z)
