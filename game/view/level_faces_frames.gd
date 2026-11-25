class_name LevelFrames
extends RefCounted

## Frames around the openings of a box-union level (#1323, GFX-2): where one
## box opens into another, the wall around the opening gets a collar as deep
## as the wall is thick, so an opening reads as a hole through rock with mass
## rather than a cut in a sheet of paper (owner's note on #1292).
##
## An opening is a hole in a face (`LevelFaces.face_cells`). Each straight
## edge of a hole that borders wall on the same face is lined by a band
## `width` wide on the hole's side. A band is drawn as a short box sunk into
## the space behind the opening: a front quad in the wall's plane, a back
## quad `depth` behind it, and a reveal quad along its inner edge, all in
## the `LevelFaces` quad layout, so `LevelView` draws them with the walls.
##
## Only edges that meet wall at one end at least are framed: a doorway's
## lintel and jambs meet each other, while the floor of a tunnel where it
## opens into a room below runs from side wall to side wall of the tunnel and
## is left alone, so a mouth gets one frame, not a frame on each side.
##
## A frame never takes more than `MAX_SHARE` of the opening across from the
## edge it lines, so frames on opposite edges leave at least half of every
## opening clear; and it reaches at most `MAX_DEPTH_SHARE` of the space
## behind, so its back never lies in the plane of a wall there. Frames are
## drawn only: the simulation's boxes, which ships collide with, are not
## changed (ARC-3, MP-2).

const EPSILON_M: float = LevelFaces.EPSILON_M
const MAX_SHARE: float = 0.25
const MAX_DEPTH_SHARE: float = 0.5

const WALL: int = 0
const FRAME: int = 1
const OPEN: int = 2


