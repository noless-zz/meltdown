class_name MapShipMarker
extends RefCounted

## The ship marker on the held map (#679, MAP-1, NAM-3): a small dart rather
## than a ball, so the pilot can read heading and roll from the map alone.
##
## The silhouette is Meltdown's own ("the kite", see `docs/art-direction.md`):
## a flat swept delta with a notched tail and one tall dorsal fin set well aft.
## The fin is the only thing above the wing plane, so the top side is never in
## doubt; the nose is the only sharp point ahead of the wings, so neither is the
## heading. Built from a handful of triangles here rather than an imported model
## (PRF-2: it is a few millimetres across on the map).
##
## Ship space is Godot's: forward is -Z, up is +Y, right is +X. The marker node
## takes the ship's orientation as its basis, so these axes follow the ship.

## Unit vector along which the nose points, in the marker's own space.
const NOSE: Vector3 = Vector3(0.0, 0.0, -1.0)
## Unit vector out of the top side (towards the fin), in the marker's own space.
const TOP: Vector3 = Vector3(0.0, 1.0, 0.0)
## Nose-to-tail length as a multiple of the look's `marker_radius_m`, so the dart
## covers about the span the old ball did, a little longer to show the point.
const LENGTH_PER_RADIUS: float = 3.0

## The shape, nose to tail = 1 along Z, centred on the origin. Named points:
const _NOSE_TIP: Vector3 = Vector3(0.0, 0.0, -0.5)
const _LEFT_TIP: Vector3 = Vector3(-0.38, -0.03, 0.5)
const _RIGHT_TIP: Vector3 = Vector3(0.38, -0.03, 0.5)
## The tail notch between the wing tips: a swallowtail reads as "back" at a glance.
const _NOTCH: Vector3 = Vector3(0.0, 0.0, 0.22)
## The dorsal fin's top and its root at the front of the fin.
const _FIN_TOP: Vector3 = Vector3(0.0, 0.3, 0.46)
const _FIN_ROOT: Vector3 = Vector3(0.0, 0.03, -0.05)
## A shallow keel under the hull so the dart has some depth seen edge-on.
const _KEEL: Vector3 = Vector3(0.0, -0.08, 0.05)

## Triangles of the shape, three points each. Both faces render (see `mesh`),
## so the winding does not matter.
const TRIANGLES: Array[Vector3] = [
	# Upper wing surfaces, nose to tip to notch.
	_NOSE_TIP, _LEFT_TIP, _NOTCH,
	_NOSE_TIP, _NOTCH, _RIGHT_TIP,
	# The dorsal fin, a single upright blade on the centre line.
	_FIN_ROOT, _FIN_TOP, _NOTCH,
	# The keel under the hull, nose to notch.
	_NOSE_TIP, _KEEL, _LEFT_TIP,
	_NOSE_TIP, _RIGHT_TIP, _KEEL,
	_KEEL, _NOTCH, _LEFT_TIP,
	_KEEL, _RIGHT_TIP, _NOTCH,
]


## The dart's points scaled so it is `length_m` from nose to tail.
static func points(length_m: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in TRIANGLES:
		out.append(point * length_m)
	return out


## Nose-to-tail length for a look's `marker_radius_m`.
static func length_for(radius_m: float) -> float:
	return radius_m * LENGTH_PER_RADIUS


## The dart as one glowing mesh in `color`, sized from the look's `radius_m`.
static func mesh(color: Color, radius_m: float, energy: float) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points(length_for(radius_m))
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = MapShapes.glow(color, energy)
	# The fin is a single blade and the wings a single sheet: seen from either
	# side they must still show, or the dart vanishes when it rolls.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.surface_set_material(0, material)
	return result
