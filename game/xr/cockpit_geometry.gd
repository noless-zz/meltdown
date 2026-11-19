class_name CockpitGeometry
extends RefCounted

## Angle maths for the cockpit frame (CMF-1): where a cell of the view lies,
## the flat panels and boxes that cover it, and the seamless glass patch.
## Split from `CockpitFrame` so that file stays about building the parts.
##
## Angles are degrees seen from the eye at the origin looking along -Z: yaw to
## the right, pitch up from the horizon.

## Which window edge a piece must stay beyond.
enum Edge { YAW, PITCH }

## Extra clearance a piece keeps from its window edge, degrees, so rounding
## never lets a corner show inside the window.
const CLEARANCE_DEG: float = 0.01
## Most corrections `keep_out` makes; each one closes nearly all of the gap.
const KEEP_OUT_PASSES: int = 6


## Unit vector from the eye at `yaw` degrees right and `pitch` degrees up.
static func direction(yaw: float, pitch: float) -> Vector3:
	var y: float = deg_to_rad(yaw)
	var p: float = deg_to_rad(pitch)
	return Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))


## (yaw, pitch) in degrees of `point` seen from the eye.
static func yaw_pitch(point: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(point.x, -point.z)),
		rad_to_deg(atan2(point.y, Vector2(point.x, point.z).length())))


## Edges from `low` to `high` degrees in equal steps no wider than `cell`.
static func breaks(low: float, high: float, cell: float) -> PackedFloat32Array:
	var result: PackedFloat32Array = [low]
	var steps: int = maxi(1, ceili((high - low) / cell))
	for k: int in range(1, steps + 1):
		result.append(low + (high - low) * k / steps)
	return result


## A basis whose X runs along increasing yaw, Y along increasing pitch, and Z
## back toward the eye, so a quad on it faces the eye.
static func facing_basis(yaw: float, pitch: float) -> Basis:
	var y: float = deg_to_rad(yaw)
	var p: float = deg_to_rad(pitch)
	var along_yaw: Vector3 = Vector3(cos(y), 0.0, sin(y))
	var along_pitch: Vector3 = Vector3(-sin(y) * sin(p), cos(p), cos(y) * sin(p))
	return Basis(along_yaw, along_pitch, -direction(yaw, pitch))


## A unit box (or flat quad when `depth` is 0) facing the eye that covers the
## cell from (`yaw_a`, `pitch_a`) to (`yaw_b`, `pitch_b`), its front face
## `distance` metres from the eye, drawn `overlap` times larger than the cell
## so neighbours leave no gap.
static func cell_piece(cell_a: Vector2, cell_b: Vector2, distance: float, depth: float,
		overlap: float) -> Transform3D:
	var yaw: float = (cell_a.x + cell_b.x) * 0.5
	var pitch: float = (cell_a.y + cell_b.y) * 0.5
	# The cell is widest on the edge nearest the horizon.
	var widest: float = cos(deg_to_rad(minf(absf(cell_a.y), absf(cell_b.y)))) \
		if signf(cell_a.y) == signf(cell_b.y) else 1.0
	var width: float = 2.0 * distance * widest * tan(deg_to_rad(cell_b.x - cell_a.x) * 0.5) * overlap
	var height: float = 2.0 * distance * tan(deg_to_rad(cell_b.y - cell_a.y) * 0.5) * overlap
	var basis: Basis = facing_basis(yaw, pitch).scaled_local(Vector3(width, height, depth if depth > 0.0 else 1.0))
	return Transform3D(basis, direction(yaw, pitch) * (distance + depth * 0.5))


## The corners of a unit piece placed by `placed`: eight for a box, four for
## a flat quad.
static func corners(placed: Transform3D, deep: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x: float in [-0.5, 0.5]:
		for y: float in [-0.5, 0.5]:
			for z: float in ([-0.5, 0.5] if deep else [0.0]):
				result.append(placed * Vector3(x, y, z))
	return result


## How far, in degrees, every corner of the piece lies beyond the window edge
## `edge` degrees on side `side` (+1 right or up, -1 left or down) along
## `axis`; negative when a corner reaches into the window.
static func clearance(placed: Transform3D, deep: bool, axis: Edge, side: float, edge: float) -> float:
	var least: float = INF
	for corner: Vector3 in corners(placed, deep):
		var angles: Vector2 = yaw_pitch(corner)
		var along: float = angles.x if axis == Edge.YAW else angles.y
		least = minf(least, side * along - edge)
	return least


## `placed` turned about the eye, away from the window, until every corner
## clears the edge. Turning about the eye keeps every distance, so the piece
## stays between the near plane and the hull. Turning about the vertical moves
## every point's yaw alike; turning about the horizontal axis across the
## piece moves pitch nearly alike, so a few passes settle it.
static func keep_out(placed: Transform3D, deep: bool, axis: Edge, side: float, edge: float) -> Transform3D:
	var result: Transform3D = placed
	for pass_index: int in KEEP_OUT_PASSES:
		var gap: float = clearance(result, deep, axis, side, edge) - CLEARANCE_DEG
		if gap >= 0.0:
			break
		var turn: float = deg_to_rad(-gap) * side
		var rotation: Basis
		if axis == Edge.YAW:
			# A positive turn about +Y lowers yaw.
			rotation = Basis(Vector3.UP, -turn)
		else:
			var yaw: float = deg_to_rad(yaw_pitch(result.origin).x)
			rotation = Basis(Vector3(cos(yaw), 0.0, sin(yaw)), turn)
		result = Transform3D(rotation, Vector3.ZERO) * result
	return result


## The points of a glass patch over the window, on a sphere of `distance`
## metres: (len(yaw_breaks) * len(pitch_breaks)) points, row by row of pitch.
static func glass_points(yaw_breaks: PackedFloat32Array, pitch_breaks: PackedFloat32Array,
		distance: float) -> PackedVector3Array:
	var points: PackedVector3Array = []
	for pitch: float in pitch_breaks:
		for yaw: float in yaw_breaks:
			points.append(direction(yaw, pitch) * distance)
	return points


## One mesh over the window built from `glass_points`. Its triangles share
## their edges, so nothing overlaps: overlapping tinted panels drew darker
## seams that read as a grid across the window (#607).
static func glass_mesh(points: PackedVector3Array, columns: int) -> ArrayMesh:
	var indices: PackedInt32Array = []
	var rows: int = points.size() / columns
	for j: int in rows - 1:
		for i: int in columns - 1:
			var a: int = j * columns + i
			var b: int = a + columns
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
