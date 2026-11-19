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

var _mins: Array[Vector3i] = []
var _maxs: Array[Vector3i] = []
## The two boxes of each opening.
var _firsts: Array[int] = []
var _seconds: Array[int] = []
var _from_boxes: Array[int] = []
var _to_boxes: Array[int] = []
var _radius_mm: int = 0
## The openings of each box, lowest first.
var _by_box: Array[Array] = []


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
	# The points are rounded to millimetres first, as `KnownRoute` does.
	var from: Vector3 = Vector3(EscapePath.to_mm(level.reactor.position())) / float(RobotSpawn.SCALE)
	var to: Vector3 = Vector3(EscapePath.to_mm(level.start_position())) / float(RobotSpawn.SCALE)
	for i: int in boxes.size():
		if boxes[i].holds(from, 0.0):
			_from_boxes.append(i)
		if boxes[i].holds(to, 0.0):
			_to_boxes.append(i)


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


## True when the start can be reached from the reactor through the openings
## not marked in `closed` (one flag per opening).
func connected(closed: Array[bool]) -> bool:
	if _from_boxes.is_empty() or _to_boxes.is_empty():
		return false
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
