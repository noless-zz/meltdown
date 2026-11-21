class_name BoxSplit
extends RefCounted

## Where solid box debris splits one box of the level in two (RUN-4, MAP-2,
## #868). `OpeningClearance` only tests debris against openings, so a cave-in in
## the middle of a long tunnel, touching no opening, left the route model seeing
## a clear tunnel while `DebrisShapes` has a wall there.
##
## An entry splits a box along an axis when it leaves less than a ship's diameter
## clear across the box's whole cross-section at its place along that axis. That
## is `OpeningClearance`'s rule for a box entry, applied to a thin slice of the
## box (two millimetres deep, centred on the entry) instead of an opening, so the
## two can never disagree about how much room is left. Only box entries are
## tested, each on its own: a sphere touches the cross-section at one point and
## never closes it, and #514's cave-ins are boxes. All three axes are tested; a
## box filled end to end is split on every axis it fills.
##
## A split is a `Vector3i`: x is the debris entry's index, y the axis (0, 1, 2)
## and z the place along that axis in whole millimetres. Everything is whole
## millimetres in and out, so the answer is the same on every device (ARC-1,
## ARC-2). #869 (`OpeningGraph`) and #870 (`LevelRoute`) call this rather than
## repeat it.

## How far the slice tested reaches either side of the split's place, in mm. The
## two halves handed to `OpeningClearance` must each be lower than the other at
## both ends, so the place is kept at least this much plus one inside the box.
const SLICE_HALF_MM: int = 1


## The splits that the solid box entries of `debris` make in the box
## `box_min`..`box_max` (mm), for a ship of `ship_radius_mm`, by entry index then
## axis. Empty when `debris` is null or nothing splits the box.
static func splits(box_min: Vector3i, box_max: Vector3i, debris: MeltdownDebris,
		ship_radius_mm: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	if debris == null:
		return found
	for index: int in debris.size():
		if not debris.is_solid(index) or not debris.is_box(index):
			continue
		var at: Vector3i = debris.positions_mm[index]
		var extent: Vector3i = debris.sizes_mm[index]
		if not _overlaps(at, extent, box_min, box_max):
			continue
		var one: MeltdownDebris = _single(at, extent)
		for axis: int in 3:
			if box_max[axis] - box_min[axis] <= 2 * (SLICE_HALF_MM + 1):
				continue
			var place: int = _place(at, extent, box_min, box_max, axis)
			var first_max: Vector3i = box_max
			first_max[axis] = place + SLICE_HALF_MM
			var second_min: Vector3i = box_min
			second_min[axis] = place - SLICE_HALF_MM
			if OpeningClearance.blocked(box_min, first_max, second_min, box_max, one,
					ship_radius_mm):
				found.append(Vector3i(index, axis, place))
	return found


## Which part of a split box `point_mm` lies in, per axis: how many of `cuts`
## along that axis lie at or below it. Two points of the same box are joined only
## when their parts are equal; with no splits every point is in part zero.
static func part(cuts: Array[Vector3i], point_mm: Vector3i) -> Vector3i:
	var counts: Vector3i = Vector3i.ZERO
	for cut: Vector3i in cuts:
		if point_mm[cut.y] >= cut.z:
			counts[cut.y] += 1
	return counts


## True when split `cut` has some of `points_mm` on each side of it.
static func separates(cut: Vector3i, points_mm: Array[Vector3i]) -> bool:
	var below: bool = false
	var above: bool = false
	for point: Vector3i in points_mm:
		if point[cut.y] >= cut.z:
			above = true
		else:
			below = true
	return below and above


## True when `point_mm` lies in the box `box_min`..`box_max`, faces included.
static func holds(box_min: Vector3i, box_max: Vector3i, point_mm: Vector3i) -> bool:
	for axis: int in 3:
		if point_mm[axis] < box_min[axis] or point_mm[axis] > box_max[axis]:
			return false
	return true


## The centre of split `cut` of the box `box_min`..`box_max`: the middle of the
## box's cross-section at the split's place.
static func centre(box_min: Vector3i, box_max: Vector3i, cut: Vector3i) -> Vector3i:
	var middle: Vector3i = (box_min + box_max) / 2
	middle[cut.y] = cut.z
	return middle


## True when the entry centred on `at` with full size `extent` shares volume
## with the box. Sizes are doubled so odd millimetres stay whole.
static func _overlaps(at: Vector3i, extent: Vector3i, box_min: Vector3i,
		box_max: Vector3i) -> bool:
	for axis: int in 3:
		if 2 * at[axis] + extent[axis] <= 2 * box_min[axis] \
				or 2 * at[axis] - extent[axis] >= 2 * box_max[axis]:
			return false
	return true


## The middle of the part of the entry inside the box along `axis`, kept far
## enough inside the box for the slice test (the caller skips boxes too thin for
## that).
static func _place(at: Vector3i, extent: Vector3i, box_min: Vector3i, box_max: Vector3i,
		axis: int) -> int:
	var margin: int = SLICE_HALF_MM + 1
	var low: int = maxi(2 * at[axis] - extent[axis], 2 * box_min[axis])
	var high: int = mini(2 * at[axis] + extent[axis], 2 * box_max[axis])
	# Floor division of a sum of doubled values: halve, then halve again.
	var place: int = floori(float(low + high) / 4.0)
	return clampi(place, box_min[axis] + margin, box_max[axis] - margin)


## A debris list holding only one solid box entry, so each entry is tested alone.
static func _single(at: Vector3i, extent: Vector3i) -> MeltdownDebris:
	var one: MeltdownDebris = MeltdownDebris.new()
	one.positions_mm.append(at)
	one.radii_mm.append(0)
	one.sizes_mm.append(extent)
	one.after_ticks.append(1)
	one.skipped.append(false)
	one.elapsed_ticks = 1
	return one
