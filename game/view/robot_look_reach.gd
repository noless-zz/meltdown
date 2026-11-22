class_name RobotLookReach
extends RefCounted

## How far a robot's drawn model reaches from its centre, in units of its
## collision radius (#1225, GEN-3, GEN-5). The simulation keeps a robot's
## centre one `radius` off every wall, so any piece drawn further out than that
## pokes through the wall and shows in the next tunnel. A look fits when its
## `scale` is at most 1 and every body and part point lies within `1 / scale`
## of the centre.
##
## The lean, bank and skid tells (`RobotTells.drawn_basis`) only rotate the
## model about its centre, so a fit in the rest pose is a fit at every lean.
##
## Points are sampled on the surface of the same unit shapes `RobotView`
## builds. Boxes, prisms and the cone's apex are exact corners; round shapes
## include their poles and widest rings, which is where a stretched and offset
## round piece reaches furthest along an axis.

## Steps around a round shape's circumference, and from pole to pole.
const AROUND: int = 72
const POLE_TO_POLE: int = 36
const TUBE_STEPS: int = 24
## `RobotView.build_mesh` torus and capsule dimensions.
const TORUS_INNER: float = 0.7
const TORUS_OUTER: float = 1.0
const CAPSULE_RADIUS: float = 0.6
const CAPSULE_HALF_HEIGHT: float = 1.0
## Allowance for float rounding when comparing a reach to the radius.
const EPSILON: float = 1e-6


## Furthest distance from the robot's centre of a unit `shape` stretched by
## `size` and moved by `offset`, in unit space (before the look's `scale`).
static func piece_reach(shape: String, size: Vector3, offset: Vector3) -> float:
	var furthest: float = 0.0
	for point: Vector3 in unit_points(shape):
		furthest = maxf(furthest, (point * size + offset).length())
	return furthest


## Every piece of `look` (body first, then parts) with its reach in units of
## the collision radius, `scale` included: `[{"name", "reach"}]`.
static func reaches(look: Dictionary) -> Array[Dictionary]:
	var scale: float = float(look["scale"])
	var result: Array[Dictionary] = [{"name": "body",
			"reach": piece_reach(look["shape"], look["stretch"], Vector3.ZERO) * scale}]
	var parts: Array = look["parts"]
	for index: int in parts.size():
		var part: Dictionary = parts[index]
		result.append({"name": "parts.%d (%s)" % [index, part["shape"]],
				"reach": piece_reach(part["shape"], part["size"], part["offset"]) * scale})
	return result


## Why the look of robot `id` does not fit inside its collision sphere, naming
## the piece that reaches furthest, or "" when it fits.
static func misfit(id: String, look: Dictionary) -> String:
	var scale: float = float(look["scale"])
	if scale > 1.0 + EPSILON:
		return "\"%s\" has scale %.3f, over 1.0" % [id, scale]
	var worst: Dictionary = {"name": "", "reach": 0.0}
	for piece: Dictionary in reaches(look):
		if float(piece["reach"]) > float(worst["reach"]):
			worst = piece
	if float(worst["reach"]) > 1.0 + EPSILON:
		return "\"%s\" %s reaches %.3f radii from its centre, past its collision radius" % [
				id, worst["name"], worst["reach"]]
	return ""


## Surface points of the unit shape `RobotView.build_mesh` draws for `shape`.
static func unit_points(shape: String) -> Array[Vector3]:
	match shape:
		"box":
			return _box_corners()
		"prism":
			return [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, -1, 1), Vector3(1, -1, 1),
					Vector3(0, 1, -1), Vector3(0, 1, 1)]
		"cylinder":
			var rims: Array[Vector3] = _ring(1.0, -1.0)
			rims.append_array(_ring(1.0, 1.0))
			return rims
		"cone":
			var cone: Array[Vector3] = _ring(1.0, -1.0)
			cone.append(Vector3(0, 1, 0))
			return cone
		"torus":
			return _torus()
		"capsule":
			return _capsule()
	return _sphere(1.0, 0.0)


static func _box_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				corners.append(Vector3(x, y, z))
	return corners


static func _ring(radius: float, y: float) -> Array[Vector3]:
	var ring: Array[Vector3] = []
	for step: int in AROUND:
		var angle: float = TAU * step / AROUND
		ring.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	return ring


## A sphere of `radius`; each hemisphere is moved `half_gap` away from the
## centre along y, which turns it into a capsule's caps.
static func _sphere(radius: float, half_gap: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for level: int in POLE_TO_POLE + 1:
		var latitude: float = -PI / 2.0 + PI * level / POLE_TO_POLE
		var shift: float = half_gap if latitude >= 0.0 else -half_gap
		for point: Vector3 in _ring(cos(latitude) * radius, sin(latitude) * radius + shift):
			points.append(point)
	return points


static func _capsule() -> Array[Vector3]:
	return _sphere(CAPSULE_RADIUS, CAPSULE_HALF_HEIGHT - CAPSULE_RADIUS)


static func _torus() -> Array[Vector3]:
	var tube: float = (TORUS_OUTER - TORUS_INNER) / 2.0
	var middle: float = TORUS_INNER + tube
	var points: Array[Vector3] = []
	for step: int in TUBE_STEPS:
		var angle: float = TAU * step / TUBE_STEPS
		points.append_array(_ring(middle + tube * cos(angle), tube * sin(angle)))
	return points
