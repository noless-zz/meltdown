class_name GuideLightPlacement
extends RefCounted

## Where the guide light strips of a box-union level go (#1463): a pure
## function of the boxes and the openings `LevelFaces` already finds, worked
## out in the view so the level and simulation hashes do not change (ARC-1,
## ARC-2). The rules come from `GuideLightRules`.
##
## A strip is a quad in `LevelFaces` layout ("box", "axis", "normal", "min",
## "max", lying in the face's plane) plus "part": `corner` for a strip along
## the box's edges, `frame` for one around an opening. No strip lies inside an
## opening or within `margin_m` of one, except the frame that rings it there.

const PART_CORNER: String = "corner"
const PART_FRAME: String = "frame"
const EPSILON_M: float = LevelFaces.EPSILON_M
## How far a strip stands off its wall, so it never fights the wall for depth.
const LIFT_M: float = 0.02


## The kind of each box of `union` by `rules` (see `GuideLightRules`).
## `reactor` is the reactor's position in the union's space, or null.
static func kinds(union: BoxUnion, rules: Dictionary, reactor: Variant) -> Array[String]:
	var result: Array[String] = []
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		var size: Vector3 = box.max_corner - box.min_corner
		var sides: Array[float] = [size.x, size.y, size.z]
		sides.sort()
		if reactor is Vector3 and _holds(box, reactor as Vector3):
			result.append(GuideLightRules.KIND_REACTOR)
		elif openings(union, index) >= int(rules["junction_openings"]):
			result.append(GuideLightRules.KIND_JUNCTION)
		elif sides[1] <= float(rules["tunnel_up_to_width_m"]):
			result.append(GuideLightRules.KIND_TUNNEL)
		else:
			result.append(GuideLightRules.KIND_ROOM)
	return result


## How many other boxes box `index` opens into: those it overlaps.
static func openings(union: BoxUnion, index: int) -> int:
	var count: int = 0
	for other: int in union.boxes.size():
		if other != index and _overlap(union.boxes[index], union.boxes[other]):
			count += 1
	return count


## Every strip of `union`, box by box and face by face as `LevelFaces` lists
## them, so the same union always gives the same list. `kinds` from `kinds`.
static func strips(union: BoxUnion, rules: Dictionary, kinds: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		var outline: bool = kinds[index] != GuideLightRules.KIND_TUNNEL
		for axis: int in 3:
			result.append_array(_face(union, index, axis, box.min_corner[axis], 1.0, rules, outline))
			result.append_array(_face(union, index, axis, box.max_corner[axis], -1.0, rules, outline))
	return result


## The six corners of the two triangles that draw `strip`, `LIFT_M` off its
## wall towards the inside of its box.
static func triangles(strip: Dictionary) -> Array[Vector3]:
	var lift: Vector3 = (strip["normal"] as Vector3) * LIFT_M
	var corners: Array[Vector3] = LevelViewMeshes.quad_triangles(strip)
	for i: int in corners.size():
		corners[i] += lift
	return corners


## The strips on one face of box `index`, at `plane` on `axis`; `facing` +1 for
## the min side. `outline` puts corner strips along every edge of the face;
## otherwise only along the box's longest axis.
static func _face(union: BoxUnion, index: int, axis: int, plane: float, facing: float, rules: Dictionary,
		outline: bool) -> Array[Dictionary]:
	var box: BoxBounds = union.boxes[index]
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var width: float = float(rules["width_m"])
	var margin: float = float(rules["margin_m"])
	var face: Rect2 = Rect2(Vector2(box.min_corner[u], box.min_corner[v]),
			Vector2(box.max_corner[u] - box.min_corner[u], box.max_corner[v] - box.min_corner[v]))
	var inner: Rect2 = face.grow(-float(rules["inset_m"]))
	if inner.size.x < width or inner.size.y < width:
		return []
	var holes: Array[Rect2] = []
	holes.assign(LevelFaces.face_cells(union, index, axis, plane)["holes"])
	var run: int = _longest_axis(box)
	# Each candidate is [rect, part, dash component or -1 for solid].
	var candidates: Array[Array] = []
	if (outline or run == u) and inner.size.y >= 2.0 * width:
		candidates.append([Rect2(inner.position, Vector2(inner.size.x, width)), PART_CORNER, 0])
		candidates.append([Rect2(Vector2(inner.position.x, inner.end.y - width), Vector2(inner.size.x, width)),
				PART_CORNER, 0])
	if (outline or run == v) and inner.size.x >= 2.0 * width:
		candidates.append([Rect2(inner.position, Vector2(width, inner.size.y)), PART_CORNER, 1])
		candidates.append([Rect2(Vector2(inner.end.x - width, inner.position.y), Vector2(width, inner.size.y)),
				PART_CORNER, 1])
	for hole: Rect2 in holes:
		for ring: Rect2 in ring_rects(hole, margin, width):
			var clipped: Rect2 = ring.intersection(inner)
			if clipped.has_area():
				candidates.append([clipped, PART_FRAME, -1])
	# Cut a hair less than the margin, so a frame exactly at the margin stays.
	var keep_clear: float = maxf(margin - EPSILON_M * 10.0, 0.0)
	var result: Array[Dictionary] = []
	for candidate: Array in candidates:
		var pieces: Array[Rect2] = [candidate[0]]
		for hole: Rect2 in holes:
			var cut: Array[Rect2] = []
			for piece: Rect2 in pieces:
				cut.append_array(subtract(piece, hole.grow(keep_clear)))
			pieces = cut
		if int(candidate[2]) >= 0:
			pieces = dashes(pieces, int(candidate[2]), float(rules["spacing_m"]), float(rules["length_m"]))
		for piece: Rect2 in pieces:
			# A scrap shorter than the strip is wide reads as a dot, not a line.
			if maxf(piece.size.x, piece.size.y) < width - EPSILON_M or minf(piece.size.x, piece.size.y) < EPSILON_M:
				continue
			result.append(_quad(index, axis, plane, facing, piece, candidate[1]))
	return result


## The four strips `width` wide that ring `hole` `margin` outside its edge.
static func ring_rects(hole: Rect2, margin: float, width: float) -> Array[Rect2]:
	var inner: Rect2 = hole.grow(margin)
	var outer: Rect2 = inner.grow(width)
	return [
		Rect2(outer.position, Vector2(outer.size.x, width)),
		Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, width)),
		Rect2(Vector2(outer.position.x, inner.position.y), Vector2(width, inner.size.y)),
		Rect2(Vector2(inner.end.x, inner.position.y), Vector2(width, inner.size.y)),
	]


