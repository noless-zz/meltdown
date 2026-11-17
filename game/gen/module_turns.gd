class_name ModuleTurns
extends RefCounted

## The 24 ways to turn a module in 90° steps without mirroring it (GEN-5): the
## rotations that map the axes onto the axes. A turn is an index into `rows()`;
## turn 0 leaves a module as authored. Integer matrices keep turned positions
## in whole millimetres, so a level comes out the same on every device (ARC-2).

const COUNT: int = 24

static var _rows: Array[Array] = []


## Each turn as three rows of a matrix, so `turned[i] = rows[i].dot(v)`. Built
## in a fixed order (axis permutations, then sign patterns) with turn 0 the
## identity.
static func rows() -> Array[Array]:
	if _rows.is_empty():
		var orders: Array[Vector3i] = [
			Vector3i(0, 1, 2), Vector3i(0, 2, 1), Vector3i(1, 0, 2),
			Vector3i(1, 2, 0), Vector3i(2, 0, 1), Vector3i(2, 1, 0),
		]
		for order: Vector3i in orders:
			for signs: int in 8:
				var matrix: Array[Vector3i] = []
				for row: int in 3:
					var line: Vector3i = Vector3i.ZERO
					line[order[row]] = -1 if (signs >> row) & 1 == 1 else 1
					matrix.append(line)
				if _determinant(matrix) == 1:
					_rows.append(matrix)
	return _rows


## `vector` turned by turn `turn`.
static func apply(turn: int, vector: Vector3i) -> Vector3i:
	var matrix: Array = rows()[turn]
	return Vector3i(
		(matrix[0] as Vector3i).x * vector.x + (matrix[0] as Vector3i).y * vector.y + (matrix[0] as Vector3i).z * vector.z,
		(matrix[1] as Vector3i).x * vector.x + (matrix[1] as Vector3i).y * vector.y + (matrix[1] as Vector3i).z * vector.z,
		(matrix[2] as Vector3i).x * vector.x + (matrix[2] as Vector3i).y * vector.y + (matrix[2] as Vector3i).z * vector.z)


## The `ModuleConnector.AXES` name of a unit axis vector, or "" if it is not one.
static func axis_name(direction: Vector3i) -> String:
	for name: String in ModuleConnector.AXES:
		var entry: Vector2i = ModuleConnector.AXES[name]
		var unit: Vector3i = Vector3i.ZERO
		unit[entry.x] = entry.y
		if unit == direction:
			return name
	return ""


## Unit vector of a connector's outward axis.
static func outward(connector: ModuleConnector) -> Vector3i:
	var unit: Vector3i = Vector3i.ZERO
	unit[connector.axis()] = connector.axis_sign()
	return unit


## The turns, lowest first, that point a connector facing `from` along `to`.
static func turns_between(from: Vector3i, to: Vector3i) -> Array[int]:
	var found: Array[int] = []
	for turn: int in COUNT:
		if apply(turn, from) == to:
			found.append(turn)
	return found


static func _determinant(m: Array[Vector3i]) -> int:
	return m[0].x * (m[1].y * m[2].z - m[1].z * m[2].y) \
			- m[0].y * (m[1].x * m[2].z - m[1].z * m[2].x) \
			+ m[0].z * (m[1].x * m[2].y - m[1].y * m[2].x)
