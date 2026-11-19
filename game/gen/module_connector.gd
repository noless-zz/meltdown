class_name ModuleConnector
extends RefCounted

## Where another mine module can join this one: a square opening on the outer
## face of one of the module's boxes (GEN-1, ARC-4). `ModuleDef` parses and
## checks it; the generator (#294) joins two connectors of the same size class
## face to face, outward axes opposite.
##
## Kept in whole millimetres, module space, so joining is exact (ARC-2).

## Size classes and the side of their square opening, millimetres. Every class
## is at least 8 m, so the warden (radius 2 m) passes with room to spare.
const SIZE_CLASSES: Dictionary[String, int] = {"small": 8000, "large": 12000}
## Outward axis names and the (axis index, sign) each stands for.
const AXES: Dictionary[String, Vector2i] = {
	"+x": Vector2i(0, 1), "-x": Vector2i(0, -1),
	"+y": Vector2i(1, 1), "-y": Vector2i(1, -1),
	"+z": Vector2i(2, 1), "-z": Vector2i(2, -1),
}

## Centre of the opening, millimetres.
var position_mm: Vector3i = Vector3i.ZERO
## One of the `AXES` keys.
var axis_name: String = "+z"
## One of the `SIZE_CLASSES` keys.
var size_class: String = "small"


func _init(p_position_mm: Vector3i = Vector3i.ZERO, p_axis_name: String = "+z",
		p_size_class: String = "small") -> void:
	position_mm = p_position_mm
	axis_name = p_axis_name
	size_class = p_size_class


## 0, 1 or 2 for x, y or z.
func axis() -> int:
	return AXES[axis_name].x


## +1 when the opening faces the positive end of `axis()`, else -1.
func axis_sign() -> int:
	return AXES[axis_name].y


## Side of the square opening, millimetres.
func size_mm() -> int:
	return SIZE_CLASSES[size_class]


## Centre of the opening, metres.
func position() -> Vector3:
	return Vector3(position_mm) / float(RobotSpawn.SCALE)


## Unit vector pointing out of the module through the opening.
func outward() -> Vector3:
	var direction: Vector3 = Vector3.ZERO
	direction[axis()] = float(axis_sign())
	return direction
