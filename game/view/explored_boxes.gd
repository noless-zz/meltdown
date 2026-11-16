class_name ExploredBoxes
extends RefCounted

## Which boxes of a box-union level the player has seen, for the hologram map
## (MAP-1). View-side bookkeeping: it reads the level and positions handed to it
## and writes no simulation state (ARC-1, MP-2).

var _union: BoxUnion = null
## One flag per box of the union, in box order.
var _seen: Array[bool] = []


func _init(p_union: BoxUnion = BoxUnion.new()) -> void:
	_union = p_union
	_seen.resize(_union.boxes.size())
	_seen.fill(false)


## Marks every box that holds `position`, walls included, so a point in a wall
## two boxes share, or in the space where they overlap, marks both.
func visit(position: Vector3) -> void:
	for index: int in _union.boxes.size():
		if _union.boxes[index].holds(position, 0.0):
			_seen[index] = true


## Indices of the marked boxes, lowest first.
func explored() -> Array[int]:
	var result: Array[int] = []
	for index: int in _seen.size():
		if _seen[index]:
			result.append(index)
	return result
