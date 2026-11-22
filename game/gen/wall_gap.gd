class_name WallGap
extends RefCounted

## The thinnest rock between two tunnels of a box-union level (#1240, GEN-3,
## GEN-5): measured so a wall-thickness rule can be decided on evidence after
## the playtest that saw robots through walls (#1225). It only measures; the
## generator is unchanged.
##
## The air is the union of the boxes; everything else is rock. A wall gap is
## found between a face of box A and the parallel face of box B beyond it on
## the same axis, the two facing away from each other with rock between
## (`b.min >= a.max` on that axis), where the faces overlap in projection. Two
## boxes that overlap open into each other and give no gap. Two boxes that only
## touch are walled off from each other (a ship is kept in one box at a time by
## `BoxUnion`, which is why the generator adds a doorway box at every join), so
## they give a gap of 0 m, unless a third box straddles the shared face inside
## the touching area: that is the doorway, and the pair is joined. Where
## other boxes fill the space between the faces (a connector, or a box that
## opens through A's face), that part does not count: a pair counts only if
## some part of the overlap has rock all the way across.
##
## Deterministic (ARC-1, ARC-2): plain loops in box order, ties to the lowest
## indices, no randomness or nodes.

## Below this an overlap or a gap is treated as none, in metres; corners are
## single-precision vectors, so far smaller differences are rounding.
const EPSILON: float = 1e-4


## `{"gap_m": float, "box_a": int, "box_b": int}` for the thinnest wall in
## `union`: the gap in metres and the indices of the two boxes, the lower
## index first. `gap_m` is INF and both indices -1 when no pair has rock
## between facing walls.
static func thinnest(union: BoxUnion) -> Dictionary:
	var best: Dictionary = {"gap_m": INF, "box_a": -1, "box_b": -1}
	var boxes: Array[BoxBounds] = union.boxes
	for i: int in boxes.size():
		for j: int in range(i + 1, boxes.size()):
			var gap: float = pair_gap(boxes, i, j)
			if gap < float(best["gap_m"]):
				best = {"gap_m": gap, "box_a": i, "box_b": j}
	return best


## The rock between boxes `i` and `j` of `boxes` on the one axis they are apart
## on with faces overlapping across it, or INF when there is none.
static func pair_gap(boxes: Array[BoxBounds], i: int, j: int) -> float:
	var a: BoxBounds = boxes[i]
	var b: BoxBounds = boxes[j]
	var found: float = INF
	for axis: int in 3:
		var low: BoxBounds = a if a.max_corner[axis] <= b.min_corner[axis] else b
		var high: BoxBounds = b if low == a else a
		var gap: float = high.min_corner[axis] - low.max_corner[axis]
		if gap < -EPSILON or gap >= found:
			continue
		var u: int = (axis + 1) % 3
		var v: int = (axis + 2) % 3
		var rect: Rect2 = _overlap(a, b, u, v)
		if rect.size.x <= EPSILON or rect.size.y <= EPSILON:
			continue
		if gap <= EPSILON:
			if not _doorway(boxes, i, j, axis, high.min_corner[axis], rect):
				found = 0.0
			continue
		if _rock_across(boxes, i, j, axis, low.max_corner[axis], high.min_corner[axis], rect):
			found = gap
	return found


## Whether some part of `rect` (in axes u, v after `axis`) has no other box
## filling the slab between `from` and `to` along `axis`.
static func _rock_across(boxes: Array[BoxBounds], i: int, j: int, axis: int, from: float, to: float,
		rect: Rect2) -> bool:
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var covers: Array[Rect2] = []
	for k: int in boxes.size():
		if k == i or k == j:
			continue
		var box: BoxBounds = boxes[k]
		if box.max_corner[axis] <= from + EPSILON or box.min_corner[axis] >= to - EPSILON:
			continue
		var shadow: Rect2 = rect.intersection(Rect2(box.min_corner[u], box.min_corner[v],
			box.max_corner[u] - box.min_corner[u], box.max_corner[v] - box.min_corner[v]))
		if shadow.size.x > EPSILON and shadow.size.y > EPSILON:
			covers.append(shadow)
	if covers.is_empty():
		return true
	# Cut the rectangle at every cover's edges; a cell no cover holds is rock.
	var xs: Array[float] = [rect.position.x, rect.end.x]
	var ys: Array[float] = [rect.position.y, rect.end.y]
	for cover: Rect2 in covers:
		xs.append_array([cover.position.x, cover.end.x])
		ys.append_array([cover.position.y, cover.end.y])
	xs.sort()
	ys.sort()
	for xi: int in xs.size() - 1:
		if xs[xi + 1] - xs[xi] <= EPSILON:
			continue
		for yi: int in ys.size() - 1:
			if ys[yi + 1] - ys[yi] <= EPSILON:
				continue
			var centre: Vector2 = Vector2((xs[xi] + xs[xi + 1]) * 0.5, (ys[yi] + ys[yi + 1]) * 0.5)
			if not _covered(covers, centre):
				return true
	return false


## Whether a box other than `i` and `j` reaches through the plane at `plane`
## along `axis` inside `rect`: a doorway between two touching boxes.
static func _doorway(boxes: Array[BoxBounds], i: int, j: int, axis: int, plane: float,
		rect: Rect2) -> bool:
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	for k: int in boxes.size():
		if k == i or k == j:
			continue
		var box: BoxBounds = boxes[k]
		if box.min_corner[axis] >= plane - EPSILON or box.max_corner[axis] <= plane + EPSILON:
			continue
		var shadow: Rect2 = rect.intersection(Rect2(box.min_corner[u], box.min_corner[v],
			box.max_corner[u] - box.min_corner[u], box.max_corner[v] - box.min_corner[v]))
		if shadow.size.x > EPSILON and shadow.size.y > EPSILON:
			return true
	return false


static func _covered(covers: Array[Rect2], point: Vector2) -> bool:
	for cover: Rect2 in covers:
		if cover.has_point(point):
			return true
	return false


## The overlap of `a` and `b` projected on axes `u` and `v`; empty or negative
## size when they do not overlap.
static func _overlap(a: BoxBounds, b: BoxBounds, u: int, v: int) -> Rect2:
	var min_u: float = maxf(a.min_corner[u], b.min_corner[u])
	var min_v: float = maxf(a.min_corner[v], b.min_corner[v])
	var max_u: float = minf(a.max_corner[u], b.max_corner[u])
	var max_v: float = minf(a.max_corner[v], b.max_corner[v])
	return Rect2(min_u, min_v, max_u - min_u, max_v - min_v)