## `rect` without the part inside `cut`: up to four rectangles.
static func subtract(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	var overlap: Rect2 = rect.intersection(cut)
	if overlap.size.x <= EPSILON_M or overlap.size.y <= EPSILON_M:
		return [rect]
	var parts: Array[Rect2] = [
		Rect2(rect.position, Vector2(overlap.position.x - rect.position.x, rect.size.y)),
		Rect2(Vector2(overlap.end.x, rect.position.y), Vector2(rect.end.x - overlap.end.x, rect.size.y)),
		Rect2(Vector2(overlap.position.x, rect.position.y), Vector2(overlap.size.x, overlap.position.y - rect.position.y)),
		Rect2(Vector2(overlap.position.x, overlap.end.y), Vector2(overlap.size.x, rect.end.y - overlap.end.y)),
	]
	var result: Array[Rect2] = []
	for part: Rect2 in parts:
		if part.size.x > EPSILON_M and part.size.y > EPSILON_M:
			result.append(part)
	return result


## `pieces` cut into dashes `length` long every `spacing` along `component`
## (0 for x, 1 for y). Dashes are anchored to the level's own coordinates,
## so where they fall does not depend on where a strip starts.
static func dashes(pieces: Array[Rect2], component: int, spacing: float, length: float) -> Array[Rect2]:
	if length >= spacing - EPSILON_M:
		return pieces
	var result: Array[Rect2] = []
	for piece: Rect2 in pieces:
		var low: float = piece.position[component]
		var high: float = piece.end[component]
		var step: int = floori(low / spacing)
		while float(step) * spacing < high:
			var start: float = maxf(float(step) * spacing, low)
			var end: float = minf(float(step) * spacing + length, high)
			if end - start > EPSILON_M:
				var dash: Rect2 = piece
				dash.position[component] = start
				dash.size[component] = end - start
				result.append(dash)
			step += 1
	return result


static func _quad(index: int, axis: int, plane: float, facing: float, rect: Rect2, part: String) -> Dictionary:
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var low: Vector3 = Vector3.ZERO
	var high: Vector3 = Vector3.ZERO
	low[axis] = plane
	high[axis] = plane
	low[u] = rect.position.x
	high[u] = rect.end.x
	low[v] = rect.position.y
	high[v] = rect.end.y
	var normal: Vector3 = Vector3.ZERO
	normal[axis] = facing
	var quad: Dictionary = LevelFaces.make_quad(index, axis, normal, low, high)
	quad["part"] = part
	return quad


## The axis the box is longest along; the lowest on a tie.
static func _longest_axis(box: BoxBounds) -> int:
	var size: Vector3 = box.max_corner - box.min_corner
	var best: int = 0
	for axis: int in [1, 2]:
		if size[axis] > size[best] + EPSILON_M:
			best = axis
	return best


static func _holds(box: BoxBounds, point: Vector3) -> bool:
	for axis: int in 3:
		if point[axis] < box.min_corner[axis] or point[axis] > box.max_corner[axis]:
			return false
	return true


static func _overlap(a: BoxBounds, b: BoxBounds) -> bool:
	for axis: int in 3:
		if a.max_corner[axis] <= b.min_corner[axis] + EPSILON_M \
				or b.max_corner[axis] <= a.min_corner[axis] + EPSILON_M:
			return false
	return true
