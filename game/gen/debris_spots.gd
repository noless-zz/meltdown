class_name DebrisSpots
extends RefCounted

## Where meltdown debris may be centred in a generated level (#398, RUN-4):
## the boxes and openings of the modules the escape runs through. Split from
## `DebrisPlan` (#436) to keep each file short; it reads nothing but the
## generator and the level, so it stays deterministic (ARC-2).


## The spots an entry may be centred on: the centre of every box of every module
## the shortest route from the reactor to the start passes through, then the
## centre of every opening between two such boxes, each in box order and each
## spot once. Empty without a reactor or a route.
static func escape_spots(generator: MineGenerator, level: LevelDef,
		ship_radius: float) -> Array[Vector3i]:
	var spots: Array[Vector3i] = []
	if level.reactor == null:
		return spots
	var all: Array[int] = []
	for box: int in generator.min_mm.size():
		all.append(box)
	var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
		level.start_position(), null, ship_radius)
	if route.length_mm == EscapePath.UNREACHABLE:
		return spots
	var on_route: Array[bool] = route_boxes(generator, route.points_mm)
	var seen: Dictionary[Vector3i, bool] = {}
	for box: int in on_route.size():
		if on_route[box]:
			_add(spots, seen, (generator.min_mm[box] + generator.max_mm[box]) / 2)
	for i: int in on_route.size():
		for j: int in range(i + 1, on_route.size()):
			if not on_route[i] or not on_route[j]:
				continue
			var low: Vector3i = generator.min_mm[i].max(generator.min_mm[j])
			var high: Vector3i = generator.max_mm[i].min(generator.max_mm[j])
			if low.x < high.x and low.y < high.y and low.z < high.z:
				_add(spots, seen, (low + high) / 2)
	return spots


## Per box: true if it belongs (as one of its boxes or its doorway) to a module
## holding one of `corners_mm`. Loop bridges belong to no module.
static func route_boxes(generator: MineGenerator, corners_mm: Array[Vector3i]) -> Array[bool]:
	var owner: Array[int] = []
	owner.resize(generator.min_mm.size())
	owner.fill(-1)
	for index: int in generator.placements.size():
		var placement: ModulePlacement = generator.placements[index]
		for box: int in range(placement.first_box, placement.end_box):
			owner[box] = index
		if placement.door_box >= 0:
			owner[placement.door_box] = index
	var modules: Array[bool] = []
	modules.resize(generator.placements.size())
	modules.fill(false)
	for corner: Vector3i in corners_mm:
		for box: int in owner.size():
			if owner[box] >= 0 and _holds(generator, box, corner):
				modules[owner[box]] = true
	var boxes: Array[bool] = []
	for box: int in owner.size():
		boxes.append(owner[box] >= 0 and modules[owner[box]])
	return boxes


static func _add(spots: Array[Vector3i], seen: Dictionary[Vector3i, bool], spot: Vector3i) -> void:
	if not seen.has(spot):
		seen[spot] = true
		spots.append(spot)


static func _holds(generator: MineGenerator, box: int, point: Vector3i) -> bool:
	for axis: int in 3:
		if point[axis] < generator.min_mm[box][axis] or point[axis] > generator.max_mm[box][axis]:
			return false
	return true
