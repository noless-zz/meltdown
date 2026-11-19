class_name LineOfSight
extends RefCounted

## Where a straight line leaves the open space of a box-union level (CMB-2,
## CMB-3, GEN-5, #615). Shots and robots' sight use it, so a robot behind a
## corridor wall can neither see nor hit the ship.
##
## Space is open inside any box, but a line may only pass from one box into
## another through the volume the two share: where they overlap. Two boxes that
## merely touch, face to face, have a wall between them, as the view draws one
## (`LevelFaces` opens a face only where another box reaches strictly past it)
## and as ships feel one (a ship is held inside a single box at a time).
##
## The line is cut into one span per box it runs through. Starting from the
## spans that hold the line's start, the reach is extended by every span that
## begins strictly before the reach ends; where nothing extends it any further
## the line leaves open space. Boxes are visited in index order and the answer
## depends only on the boxes and the two points, so it is the same on every
## device (ARC-1, ARC-2).

## Two spans must share at least this much line, in metres, to join. Spans that
## only touch (boxes face to face, or a line grazing a shared edge) do not.
const MIN_OVERLAP_M: float = 0.001


## The fraction 0..1 of the segment `from`..`to` at which it first leaves the
## open space of `walls`, or -1.0 if it never does. 0.0 when `from` itself is
## outside every box. Null walls are open space everywhere.
static func exit_fraction(walls: BoxUnion, from: Vector3, to: Vector3) -> float:
	if walls == null:
		return -1.0
	var path: Vector3 = to - from
	# Fractions (enter, leave) per box the line meets, flat. Inlined rather than
	# a helper per box: this runs for every shot and armed robot every tick.
	var spans: PackedFloat64Array = []
	for box: BoxBounds in walls.boxes:
		var enter: float = 0.0
		var leave: float = 1.0
		for axis: int in 3:
			var low: float = box.min_corner[axis]
			var high: float = box.max_corner[axis]
			var start: float = from[axis]
			var along: float = path[axis]
			if along == 0.0:
				if start < low or start > high:
					leave = -1.0
					break
				continue
			var t_low: float = (low - start) / along
			var t_high: float = (high - start) / along
			if t_low > t_high:
				var swap: float = t_low
				t_low = t_high
				t_high = swap
			enter = maxf(enter, t_low)
			leave = minf(leave, t_high)
			if enter > leave:
				break
		if enter > leave:
			continue
		# One convex box holds the whole line: the common case, done.
		if enter <= 0.0 and leave >= 1.0:
			return -1.0
		spans.push_back(enter)
		spans.push_back(leave)
	var reach: float = -1.0
	for index: int in range(0, spans.size(), 2):
		if spans[index] <= 0.0:
			reach = maxf(reach, spans[index + 1])
	var length: float = path.length()
	if reach < 0.0 or length <= 0.0:
		# Outside every box; a zero-length line inside one returned above.
		return 0.0
	var overlap: float = MIN_OVERLAP_M / length
	var extended: bool = true
	while extended and reach < 1.0:
		extended = false
		for index: int in range(0, spans.size(), 2):
			if spans[index] < reach - overlap and spans[index + 1] > reach:
				reach = spans[index + 1]
				extended = true
	return -1.0 if reach >= 1.0 else reach


## True when the whole segment `from`..`to` lies in open space.
static func clear(walls: BoxUnion, from: Vector3, to: Vector3) -> bool:
	return exit_fraction(walls, from, to) < 0.0
