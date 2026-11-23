class_name PlacementFit
extends RefCounted

## Whether a module placement fits among the boxes already placed, for
## `MineGenerator` (GEN-5), split from it to keep it short (#919). It keeps
## each module's boxes turned once per turn, in whole millimetres, so the
## thousands of placements a level draws only add an offset. Nothing here is
## random, and the answers are the plain box-against-box test's (ARC-2).

## Each module's turned boxes, by module then turn, filled as needed.
var _turned: Dictionary[ModuleDef, Array] = {}


## True if the module's turned boxes and its doorway overlap none of
## `generator`'s boxes, apart from the doorway reaching into the parent
## module. One pass over the placed boxes; a placed box clear of the module's
## bounding box is clear of each of its boxes, so those are only tested
## inside it.
func fits(generator: MineGenerator, module: ModuleDef, turn: int, offset: Vector3i,
		door: Array[Vector3i], parent: int) -> bool:
	var parent_placement: ModulePlacement = generator.placements[parent]
	var first: int = parent_placement.first_box
	var end: int = parent_placement.end_box
	var door_min: Vector3i = door[0]
	var door_max: Vector3i = door[1]
	var turned: Array[Vector3i] = turned_boxes(module, turn)
	var pairs: int = turned.size() - 2
	var bound_min: Vector3i = turned[pairs] + offset
	var bound_max: Vector3i = turned[pairs + 1] + offset
	# A placed box must reach inside the box around the doorway and the module
	# on every axis to overlap either; most placed boxes are far away.
	var near_min: Vector3i = bound_min.min(door_min)
	var near_max: Vector3i = bound_max.max(door_max)
	var min_mm: Array[Vector3i] = generator.min_mm
	var max_mm: Array[Vector3i] = generator.max_mm
	for index: int in min_mm.size():
		var low: Vector3i = min_mm[index]
		var high: Vector3i = max_mm[index]
		if high.x <= near_min.x or low.x >= near_max.x or high.y <= near_min.y \
				or low.y >= near_max.y or high.z <= near_min.z or low.z >= near_max.z:
			continue
		if (index < first or index >= end) and MineGenerator.overlaps(door_min, door_max, low, high):
			return false
		if not MineGenerator.overlaps(bound_min, bound_max, low, high):
			continue
		for corner: int in range(0, pairs, 2):
			if MineGenerator.overlaps(turned[corner] + offset, turned[corner + 1] + offset, low, high):
				return false
	return true


## The module's boxes turned by `turn`, not yet moved, as millimetre corner
## pairs, then their bounding box as one more pair. Worked out once per
## module and turn for this cache: a turned box moved by an offset is the
## turned box plus the offset, so this gives `turned_box`'s corners.
func turned_boxes(module: ModuleDef, turn: int) -> Array[Vector3i]:
	if not _turned.has(module):
		var empty: Array = []
		empty.resize(ModuleTurns.COUNT)
		_turned[module] = empty
	var slots: Array = _turned[module]
	if slots[turn] != null:
		return slots[turn]
	var corners: Array[Vector3i] = []
	var bound_min: Vector3i = Vector3i.ZERO
	var bound_max: Vector3i = Vector3i.ZERO
	for box: BoxBounds in module.boxes:
		var pair: Array[Vector3i] = turned_box(box, turn, Vector3i.ZERO)
		bound_min = pair[0] if corners.is_empty() else bound_min.min(pair[0])
		bound_max = pair[1] if corners.is_empty() else bound_max.max(pair[1])
		corners.append_array(pair)
	corners.append_array([bound_min, bound_max])
	slots[turn] = corners
	return corners


## The module's boxes turned by `turn` and moved by `offset`, then the
## doorway `door`, as millimetre corner pairs, for `WallClearance` (#1285).
func moved_boxes(module: ModuleDef, turn: int, offset: Vector3i, door: Array[Vector3i]) -> Array[Vector3i]:
	var turned: Array[Vector3i] = turned_boxes(module, turn)
	var moved: Array[Vector3i] = []
	for corner: int in turned.size() - 2:
		moved.append(turned[corner] + offset)
	moved.append_array(door)
	return moved


## A module box turned and moved, as millimetre corners [min, max].
static func turned_box(box: BoxBounds, turn: int, offset: Vector3i) -> Array[Vector3i]:
	var scale: float = float(RobotSpawn.SCALE)
	var a: Vector3i = ModuleTurns.apply(turn, Vector3i((box.min_corner * scale).round())) + offset
	var b: Vector3i = ModuleTurns.apply(turn, Vector3i((box.max_corner * scale).round())) + offset
	return [Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)),
			Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))]