## Every frame quad of `union` for frames `depth` deep and `width` wide.
## Listed box by box, face by face, like `LevelFaces.quads`.
static func quads(union: BoxUnion, depth: float, width: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if depth <= EPSILON_M or width <= EPSILON_M:
		return result
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		for axis: int in 3:
			result.append_array(face_frame(union, index, axis, box.min_corner[axis], 1.0, depth, width))
			result.append_array(face_frame(union, index, axis, box.max_corner[axis], -1.0, depth, width))
	return result


## The frame quads of one face of box `index`: the face at `plane` on `axis`,
## with `facing` +1 for the min side and -1 for the max side.
static func face_frame(union: BoxUnion, index: int, axis: int, plane: float, facing: float,
		depth: float, width: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells: Dictionary = LevelFaces.face_cells(union, index, axis, plane)
	var holes: Array[Rect2] = cells["holes"]
	if holes.is_empty():
		return result
	var us: Array[float] = cells["us"]
	var vs: Array[float] = cells["vs"]
	var segments: Array[Dictionary] = framed_segments(cells["wall"], us, vs)
	if segments.is_empty():
		return result
	var band: float = width
	for segment: Dictionary in segments:
		band = minf(band, MAX_SHARE * float(segment["run"]))
	if band <= EPSILON_M:
		return result
	var bands: Array[Rect2] = []
	for segment: Dictionary in segments:
		bands.append(_band(segment, us, vs, band))
	var fine_us: Array[float] = _with_cuts(us, bands, 0)
	var fine_vs: Array[float] = _with_cuts(vs, bands, 1)
	var kinds: Array[Array] = []
	var frame_cells: Array[Array] = []
	var reach: float = depth
	for j: int in fine_vs.size() - 1:
		var row: Array[int] = []
		var flags: Array[bool] = []
		for i: int in fine_us.size() - 1:
			var cell: Rect2 = Rect2(fine_us[i], fine_vs[j], fine_us[i + 1] - fine_us[i], fine_vs[j + 1] - fine_vs[j])
			var kind: int = WALL
			if LevelFaces.in_any(cell.get_center(), holes):
				kind = FRAME if LevelFaces.in_any(cell.get_center(), bands) else OPEN
			if kind == FRAME:
				reach = minf(reach, MAX_DEPTH_SHARE * room_behind(union, index, axis, plane, facing, cell))
			row.append(kind)
			flags.append(kind == FRAME)
		kinds.append(row)
		frame_cells.append(flags)
	if reach <= EPSILON_M:
		return result
	var back: float = plane - facing * reach
	result.append_array(LevelFaces.merge(frame_cells, fine_us, fine_vs, index, axis, plane, facing))
	result.append_array(LevelFaces.merge(frame_cells, fine_us, fine_vs, index, axis, back, -facing))
	result.append_array(_reveals(kinds, fine_us, fine_vs, index, axis, minf(plane, back), maxf(plane, back)))
	return result


## The straight edges of the holes in a face grid (`LevelFaces.face_cells`)
## that border wall and meet wall at one end at least. Each is a Dictionary:
##   "along": 1 for an edge running along v (wall beside it in u), 0 for u,
##   "line":  the cell index across the edge, on the hole's side,
##   "side":  -1 or +1, where the wall lies from the hole across the edge,
##   "from", "to": the first and last cell index along the edge,
##   "run":   the shortest stretch of hole straight across from the edge, in metres.
static func framed_segments(wall: Array[Array], us: Array[float], vs: Array[float]) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var columns: int = us.size() - 1
	var rows: int = vs.size() - 1
	for along: int in [1, 0]:
		var lines: int = columns if along == 1 else rows
		var length: int = rows if along == 1 else columns
		for line: int in lines:
			for side: int in [-1, 1]:
				var k: int = 0
				while k < length:
					if not _borders_wall(wall, along, line, k, side):
						k += 1
						continue
					var first: int = k
					while k < length and _borders_wall(wall, along, line, k, side):
						k += 1
					var last: int = k - 1
					if _is_wall(wall, along, line, first - 1) or _is_wall(wall, along, line, last + 1):
						segments.append({"along": along, "line": line, "side": side, "from": first, "to": last,
							"run": _run(wall, us, vs, along, line, side, first, last)})
	return segments


## The largest stretch of open space straight behind `cell` (a rectangle in
## the face's (u, v)), out of box `index` through its face at `plane`: how far
## the deepest other box over the whole cell reaches past the plane.
static func room_behind(union: BoxUnion, index: int, axis: int, plane: float, facing: float, cell: Rect2) -> float:
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var best: float = 0.0
	for other_index: int in union.boxes.size():
		if other_index == index:
			continue
		var other: BoxBounds = union.boxes[other_index]
		if not (other.min_corner[axis] < plane - EPSILON_M and plane + EPSILON_M < other.max_corner[axis]):
			continue
		if other.min_corner[u] > cell.position.x + EPSILON_M or other.max_corner[u] < cell.end.x - EPSILON_M:
			continue
		if other.min_corner[v] > cell.position.y + EPSILON_M or other.max_corner[v] < cell.end.y - EPSILON_M:
			continue
		var reach: float = plane - other.min_corner[axis] if facing > 0.0 else other.max_corner[axis] - plane
		best = maxf(best, reach)
	return best


## Cell (`line`, `k`) is hole and its neighbour on `side` across the edge is wall.
static func _borders_wall(wall: Array[Array], along: int, line: int, k: int, side: int) -> bool:
	if _is_wall(wall, along, line, k) or not _in_grid(wall, along, line, k):
		return false
	return _is_wall(wall, along, line + side, k)


static func _in_grid(wall: Array[Array], along: int, line: int, k: int) -> bool:
	var i: int = line if along == 1 else k
	var j: int = k if along == 1 else line
	return j >= 0 and j < wall.size() and i >= 0 and i < (wall[0] as Array).size()


static func _is_wall(wall: Array[Array], along: int, line: int, k: int) -> bool:
	if not _in_grid(wall, along, line, k):
		return false
	var i: int = line if along == 1 else k
	var j: int = k if along == 1 else line
	return wall[j][i]


## Shortest run of hole cells away from the wall, over the edge's cells.
static func _run(wall: Array[Array], us: Array[float], vs: Array[float], along: int, line: int, side: int,
		first: int, last: int) -> float:
	var cuts: Array[float] = us if along == 1 else vs
	var shortest: float = INF
	for k: int in range(first, last + 1):
		var step: int = line
		while _in_grid(wall, along, step, k) and not _is_wall(wall, along, step, k):
			step -= side
		# Hole cells run from `line` up to, not including, `step`.
		var near: float = cuts[line] if side < 0 else cuts[line + 1]
		var far: float = cuts[step] if side < 0 else cuts[step + 1]
		shortest = minf(shortest, absf(near - far))
	return shortest


## The band `band` wide on the hole's side of `segment`, as a Rect2 in (u, v).
static func _band(segment: Dictionary, us: Array[float], vs: Array[float], band: float) -> Rect2:
	var along: int = segment["along"]
	var line: int = segment["line"]
	var side: int = segment["side"]
	var across: Array[float] = us if along == 1 else vs
	var lengthwise: Array[float] = vs if along == 1 else us
	var edge: float = across[line] if side < 0 else across[line + 1]
	var low: float = edge if side < 0 else edge - band
	var start: float = lengthwise[int(segment["from"])]
	var end: float = lengthwise[int(segment["to"]) + 1]
	if along == 1:
		return Rect2(low, start, band, end - start)
	return Rect2(start, low, end - start, band)


## `base` with every band edge on `component` added, sorted and distinct.
static func _with_cuts(base: Array[float], bands: Array[Rect2], component: int) -> Array[float]:
	var raw: Array[float] = base.duplicate()
	for band: Rect2 in bands:
		raw.append(band.position[component])
		raw.append(band.end[component])
	raw.sort()
	var cuts: Array[float] = []
	for value: float in raw:
		if cuts.is_empty() or value - cuts[cuts.size() - 1] > EPSILON_M:
			cuts.append(value)
	return cuts


## The inner sides of the frame: wherever a frame cell meets open hole or the
## face's border, a quad from `near` to `far` on `axis`, facing away from the frame.
static func _reveals(kinds: Array[Array], us: Array[float], vs: Array[float], index: int, axis: int,
		near: float, far: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var rows: int = kinds.size()
	var columns: int = (kinds[0] as Array).size()
	for along: int in [1, 0]:
		var lines: int = columns if along == 1 else rows
		var length: int = rows if along == 1 else columns
		var across_axis: int = u if along == 1 else v
		var length_axis: int = v if along == 1 else u
		var across: Array[float] = us if along == 1 else vs
		var lengthwise: Array[float] = vs if along == 1 else us
		for line: int in lines:
			for side: int in [-1, 1]:
				var k: int = 0
				while k < length:
					if not _faces_open(kinds, along, line, k, side):
						k += 1
						continue
					var first: int = k
					while k < length and _faces_open(kinds, along, line, k, side):
						k += 1
					var low: Vector3 = Vector3.ZERO
					var high: Vector3 = Vector3.ZERO
					var at: float = across[line] if side < 0 else across[line + 1]
					low[across_axis] = at
					high[across_axis] = at
					low[length_axis] = lengthwise[first]
					high[length_axis] = lengthwise[k]
					low[axis] = near
					high[axis] = far
					var normal: Vector3 = Vector3.ZERO
					normal[across_axis] = float(side)
					result.append(LevelFaces.make_quad(index, across_axis, normal, low, high))
	return result


## Cell (`line`, `k`) is frame and its neighbour on `side` is open hole or off the face.
static func _faces_open(kinds: Array[Array], along: int, line: int, k: int, side: int) -> bool:
	if _kind(kinds, along, line, k) != FRAME:
		return false
	var next: int = _kind(kinds, along, line + side, k)
	return next == OPEN or next == -1


static func _kind(kinds: Array[Array], along: int, line: int, k: int) -> int:
	var i: int = line if along == 1 else k
	var j: int = k if along == 1 else line
	if j < 0 or j >= kinds.size() or i < 0 or i >= (kinds[0] as Array).size():
		return -1
	return kinds[j][i]
