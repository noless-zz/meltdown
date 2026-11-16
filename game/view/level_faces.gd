class_name LevelFaces
extends RefCounted

## The wall quads of a box-union level (GEN-5): each face of each box, minus
## every part of it that lies inside another box of the union, so the openings
## where boxes overlap stay open. Pure geometry, kept apart from `LevelView` so
## it can be checked without building meshes.
##
## A quad is a Dictionary:
##   "box":    index of the box whose face it is part of,
##   "axis":   0, 1 or 2, the axis the face is perpendicular to,
##   "normal": unit vector along that axis, pointing into the box,
##   "min", "max": opposite corners; equal on `axis` (the face's plane).
##
## Quads are listed box by box, face by face (axis 0..2, min side then max
## side), so the same union always gives the same list.

## Lengths below this are treated as zero, so a box that only just reaches a
## face does not leave a sliver of wall.
const EPSILON_M: float = 1e-4


## Every wall quad of `union`. Read only; the union is not changed.
static func quads(union: BoxUnion) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		for axis: int in 3:
			result.append_array(_face_quads(union, index, axis, box.min_corner[axis], 1.0))
			result.append_array(_face_quads(union, index, axis, box.max_corner[axis], -1.0))
	return result


## Thin strips of `width` along the sides of `quad` that lie on an edge of its
## box's face, so a box's outline reads in the dark. A strip is lifted `lift`
## off the wall into the box, so it is never drawn in the same plane as it.
## Strips use the quad layout above; where two strips meet in a corner they
## overlap, which is harmless for an emissive outline.
static func edge_strips(quad: Dictionary, box: BoxBounds, width: float, lift: float) -> Array[Dictionary]:
	var strips: Array[Dictionary] = []
	var axis: int = quad["axis"]
	var normal: Vector3 = quad["normal"]
	var low: Vector3 = quad["min"] + normal * lift
	var high: Vector3 = quad["max"] + normal * lift
	for side_axis: int in [(axis + 1) % 3, (axis + 2) % 3]:
		var span: float = high[side_axis] - low[side_axis]
		var strip_width: float = minf(width, span)
		if absf(low[side_axis] - box.min_corner[side_axis]) < EPSILON_M:
			var strip_high: Vector3 = high
			strip_high[side_axis] = low[side_axis] + strip_width
			strips.append(_quad(quad["box"], axis, normal, low, strip_high))
		if absf(high[side_axis] - box.max_corner[side_axis]) < EPSILON_M:
			var strip_low: Vector3 = low
			strip_low[side_axis] = high[side_axis] - strip_width
			strips.append(_quad(quad["box"], axis, normal, strip_low, high))
	return strips


## Area of a quad in square metres.
static func area(quad: Dictionary) -> float:
	var size: Vector3 = quad["max"] - quad["min"]
	var axis: int = quad["axis"]
	return size[(axis + 1) % 3] * size[(axis + 2) % 3]


## The wall left of one face of box `index`: the face at `plane` on `axis`,
## with `facing` +1 for the min side (normal along +axis) and -1 for the max side.
static func _face_quads(union: BoxUnion, index: int, axis: int, plane: float, facing: float) -> Array[Dictionary]:
	var box: BoxBounds = union.boxes[index]
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var face_low: Vector2 = Vector2(box.min_corner[u], box.min_corner[v])
	var face_high: Vector2 = Vector2(box.max_corner[u], box.max_corner[v])
	# The parts of the face inside each other box, as rectangles in (u, v).
	var holes: Array[Rect2] = []
	for other_index: int in union.boxes.size():
		if other_index == index:
			continue
		var other: BoxBounds = union.boxes[other_index]
		# Strictly inside on the face's own axis: a box whose wall lies in the
		# same plane does not open this one.
		if not (other.min_corner[axis] < plane - EPSILON_M and plane + EPSILON_M < other.max_corner[axis]):
			continue
		var low: Vector2 = Vector2(maxf(face_low.x, other.min_corner[u]), maxf(face_low.y, other.min_corner[v]))
		var high: Vector2 = Vector2(minf(face_high.x, other.max_corner[u]), minf(face_high.y, other.max_corner[v]))
		if high.x - low.x > EPSILON_M and high.y - low.y > EPSILON_M:
			holes.append(Rect2(low, high - low))
	var us: Array[float] = _cuts(face_low.x, face_high.x, holes, 0)
	var vs: Array[float] = _cuts(face_low.y, face_high.y, holes, 1)
	# A grid over every hole edge: each cell is wholly wall or wholly hole.
	var wall: Array[Array] = []
	for j: int in vs.size() - 1:
		var row: Array[bool] = []
		for i: int in us.size() - 1:
			var centre: Vector2 = Vector2((us[i] + us[i + 1]) * 0.5, (vs[j] + vs[j + 1]) * 0.5)
			row.append(not _in_any(centre, holes))
		wall.append(row)
	return _merge(wall, us, vs, index, axis, plane, facing)


## Sorted, distinct cut positions on one face axis: the face's own edges and
## every hole edge.
static func _cuts(low: float, high: float, holes: Array[Rect2], component: int) -> Array[float]:
	var raw: Array[float] = [low, high]
	for hole: Rect2 in holes:
		raw.append(hole.position[component])
		raw.append(hole.end[component])
	raw.sort()
	var cuts: Array[float] = []
	for value: float in raw:
		if cuts.is_empty() or value - cuts[cuts.size() - 1] > EPSILON_M:
			cuts.append(value)
	return cuts


static func _in_any(point: Vector2, holes: Array[Rect2]) -> bool:
	for hole: Rect2 in holes:
		if point.x > hole.position.x and point.x < hole.end.x and point.y > hole.position.y and point.y < hole.end.y:
			return true
	return false


## Joins wall cells into as few rectangles as a row-first greedy pass finds:
## fewer, larger quads mean fewer triangles on the headset.
static func _merge(wall: Array[Array], us: Array[float], vs: Array[float], index: int, axis: int,
		plane: float, facing: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used: Array[Array] = []
	for row: Array in wall:
		var flags: Array[bool] = []
		flags.resize(row.size())
		flags.fill(false)
		used.append(flags)
	var normal: Vector3 = Vector3.ZERO
	normal[axis] = facing
	for j: int in wall.size():
		for i: int in wall[j].size():
			if not wall[j][i] or used[j][i]:
				continue
			var i_end: int = i + 1
			while i_end < wall[j].size() and wall[j][i_end] and not used[j][i_end]:
				i_end += 1
			var j_end: int = j + 1
			while j_end < wall.size() and _row_free(wall[j_end], used[j_end], i, i_end):
				j_end += 1
			for jj: int in range(j, j_end):
				for ii: int in range(i, i_end):
					used[jj][ii] = true
			var low: Vector3 = Vector3.ZERO
			var high: Vector3 = Vector3.ZERO
			low[axis] = plane
			high[axis] = plane
			low[(axis + 1) % 3] = us[i]
			high[(axis + 1) % 3] = us[i_end]
			low[(axis + 2) % 3] = vs[j]
			high[(axis + 2) % 3] = vs[j_end]
			result.append(_quad(index, axis, normal, low, high))
	return result


static func _row_free(row: Array, used: Array, from: int, to: int) -> bool:
	for i: int in range(from, to):
		if not row[i] or used[i]:
			return false
	return true


static func _quad(box: int, axis: int, normal: Vector3, low: Vector3, high: Vector3) -> Dictionary:
	return {"box": box, "axis": axis, "normal": normal, "min": low, "max": high}
