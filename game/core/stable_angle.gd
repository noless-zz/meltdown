class_name StableAngle
extends RefCounted

## The angle between two vectors, the same on every machine (ARC-1, ARC-2, #381).
##
## `Vector3.angle_to` takes the float `atan2f` of the C library, which is not
## required to round correctly: for one robot turn on G2's first tick it was a
## bit apart between a Builder's sandbox and CI, and the whole co-op session
## then diverged. GDScript's `atan2` works in double precision, so its answer
## rounded once to float is the correctly rounded angle on both. The cross and
## dot products stay in float, as in `angle_to`, so wherever `atan2f` was
## already right the result is unchanged and recorded hashes stand.


## Radians in [0, PI]. A zero-length input gives 0.
static func between(a: Vector3, b: Vector3) -> float:
	if a == Vector3.ZERO or b == Vector3.ZERO:
		return 0.0
	var cross_length: float = a.cross(b).length()
	var dot: float = a.dot(b)
	return to_float32(atan2(cross_length, dot))


## Rounds a double to the nearest float, the precision of a `Vector3` component.
static func to_float32(value: float) -> float:
	return Vector3(value, 0.0, 0.0).x
