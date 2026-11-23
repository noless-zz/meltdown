class_name WallGap
extends RefCounted

## The thinnest rock between two tunnels of a box-union level (#1240, GEN-3,
## GEN-5): the smallest distance from a wall face of one box to a parallel wall
## face of another box that faces away from it, where the two faces overlap in
## projection. That is two boxes apart along one axis (or touching, a gap of 0)
## while their spans overlap, with some area, on the other two. Boxes that
## overlap on every axis open into each other and have no wall between them;
## boxes apart on two or three axes only meet at an edge or a corner, so their
## faces never overlap in projection.
##
## Two boxes also open into each other when a third box overlaps both: the
## doorway or loop bridge between two modules. The generator places modules
## face to face with a doorway box across the shared face, so without this
## rule every generated level measures 0 m, the rim around a doorway, between
## two rooms that see each other through that doorway anyway. With
## `count_joined` such pairs are measured too, for that number on its own.
## A third box that fills only part of the rock between a pair that is not
## joined is not looked at: the gap is the rock beside it.
##
## Measured so that a minimum wall thickness could be decided on evidence
## (owner's playtest #1225). `LevelValidator`'s `wall` check reads it through
## `WallClearance`, which also keeps the generator to the same rules (#1285).
##
## Boxes are compared in index order and a pair only replaces a smaller-index
## pair with a strictly smaller gap, so the result depends only on the box list
## (ARC-1, ARC-2).

## The smallest gap in metres, or `INF` when no pair of faces qualifies.
var gap_m: float = INF
## The pair's box indices, the lower one first; -1 when there is none.
var first_box: int = -1
var second_box: int = -1
## The axis the two boxes are apart on (0 x, 1 y, 2 z); -1 when there is none.
var axis: int = -1


## The thinnest wall between any two of `boxes` that do not open into each
## other; with `count_joined`, pairs joined through a third box count too.
static func measure(boxes: Array[BoxBounds], count_joined: bool = false) -> WallGap:
	var best: WallGap = WallGap.new()
	for first: int in boxes.size():
		for second: int in range(first + 1, boxes.size()):
			var apart: int = _apart_axis(boxes[first], boxes[second])
			if apart < 0:
				continue
			var gap: float = _gap(boxes[first], boxes[second], apart)
			if gap >= best.gap_m:
				continue
			if not count_joined and _joined(boxes, first, second):
				continue
			best.gap_m = gap
			best.first_box = first
			best.second_box = second
			best.axis = apart
	return best


## The thinnest wall of a level's union, as `measure` gives it.
static func of_union(union: BoxUnion, count_joined: bool = false) -> WallGap:
	return measure(union.boxes, count_joined)


## Whether a pair was found.
func has_pair() -> bool:
	return first_box >= 0


## The one axis `a` and `b` are apart (or touching) on while overlapping with
## some width on both others, or -1 when there is no such axis.
static func _apart_axis(a: BoxBounds, b: BoxBounds) -> int:
	var apart: int = -1
	for each: int in 3:
		var overlap: float = minf(a.max_corner[each], b.max_corner[each]) \
				- maxf(a.min_corner[each], b.min_corner[each])
		if overlap > 0.0:
			continue
		if apart >= 0:
			return -1
		apart = each
	return apart


## Whether some box other than `first` and `second` overlaps both.
static func _joined(boxes: Array[BoxBounds], first: int, second: int) -> bool:
	for other: int in boxes.size():
		if other == first or other == second:
			continue
		if _overlaps(boxes[other], boxes[first]) and _overlaps(boxes[other], boxes[second]):
			return true
	return false


## Whether `a` and `b` share some volume.
static func _overlaps(a: BoxBounds, b: BoxBounds) -> bool:
	for each: int in 3:
		if minf(a.max_corner[each], b.max_corner[each]) <= maxf(a.min_corner[each], b.min_corner[each]):
			return false
	return true


static func _gap(a: BoxBounds, b: BoxBounds, along: int) -> float:
	return maxf(a.min_corner[along], b.min_corner[along]) - minf(a.max_corner[along], b.max_corner[along])
