class_name LevelBevels
extends RefCounted

## Bevelled box edges of a box-union level (#1323, GFX-2): along every edge
## where two walls of one box meet, a strip set at 45 degrees cuts the corner,
## so the edge reads as a chamfered edge of rock and metal. They replace the
## thin glowing strips that used to outline each box (#609), which made the
## walls read as paper with bright lines on it (owner's note on #1292).
##
## A bevel runs only where both walls are there (`LevelFaces` quads), so it
## never crosses an opening. It is `width` across each wall at most, and at
## most `MAX_SHARE` of the smaller of the two walls' sides, so a small box
## keeps its walls. It is drawn only; the simulation's boxes are not changed.
##
## A bevel is a Dictionary:
##   "box":     index of the box whose edge it is,
##   "normal":  unit vector pointing into the box, halfway between the walls',
##   "corners": four Vector3, around the strip.

const EPSILON_M: float = LevelFaces.EPSILON_M
const MAX_SHARE: float = 0.25


## Every bevel of `union` whose walls are `faces` (`LevelFaces.quads(union)`).
## Edges are listed in the order their first wall quad is, so the same union
## always gives the same list.
static func quads(union: BoxUnion, faces: Array[Dictionary], width: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if width <= EPSILON_M:
		return result
	# Per edge, the stretches along it that each of its two walls covers.
	var edges: Dictionary = {}
	for face: Dictionary in faces:
		var index: int = face["box"]
		var box: BoxBounds = union.boxes[index]
		var axis: int = face["axis"]
		var low: Vector3 = face["min"]
		var high: Vector3 = face["max"]
		var axis_max: int = 0 if float((face["normal"] as Vector3)[axis]) > 0.0 else 1
		for side_axis: int in [(axis + 1) % 3, (axis + 2) % 3]:
			var run_axis: int = 3 - axis - side_axis
			for side_max: int in [0, 1]:
				var at: float = high[side_axis] if side_max == 1 else low[side_axis]
				var corner: float = box.max_corner[side_axis] if side_max == 1 else box.min_corner[side_axis]
				if absf(at - corner) >= EPSILON_M:
					continue
				var key: String = _key(index, axis, axis_max, side_axis, side_max)
				if not edges.has(key):
					edges[key] = {"box": index, "run": run_axis, "walls": {}}
				var walls: Dictionary = edges[key]["walls"]
				if not walls.has(axis):
					walls[axis] = []
				(walls[axis] as Array).append(Vector2(low[run_axis], high[run_axis]))
	for key: String in edges:
		var edge: Dictionary = edges[key]
		var walls: Dictionary = edge["walls"]
		if walls.size() != 2:
			continue
		var axes: Array = walls.keys()
		var stretches: Array[Vector2] = _overlap(_joined(walls[axes[0]]), _joined(walls[axes[1]]))
		for stretch: Vector2 in stretches:
			result.append(_bevel(union, key, edge, stretch, width))
	return result


## The six corners of the two triangles that draw `bevel`, wound so the side
## its normal points to is the one drawn (as `LevelViewMeshes.quad_triangles` does).
static func triangles(bevel: Dictionary) -> Array[Vector3]:
	var c: Array = bevel["corners"]
	var normal: Vector3 = bevel["normal"]
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	var d: Vector3 = c[2]
	var e: Vector3 = c[3]
	# Godot draws a triangle from the side its corners run clockwise.
	if (b - a).cross(d - a).dot(normal) > 0.0:
		return [a, d, b, a, e, d]
	return [a, b, d, a, d, e]


## The same edge seen from either wall gives the same key.
static func _key(index: int, first_axis: int, first_max: int, second_axis: int, second_max: int) -> String:
	if first_axis > second_axis:
		return "%d:%d%d:%d%d" % [index, second_axis, second_max, first_axis, first_max]
	return "%d:%d%d:%d%d" % [index, first_axis, first_max, second_axis, second_max]


## `stretches` sorted, with touching or overlapping ones joined.
static func _joined(stretches: Array) -> Array[Vector2]:
	var sorted: Array[Vector2] = []
	for stretch: Vector2 in stretches:
		sorted.append(stretch)
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var joined: Array[Vector2] = []
	for stretch: Vector2 in sorted:
		if not joined.is_empty() and stretch.x <= joined[joined.size() - 1].y + EPSILON_M:
			joined[joined.size() - 1].y = maxf(joined[joined.size() - 1].y, stretch.y)
		else:
			joined.append(stretch)
	return joined


static func _overlap(first: Array[Vector2], second: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for a: Vector2 in first:
		for b: Vector2 in second:
			var low: float = maxf(a.x, b.x)
			var high: float = minf(a.y, b.y)
			if high - low > EPSILON_M:
				result.append(Vector2(low, high))
	return result


static func _bevel(union: BoxUnion, key: String, edge: Dictionary, stretch: Vector2, width: float) -> Dictionary:
	var index: int = edge["box"]
	var box: BoxBounds = union.boxes[index]
	var run_axis: int = edge["run"]
	var parts: PackedStringArray = key.split(":")
	var first_axis: int = int(parts[1][0])
	var first_max: bool = parts[1][1] == "1"
	var second_axis: int = int(parts[2][0])
	var second_max: bool = parts[2][1] == "1"
	var size: Vector3 = box.max_corner - box.min_corner
	var cut: float = minf(width, MAX_SHARE * minf(size[first_axis], size[second_axis]))
	var corner: Vector3 = Vector3.ZERO
	corner[first_axis] = box.max_corner[first_axis] if first_max else box.min_corner[first_axis]
	corner[second_axis] = box.max_corner[second_axis] if second_max else box.min_corner[second_axis]
	var into_first: Vector3 = Vector3.ZERO
	into_first[first_axis] = -1.0 if first_max else 1.0
	var into_second: Vector3 = Vector3.ZERO
	into_second[second_axis] = -1.0 if second_max else 1.0
	var start: Vector3 = corner
	start[run_axis] = stretch.x
	var end: Vector3 = corner
	end[run_axis] = stretch.y
	var corners: Array[Vector3] = [start + into_second * cut, start + into_first * cut,
		end + into_first * cut, end + into_second * cut]
	return {"box": index, "normal": (into_first + into_second).normalized(), "corners": corners}
