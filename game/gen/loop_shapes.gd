class_name LoopShapes
extends RefCounted

## Tunnel shapes for `LoopBridges` (#396, #411, GEN-5): the boxes that join two
## open connectors of the same size class facing each other along one axis.
## Each box is a corner pair [min, max] in whole millimetres, level space.
##
## A straight tunnel is the opening's square, face to face. A Z is for openings
## whose centres are offset across the axis: a leg straight out of each doorway
## towards the middle of the gap and a cross box joining the two legs there.
## The cross box is a tunnel width deep along the axis and covers both legs'
## squares across it, so each leg meets it through its whole square.
##
## Each leg reaches only `LEG_INTO_CROSS_MM` into the cross box, short of the
## middle (#472). Legs that ran half a tunnel width past the middle overlapped
## each other by a diagonal sliver when the offset was under a tunnel width on
## both axes, and in a short gap a leg reached into the far doorway box beside
## the far leg. Stopping short keeps the legs apart from each other and from
## the far doorway for every gap of at least a tunnel width, so every pair of
## boxes that meet does so through at least the connector's square.
## `joints_clear` checks that for a whole bridge.

## How far a leg reaches into the cross box along the axis. At least
## `LevelDef.MIN_OVERLAP_M`, so the two count as joined, and under half the
## smallest connector (4 m), so the two legs never meet each other.
const LEG_INTO_CROSS_MM: int = 3000


## The straight tunnel between two openings exactly in line: one box.
static func straight(from: ModuleConnector, to: ModuleConnector) -> Array[Vector3i]:
	var axis: int = from.axis()
	return _leg(from.position_mm, from.size_mm() / 2, axis, to.position_mm[axis])


## The Z between two offset openings: [leg at from, cross, leg at to], or
## empty when the gap is shorter than a tunnel width, where the legs and cross
## box would reach past the far opening into its module.
static func z_shape(from: ModuleConnector, to: ModuleConnector) -> Array[Vector3i]:
	var axis: int = from.axis()
	var outward: int = from.axis_sign()
	var width: int = from.size_mm()
	var half: int = width / 2
	var gap: int = (to.position_mm[axis] - from.position_mm[axis]) * outward
	if gap < width:
		return []
	var middle: int = from.position_mm[axis] + outward * (gap / 2)
	var reach: int = half - LEG_INTO_CROSS_MM
	var leg_from: Array[Vector3i] = _leg(from.position_mm, half, axis, middle - outward * reach)
	var leg_to: Array[Vector3i] = _leg(to.position_mm, half, axis, middle + outward * reach)
	var cross_low: Vector3i = Vector3i(
			mini(leg_from[0].x, leg_to[0].x), mini(leg_from[0].y, leg_to[0].y), mini(leg_from[0].z, leg_to[0].z))
	var cross_high: Vector3i = Vector3i(
			maxi(leg_from[1].x, leg_to[1].x), maxi(leg_from[1].y, leg_to[1].y), maxi(leg_from[1].z, leg_to[1].z))
	cross_low[axis] = middle - half
	cross_high[axis] = middle + half
	var boxes: Array[Vector3i] = []
	boxes.append_array(leg_from)
	boxes.append_array([cross_low, cross_high])
	boxes.append_array(leg_to)
	return boxes


## True if every two of `boxes` (corner pairs) that touch or overlap share an
## opening at least `width` mm on both axes across it: the two larger of the
## three overlaps. Boxes apart on any axis are skipped. Whole millimetres
## (GEN-2), and no ship radius, so `gen/` keeps its own promise (#472).
static func joints_clear(boxes: Array[Vector3i], width: int) -> bool:
	for a: int in range(0, boxes.size(), 2):
		for b: int in range(a + 2, boxes.size(), 2):
			var overlap: Array[int] = []
			for axis: int in 3:
				overlap.append(mini(boxes[a + 1][axis], boxes[b + 1][axis]) - maxi(boxes[a][axis], boxes[b][axis]))
			overlap.sort()
			if overlap[0] < 0:
				continue
			if overlap[1] < width:
				return false
	return true


## A leg: the opening's square at `centre`, from its face to `end` along `axis`.
static func _leg(centre: Vector3i, half: int, axis: int, end: int) -> Array[Vector3i]:
	var low: Vector3i = centre - Vector3i(half, half, half)
	var high: Vector3i = centre + Vector3i(half, half, half)
	low[axis] = mini(centre[axis], end)
	high[axis] = maxi(centre[axis], end)
	return [low, high]
