class_name LoopShapes
extends RefCounted

## Tunnel shapes for `LoopBridges` (#396, #411, GEN-5): the boxes that join two
## open connectors of the same size class facing each other along one axis.
## Each box is a corner pair [min, max] in whole millimetres, level space.
##
## A straight tunnel is the opening's square, face to face. A Z is for openings
## whose centres are offset across the axis: a leg straight out of each doorway
## to the middle of the gap and a cross box joining the two legs there. Each
## leg runs half a tunnel width past the middle and the cross box is a tunnel
## width deep along the axis and covers both legs' squares across it, so every
## joint overlaps by at least the tunnel's width on every axis and the passage
## is nowhere narrower than the connector.


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
	var leg_from: Array[Vector3i] = _leg(from.position_mm, half, axis, middle + outward * half)
	var leg_to: Array[Vector3i] = _leg(to.position_mm, half, axis, middle - outward * half)
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


## A leg: the opening's square at `centre`, from its face to `end` along `axis`.
static func _leg(centre: Vector3i, half: int, axis: int, end: int) -> Array[Vector3i]:
	var low: Vector3i = centre - Vector3i(half, half, half)
	var high: Vector3i = centre + Vector3i(half, half, half)
	low[axis] = mini(centre[axis], end)
	high[axis] = maxi(centre[axis], end)
	return [low, high]
