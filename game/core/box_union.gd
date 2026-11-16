class_name BoxUnion
extends RefCounted

## Level walls as a union of axis-aligned boxes: rooms, tunnels and shafts that
## overlap where they join (FLT-3, GEN-5). Space is open where any box is open.
##
## Each tick a sphere is kept inside one box only, picked by `box_for`, so
## ships, robots and salvage keep the per-box wall rules of `BoxBounds`. Boxes
## are checked in index order and ties go to the lower index, so the result
## depends only on the box list and the inputs (ARC-1, ARC-2).

## The boxes, in the order given. Not copied: a level builds the list once.
var boxes: Array[BoxBounds] = []


func _init(p_boxes: Array[BoxBounds] = []) -> void:
	boxes = p_boxes


## The box that should contain a sphere of `radius` at `point`: the lowest-index
## box that holds it whole; if none does, the box whose interior shrunk by
## `radius` is nearest to the point (ties to the lower index). Null only for an
## empty union.
func box_for(point: Vector3, radius: float) -> BoxBounds:
	for box: BoxBounds in boxes:
		if box.holds(point, radius):
			return box
	var best: BoxBounds = null
	var best_distance: float = INF
	for box: BoxBounds in boxes:
		var distance: float = _shrunk_distance_squared(box, point, radius)
		# Strictly less keeps the lower index on a tie.
		if distance < best_distance:
			best_distance = distance
			best = box
	return best


## True if any box holds a sphere of `radius` at `point` whole.
func holds(point: Vector3, radius: float) -> bool:
	for box: BoxBounds in boxes:
		if box.holds(point, radius):
			return true
	return false


## Keeps `ship` inside the box `box_for` picks for it, exactly as that
## `BoxBounds.contain_impact` does; a single-box union is that box. Returns
## the into-wall velocity, or Vector3.ZERO when nothing was hit or the union
## is empty.
func contain_impact(ship: ShipState) -> Vector3:
	var box: BoxBounds = box_for(ship.position, ship.radius)
	if box == null:
		return Vector3.ZERO
	return box.contain_impact(ship)


## Squared distance from `point` to the region where a sphere of `radius` fits
## in `box`. On an axis where the box is narrower than the sphere, that region
## is the centre line, as in `BoxBounds.contain_impact`.
func _shrunk_distance_squared(box: BoxBounds, point: Vector3, radius: float) -> float:
	var total: float = 0.0
	for axis: int in 3:
		var low: float = box.min_corner[axis] + radius
		var high: float = box.max_corner[axis] - radius
		if low > high:
			low = (box.min_corner[axis] + box.max_corner[axis]) * 0.5
			high = low
		var gap: float = 0.0
		if point[axis] < low:
			gap = low - point[axis]
		elif point[axis] > high:
			gap = point[axis] - high
		total += gap * gap
	return total
