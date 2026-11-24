class_name BoltMeshes
extends RefCounted

## The meshes each weapon's bolts are drawn with (#1309, GFX-2, ARC-4, ARC-5):
## a head of one of `SHAPES` along the mesh's Y axis, in the weapon's colour,
## and a trail behind it that tapers to nothing. Both are primitive meshes
## made in code with unshaded materials, so no model or image file is shipped
## and the dark mine is lit only by what glows (LGT-1). Built once per weapon
## and shared by all its bolts.

## The head shapes a look may name: a rod, a rod with round ends, a stretched
## ball and a dart pointed along its flight.
const SHAPES: Array = ["cylinder", "capsule", "ellipsoid", "dart"]
## Sides around a head or trail: few, since bolts are small and many.
const SIDES: int = 6
## A trail's radius at the bolt, as a share of the bolt's radius.
const TRAIL_RADIUS_SHARE: float = 0.7

var _look: Dictionary = ProjectileLook.DEFAULTS
## Weapon row name to [head mesh, trail mesh, merged look].
var _built: Dictionary[String, Array] = {}


## Takes a parsed `ProjectileLook` (with `weapons`); forgets the meshes built.
func set_look(look: Dictionary) -> void:
	_look = look
	_built = {}


## The look of `weapon`'s bolts (`ProjectileWeaponLooks.look_for`).
func look(weapon: String) -> Dictionary:
	return _entry(weapon)[2]


## The head mesh of `weapon`'s bolts, centred on the origin along Y.
func head(weapon: String) -> PrimitiveMesh:
	return _entry(weapon)[0]


## The trail mesh of `weapon`'s bolts: a cone 1 m long, centred on the origin,
## 1 m round at its +Y end and tapering to a point at its -Y end; the bolt
## scales and places it behind itself.
func trail(weapon: String) -> PrimitiveMesh:
	return _entry(weapon)[1]


## The head mesh for `shape`, `length_m` long and `radius_m` round, glowing in `color`.
static func build_head(shape: String, length_m: float, radius_m: float, color: Color) -> PrimitiveMesh:
	var mesh: PrimitiveMesh = null
	match shape:
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = radius_m
			capsule.height = maxf(length_m, radius_m * 2.0)
			capsule.radial_segments = SIDES
			capsule.rings = 1
			mesh = capsule
		"ellipsoid":
			var ball: SphereMesh = SphereMesh.new()
			ball.radius = radius_m
			ball.height = length_m
			ball.radial_segments = SIDES
			ball.rings = 3
			mesh = ball
		_:
			var rod: CylinderMesh = CylinderMesh.new()
			rod.height = length_m
			# A dart's point (the mesh's top, +Y) leads, as bolts fly along +Y.
			rod.top_radius = 0.0 if shape == "dart" else radius_m
			rod.bottom_radius = radius_m
			rod.radial_segments = SIDES
			rod.rings = 1
			mesh = rod
	mesh.material = glow_material(color)
	return mesh


## An unshaded material glowing in `color`.
static func glow_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.albedo_color = color
	material.emission = color
	return material


func _entry(weapon: String) -> Array:
	if _built.has(weapon):
		return _built[weapon]
	var merged: Dictionary = ProjectileWeaponLooks.look_for(_look, weapon)
	var head_mesh: PrimitiveMesh = build_head(merged["bolt_shape"], merged["bolt_length_m"],
		merged["bolt_radius_m"], merged["emission_color"])
	var trail_mesh: CylinderMesh = CylinderMesh.new()
	trail_mesh.height = 1.0
	trail_mesh.top_radius = 1.0
	trail_mesh.bottom_radius = 0.0
	trail_mesh.radial_segments = SIDES
	trail_mesh.rings = 1
	trail_mesh.material = glow_material(merged["trail_color"])
	_built[weapon] = [head_mesh, trail_mesh, merged]
	return _built[weapon]
