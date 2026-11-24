class_name RobotMeshes
extends RefCounted

## The unit primitive meshes robot bodies and parts are built from (CMB-3).
## Kept apart from `RobotView` so the node stays small; `RobotLookReach`
## samples the same shapes.


## A unit-sized mesh for `shape`: about 1 m from the centre to the surface
## along its widest axes, so the node's scale is the robot's size directly.
static func build_mesh(shape: String) -> PrimitiveMesh:
	match shape:
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(2.0, 2.0, 2.0)
			return box
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = 0.6
			capsule.height = 2.0
			capsule.radial_segments = 12
			capsule.rings = 4
			return capsule
		"prism":
			var prism: PrismMesh = PrismMesh.new()
			prism.size = Vector3(2.0, 2.0, 2.0)
			return prism
		"cylinder", "cone":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 1.0 if shape == "cylinder" else 0.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 2.0
			cylinder.radial_segments = 12
			cylinder.rings = 1
			return cylinder
		"torus":
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = 0.7
			torus.outer_radius = 1.0
			torus.rings = 16
			torus.ring_segments = 6
			return torus
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere
