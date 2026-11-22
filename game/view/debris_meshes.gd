class_name DebrisMeshes
extends RefCounted

## The shared meshes `DebrisView` draws every debris entry with (RUN-4). Each is
## of unit size and every node scales it to its entry, so a new radius or slab
## size never needs a new mesh, and the meshes are built once, never per call.

## Times a mesh was built, for tests.
var builds: int = 0
## A whole rock: more facets read as one piece.
var rock: SphereMesh
## A held, cracked shell: fewer facets read as a broken one.
var cracked: SphereMesh
## A blast door or collapsed ceiling (#459).
var slab: BoxMesh
## A burning fire sphere: a faceted upward cone filling the sphere's height. A
## glowing ball there was taken for the reactor core (#1208).
var flame: CylinderMesh


func _init() -> void:
	rock = _build_sphere(10, 5)
	cracked = _build_sphere(5, 3)
	slab = BoxMesh.new()
	slab.size = Vector3.ONE
	builds += 1
	flame = CylinderMesh.new()
	flame.top_radius = 0.0
	flame.bottom_radius = 1.0
	flame.height = 2.0
	flame.radial_segments = 5
	flame.rings = 0
	builds += 1


## A unit sphere; each node's scale is its entry's radius.
func _build_sphere(segments: int, rings: int) -> SphereMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segments
	sphere.rings = rings
	builds += 1
	return sphere
