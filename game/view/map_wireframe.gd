class_name MapWireframe
extends RefCounted

## The line segments of the hologram map (MAP-1): the outline of each explored
## box of a box-union level (GEN-5). Outlines follow the walls `LevelFaces`
## leaves, so where a box opens onto another the opening's rim is drawn and no
## edge runs across it. Pure geometry; nothing is drawn here.
##
## Segments come as a PackedVector3Array of endpoint pairs (from, to, from, to,
## ...), the layout a line mesh takes. Collinear pieces that touch are joined
## and duplicates dropped, so a box edge shared by two faces is one segment.
## The order depends only on the union and the explored set.

const EPSILON_M: float = LevelFaces.EPSILON_M


## Outline segments of the boxes in `explored` (indices into `union.boxes`).
## Openings are cut against the whole union, so a passage into a box not yet
## explored still reads as an opening.
static func segments(union: BoxUnion, explored: Array[int]) -> PackedVector3Array:
	var wanted: Dictionary = {}
	for index: int in explored:
		wanted[index] = true
	# Wall quads of each wanted face, keyed by [box, axis, side].
	var faces: Dictionary = {}
	for quad: Dictionary in LevelFaces.quads(union):
		var box: int = quad["box"]
		if not wanted.has(box):
			continue
		var axis: int = quad["axis"]
		var side: int = 0 if (quad["normal"] as Vector3)[axis] > 0.0 else 1
		var key: Vector3i = Vector3i(box, axis, side)
		if not faces.has(key):
			var fresh: Array[Dictionary] = []
			faces[key] = fresh
		var list: Array[Dictionary] = faces[key]
		list.append(quad)
	# Pieces of lines, keyed by the line: [direction axis, the two fixed coordinates].
	var lines: Dictionary = {}
	for key: Vector3i in faces:
		var quads: Array[Dictionary] = faces[key]
		_face_outline(union.boxes[key.x], key.y, key.z, quads, lines)
	return _join(lines)


## `points` (endpoint pairs) scaled evenly so their bounds fit a cube of edge
## `edge_m`, with the bounds' centre moved to the origin. Proportions are kept;
## the longest side of the bounds becomes `edge_m`. Empty in, empty out.
static func fit_to_cube(points: PackedVector3Array, edge_m: float) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if points.is_empty():
		return result
	var low: Vector3 = points[0]
	var high: Vector3 = points[0]
	for point: Vector3 in points:
		low = low.min(point)
		high = high.max(point)
	var centre: Vector3 = (low + high) * 0.5
	var longest: float = (high - low)[(high - low).max_axis_index()]
	var scale: float = edge_m / longest if longest > EPSILON_M else 1.0
	result.resize(points.size())
	for i: int in points.size():
		result[i] = (points[i] - centre) * scale
	return result


## Adds the outline of one face's wall to `lines`: every grid edge with wall on
## one side and opening (or the face's border) on the other.
static func _face_outline(box: BoxBounds, axis: int, side: int, quads: Array[Dictionary], lines: Dictionary) -> void:
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var plane: float = box.min_corner[axis] if side == 0 else box.max_corner[axis]
	var us: Array[float] = _cuts(box.min_corner[u], box.max_corner[u], quads, u)
	var vs: Array[float] = _cuts(box.min_corner[v], box.max_corner[v], quads, v)
	var wall: Array[Array] = []
	for j: int in vs.size() - 1:
		var row: Array[bool] = []
		for i: int in us.size() - 1:
			var centre: Vector3 = Vector3.ZERO
			centre[u] = (us[i] + us[i + 1]) * 0.5
			centre[v] = (vs[j] + vs[j + 1]) * 0.5
			row.append(_in_any(centre, quads, u, v))
		wall.append(row)
	# Edges running along u, on each grid line v = vs[j].
	for j: int in vs.size():
		for i: int in us.size() - 1:
			if _cell(wall, i, j - 1) != _cell(wall, i, j):
				_add(lines, u, axis, plane, v, vs[j], us[i], us[i + 1])
	# Edges running along v, on each grid line u = us[i].
	for i: int in us.size():
		for j: int in vs.size() - 1:
			if _cell(wall, i - 1, j) != _cell(wall, i, j):
				_add(lines, v, axis, plane, u, us[i], vs[j], vs[j + 1])


## Sorted, distinct cut positions on `component` between `low` and `high`: the
## face's own edges and every quad edge.
static func _cuts(low: float, high: float, quads: Array[Dictionary], component: int) -> Array[float]:
	var raw: Array[float] = [low, high]
	for quad: Dictionary in quads:
		raw.append((quad["min"] as Vector3)[component])
		raw.append((quad["max"] as Vector3)[component])
	raw.sort()
	var cuts: Array[float] = []
	for value: float in raw:
		if cuts.is_empty() or value - cuts[cuts.size() - 1] > EPSILON_M:
			cuts.append(value)
	return cuts


static func _in_any(point: Vector3, quads: Array[Dictionary], u: int, v: int) -> bool:
	for quad: Dictionary in quads:
		var low: Vector3 = quad["min"]
		var high: Vector3 = quad["max"]
		if point[u] > low[u] and point[u] < high[u] and point[v] > low[v] and point[v] < high[v]:
			return true
	return false


## Wall flag of cell (i, j); cells off the face are not wall.
static func _cell(wall: Array[Array], i: int, j: int) -> bool:
	if j < 0 or j >= wall.size() or i < 0 or i >= (wall[j] as Array).size():
		return false
	return wall[j][i]


## Records the piece from `from` to `to` along axis `direction`, on the line
## where `fixed_a` is `value_a` and `fixed_b` is `value_b`.
static func _add(lines: Dictionary, direction: int, fixed_a: int, value_a: float, fixed_b: int,
		value_b: float, from: float, to: float) -> void:
	var fixed: Vector3 = Vector3.ZERO
	fixed[fixed_a] = value_a
	fixed[fixed_b] = value_b
	# Snapped so the same line seen from two faces or boxes has one key.
	var key: Vector4 = Vector4(direction, snappedf(fixed.x, EPSILON_M), snappedf(fixed.y, EPSILON_M),
			snappedf(fixed.z, EPSILON_M))
	if not lines.has(key):
		var fresh: Array[Vector2] = []
		lines[key] = fresh
	var pieces: Array[Vector2] = lines[key]
	pieces.append(Vector2(from, to))


## Joins touching pieces on each line and lists the segments, lines in sorted
## key order, pieces along each line from low to high.
static func _join(lines: Dictionary) -> PackedVector3Array:
	var keys: Array = lines.keys()
	keys.sort_custom(_key_before)
	var result: PackedVector3Array = PackedVector3Array()
	for key: Vector4 in keys:
		var pieces: Array[Vector2] = lines[key]
		pieces.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var merged: Array[Vector2] = []
		for piece: Vector2 in pieces:
			var last: int = merged.size() - 1
			if last >= 0 and piece.x <= merged[last].y + EPSILON_M:
				merged[last].y = maxf(merged[last].y, piece.y)
			else:
				merged.append(piece)
		var direction: int = int(key.x)
		var base: Vector3 = Vector3(key.y, key.z, key.w)
		for piece: Vector2 in merged:
			var from: Vector3 = base
			var to: Vector3 = base
			from[direction] = piece.x
			to[direction] = piece.y
			result.append(from)
			result.append(to)
	return result


static func _key_before(a: Vector4, b: Vector4) -> bool:
	for component: int in 4:
		if a[component] != b[component]:
			return a[component] < b[component]
	return false
