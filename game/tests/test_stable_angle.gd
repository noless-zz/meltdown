extends RefCounted

## `StableAngle.between` must give the correctly rounded angle on every machine
## (ARC-1, ARC-2, #381), where `Vector3.angle_to` follows the platform's
## `atan2f` and was one bit apart between a Builder's sandbox and CI.

## Grid components exactly representable in float, so the float cross and dot
## products used by the helper equal the double ones of the reference.
const GRID: Array[float] = [-1.0, 0.0, 0.5, 2.0]
## Robot 0's first turn on G2 (#340 flight, seed 340), rebuilt from the G2
## start: its facing and the unit offset to the ship, exactly as floats.
const TIE_FACING: Vector3 = Vector3(0.0, 0.0, 1.0)
const TIE_TO_TARGET: Vector3 = Vector3(-0.06237019225955009, -0.03118356131017208,
	0.99756580591201782)
## The double `atan2` of that pair, as the #381 devlog printed it on both machines.
const TIE_EXACT: float = 0.06978794517499533
## The float CI's `atan2f` returned (0.069787942), the nearer of the two.
const TIE_ROUNDED: float = 0.06978794187307358


## Angle from double cross and dot products of the same components.
static func _reference(a: Vector3, b: Vector3) -> float:
	var ax: float = a.x
	var ay: float = a.y
	var az: float = a.z
	var bx: float = b.x
	var by: float = b.y
	var bz: float = b.z
	var cx: float = ay * bz - az * by
	var cy: float = az * bx - ax * bz
	var cz: float = ax * by - ay * bx
	return atan2(sqrt(cx * cx + cy * cy + cz * cz), ax * bx + ay * by + az * bz)


## Distance between `value` and the next float up, for a positive value.
static func _float_step(value: float) -> float:
	if value <= 0.0:
		return 1.0e-45
	var power: float = 1.0
	while power > value:
		power /= 2.0
	while power * 2.0 <= value:
		power *= 2.0
	return power * pow(2.0, -23.0)


static func _grid_vectors() -> Array[Vector3]:
	var vectors: Array[Vector3] = []
	for x: float in GRID:
		for y: float in GRID:
			for z: float in GRID:
				vectors.append(Vector3(x, y, z))
	return vectors


func test_grid_agrees_with_the_double_reference_within_one_float_step() -> String:
	var vectors: Array[Vector3] = _grid_vectors()
	for a: Vector3 in vectors:
		for b: Vector3 in vectors:
			var angle: float = StableAngle.between(a, b)
			var expected: float = 0.0
			if a != Vector3.ZERO and b != Vector3.ZERO:
				expected = _reference(a, b)
			if absf(angle - expected) > _float_step(expected):
				return "%s to %s gave %.17g, reference %.17g" % [a, b, angle, expected]
	return ""


func test_results_are_floats() -> String:
	var vectors: Array[Vector3] = _grid_vectors()
	for a: Vector3 in vectors:
		for b: Vector3 in vectors:
			var angle: float = StableAngle.between(a, b)
			if StableAngle.to_float32(angle) != angle:
				return "%s to %s gave %.17g, not a float" % [a, b, angle]
	return ""


func test_near_tie_rounds_to_the_nearer_float() -> String:
	var angle: float = StableAngle.between(TIE_FACING, TIE_TO_TARGET)
	if angle != TIE_ROUNDED:
		return "the devlog pair gave %.17g, expected %.17g" % [angle, TIE_ROUNDED]
	if absf(angle - TIE_EXACT) > _float_step(TIE_EXACT) / 2.0:
		return "%.17g is more than half a float step from %.17g" % [angle, TIE_EXACT]
	if StableAngle.to_float32(TIE_EXACT) != TIE_ROUNDED:
		return "the exact angle rounds to %.17g" % StableAngle.to_float32(TIE_EXACT)
	return ""


func test_zero_length_inputs_give_zero() -> String:
	var pairs: Array[Array] = [[Vector3.ZERO, Vector3.FORWARD], [Vector3.UP, Vector3.ZERO],
		[Vector3.ZERO, Vector3.ZERO]]
	for pair: Array in pairs:
		var angle: float = StableAngle.between(pair[0], pair[1])
		if angle != 0.0:
			return "%s to %s gave %.17g" % [pair[0], pair[1], angle]
	return ""


func test_parallel_perpendicular_and_opposite() -> String:
	if StableAngle.between(Vector3(0, 0, 2), Vector3(0, 0, 0.5)) != 0.0:
		return "parallel vectors are not at 0"
	if StableAngle.between(Vector3.UP, Vector3.RIGHT) != StableAngle.to_float32(PI / 2.0):
		return "perpendicular vectors are not at PI/2"
	if StableAngle.between(Vector3.UP, Vector3.DOWN) != StableAngle.to_float32(PI):
		return "opposite vectors are not at PI"
	return ""


func test_order_does_not_matter() -> String:
	var a: Vector3 = Vector3(0.3, -1.7, 2.2)
	var b: Vector3 = Vector3(-4.1, 0.25, 0.9)
	if StableAngle.between(a, b) != StableAngle.between(b, a):
		return "between(a, b) %.17g and between(b, a) %.17g differ" % [
			StableAngle.between(a, b), StableAngle.between(b, a)]
	return ""
