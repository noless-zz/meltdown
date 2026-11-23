class_name WallClearance
extends RefCounted

## Keeps a minimum thickness of rock between tunnels that do not connect
## (#1285, GEN-1, GEN-3, GEN-5; owner's playtest #1225): `MineGenerator`
## rejects a placement that would leave a wall thinner than `min_wall_mm`
## between one of the new boxes and a placed box it does not open into.
##
## It applies `WallGap`'s rules in whole millimetres, so a level the generator
## builds measures at least the minimum there: two boxes have a wall between
## them when they are apart (or touching) along one axis and overlap with some
## width on the other two, and they open into each other, with no wall, when
## some third box overlaps both. The doorway into the parent is such a third
## box, so the parent's rim around it is not a wall.
##
## Only pairs of a new box and a placed box are looked at: two placed boxes
## keep the wall they had, and adding boxes can only join a pair, never part
## it. A placed box is only compared when it reaches inside the new boxes'
## bounds grown by the minimum; any box overlapping a new box does too, so the
## third boxes looked for are all among those and the new ones. Nothing here
## is random, and placed boxes are visited in index order (ARC-2).
##
## `failure` is `LevelValidator`'s `wall` check of a whole level (GEN-3), so
## the 1,000-seed validator run holds every generated level to the minimum.

## The check's name, as `LevelValidator.CHECKS` lists it.
const CHECK: String = "wall"
## Slack on the metre comparison: box corners are single-precision floats, so
## a wall of exactly the minimum in millimetres may measure a hair under it.
const TOLERANCE_M: float = 0.0005


## The `wall` failure of a level whose thinnest wall between boxes that do not
## open into each other (`WallGap`) is below `min_wall_m`, else "". A minimum
## of 0 or less checks nothing.
static func failure(union: BoxUnion, min_wall_m: float) -> String:
	if min_wall_m <= 0.0:
		return ""
	var thinnest: WallGap = WallGap.of_union(union)
	if not thinnest.has_pair() or thinnest.gap_m >= min_wall_m - TOLERANCE_M:
		return ""
	return "%s: boxes %d and %d are %.3f m apart on %s with no opening between them, below %.2f m" \
			% [CHECK, thinnest.first_box, thinnest.second_box, thinnest.gap_m, "xyz"[thinnest.axis], min_wall_m]


## True when none of `boxes` (corner pairs, millimetres) leaves a wall thinner
## than `min_wall_mm` to a box of `generator` it does not open into. A minimum
## of 0 or less checks nothing.
static func clear(generator: MineGenerator, boxes: Array[Vector3i], min_wall_mm: int) -> bool:
	if min_wall_mm <= 0 or boxes.is_empty():
		return true
	var grow: Vector3i = Vector3i(min_wall_mm, min_wall_mm, min_wall_mm)
	var reach_min: Vector3i = boxes[0]
	var reach_max: Vector3i = boxes[1]
	for corner: int in range(2, boxes.size(), 2):
		reach_min = reach_min.min(boxes[corner])
		reach_max = reach_max.max(boxes[corner + 1])
	reach_min -= grow
	reach_max += grow
	# The placed boxes near enough to matter, then the new ones, as corner pairs.
	var near: Array[Vector3i] = []
	for index: int in generator.min_mm.size():
		if MineGenerator.overlaps(reach_min, reach_max, generator.min_mm[index], generator.max_mm[index]):
			near.append_array([generator.min_mm[index], generator.max_mm[index]])
	var placed: int = near.size()
	if placed == 0:
		return true
	near.append_array(boxes)
	for fresh: int in range(placed, near.size(), 2):
		for old: int in range(0, placed, 2):
			var gap: int = wall_mm(near[fresh], near[fresh + 1], near[old], near[old + 1])
			if gap < 0 or gap >= min_wall_mm:
				continue
			if not _joined(near, fresh, old):
				return false
	return true


## The rock between two boxes in millimetres as `WallGap` measures it: apart
## (or touching) on exactly one axis and overlapping on the other two; -1 when
## the pair has no such wall.
static func wall_mm(a_min: Vector3i, a_max: Vector3i, b_min: Vector3i, b_max: Vector3i) -> int:
	var gap: int = -1
	for axis: int in 3:
		var overlap: int = mini(a_max[axis], b_max[axis]) - maxi(a_min[axis], b_min[axis])
		if overlap > 0:
			continue
		if gap >= 0:
			return -1
		gap = -overlap
	return gap


## Whether a box of `pairs` other than those starting at `first` and `second`
## overlaps both.
static func _joined(pairs: Array[Vector3i], first: int, second: int) -> bool:
	for other: int in range(0, pairs.size(), 2):
		if other == first or other == second:
			continue
		if MineGenerator.overlaps(pairs[other], pairs[other + 1], pairs[first], pairs[first + 1]) \
				and MineGenerator.overlaps(pairs[other], pairs[other + 1], pairs[second], pairs[second + 1]):
			return true
	return false
