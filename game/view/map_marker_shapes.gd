class_name MapMarkerShapes
extends RefCounted

## The named solid shapes the map hologram's reactor, trapped-miner and fire
## markers are drawn as (#1219, MAP-1, SLV-3, PLT-2). On 22 Nov the owner took a
## fire for a second reactor: a yellow double cone and a pink ball a few
## millimetres across differ by hue alone. Each of those markers now names its
## shape in `map_look.json` (ARC-4), and the look's parser rejects a file where
## two of them name the same one.
##
## The shapes are Meltdown's own (NAM-3) and chosen so their outlines differ
## from any side, not only their colours:
##
## - `diamond`: a tall four-sided double point, twice as high as it is wide.
##   Symmetric top and bottom, the only marker with a point at both ends.
## - `pin`: a square pyramid standing on its point, as wide as it is tall, flat
##   on top, like a map pin (#1072).
## - `flame`: a slender three-sided spike pointing up from a flat base, a
##   little over half as wide as it is tall, like a tongue of flame.
##
## The ship's dart (`MapShipMarker`, #679), the exit's cube and the blocked
## openings' crosses are none of these. Every shape is `size` tall, centred on
## `centre`, and returned as loose triangles (three points each) so many
## markers share one mesh surface (PRF-2). Both faces render, so the winding
## does not matter.

const DIAMOND: String = "diamond"
const PIN: String = "pin"
const FLAME: String = "flame"
## Every shape a marker key may name.
const NAMES: Array[String] = [DIAMOND, PIN, FLAME]
## Vertices each shape adds: triangles times three.
const VERTICES: Dictionary[String, int] = {DIAMOND: 24, PIN: 18, FLAME: 12}
## Width over height. The diamond is narrow so it never reads as a ball or a
## cube; the flame narrower than the pin so the two are told apart edge on.
const WIDTH_PER_HEIGHT: Dictionary[String, float] = {DIAMOND: 0.5, PIN: 1.0, FLAME: 0.6}


## Triangles of `shape` (one of `NAMES`), `size` tall, centred on `centre`.
## An unknown name gives no triangles.
static func triangles(shape: String, centre: Vector3, size: float) -> PackedVector3Array:
	match shape:
		DIAMOND:
			return _diamond(centre, size)
		PIN:
			return _pin(centre, size)
		FLAME:
			return _flame(centre, size)
	return PackedVector3Array()


## One glowing mesh of `shape` at the origin, for a single marker node.
static func mesh(shape: String, size: float, material: StandardMaterial3D) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles(shape, Vector3.ZERO, size)
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.surface_set_material(0, material)
	return result


static func _diamond(centre: Vector3, size: float) -> PackedVector3Array:
	var half: float = size * 0.5
	var reach: float = size * WIDTH_PER_HEIGHT[DIAMOND] * 0.5
	var ring: Array[Vector3] = [Vector3(reach, 0.0, 0.0), Vector3(0.0, 0.0, reach),
			Vector3(-reach, 0.0, 0.0), Vector3(0.0, 0.0, -reach)]
	var result: PackedVector3Array = PackedVector3Array()
	for pole: Vector3 in [Vector3.UP * half, Vector3.DOWN * half]:
		for i: int in ring.size():
			result.append(centre + pole)
			result.append(centre + ring[i])
			result.append(centre + ring[(i + 1) % ring.size()])
	return result


static func _pin(centre: Vector3, size: float) -> PackedVector3Array:
	var half: float = size * 0.5
	var reach: float = size * WIDTH_PER_HEIGHT[PIN] * 0.5
	var tip: Vector3 = centre + Vector3.DOWN * half
	var top: Array[Vector3] = [Vector3(reach, half, reach), Vector3(reach, half, -reach),
			Vector3(-reach, half, -reach), Vector3(-reach, half, reach)]
	var result: PackedVector3Array = PackedVector3Array()
	for i: int in top.size():
		result.append(tip)
		result.append(centre + top[i])
		result.append(centre + top[(i + 1) % top.size()])
	for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
		for corner: int in triangle:
			result.append(centre + top[corner])
	return result


static func _flame(centre: Vector3, size: float) -> PackedVector3Array:
	var half: float = size * 0.5
	var reach: float = size * WIDTH_PER_HEIGHT[FLAME] * 0.5
	var tip: Vector3 = centre + Vector3.UP * half
	var base: Array[Vector3] = []
	for i: int in 3:
		var angle: float = TAU * float(i) / 3.0
		base.append(centre + Vector3(cos(angle) * reach, -half, sin(angle) * reach))
	var result: PackedVector3Array = PackedVector3Array()
	for i: int in base.size():
		result.append(tip)
		result.append(base[i])
		result.append(base[(i + 1) % base.size()])
	result.append_array(PackedVector3Array(base))
	return result
