class_name FadeOverlay
extends MeshInstance3D

## A black quad just in front of the camera that fades the view out and in,
## used around the reset to the start so the ship is never seen sweeping
## there (CMF-8). One unshaded, alpha-blended quad drawn last and over
## everything; no full-screen pass (PRF-2). Hidden at alpha 0, so it costs
## nothing outside a fade. It only shows an alpha it is given.

const NODE_NAME: String = "FadeOverlay"
## Close to the eyes, inside any wall the ship can touch (radius 1 m).
const DISTANCE: float = 0.1
## Wide enough at `DISTANCE` to cover both eyes' fields of view on Quest 3.
const SIZE: float = 1.0


func _init() -> void:
	name = NODE_NAME
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	mesh = quad
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# One step below the top, so the destroyed screen's words draw over it (#616).
	material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	ignore_occlusion_culling = true
	position = Vector3(0.0, 0.0, -DISTANCE)
	visible = false


## Shows `value` (clamped to 0..1) as the black's opacity; hidden at 0.
func set_alpha(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	(material_override as StandardMaterial3D).albedo_color.a = clamped
	visible = clamped > 0.0


## Makes the quad `value`'s colour, keeping the opacity shown; the launch
## fade's colour is data (#1396), every other fade is black.
func set_color(value: Color) -> void:
	var material: StandardMaterial3D = material_override as StandardMaterial3D
	material.albedo_color = Color(value.r, value.g, value.b, material.albedo_color.a)


## The colour shown, without its opacity.
func get_color() -> Color:
	var shown: Color = (material_override as StandardMaterial3D).albedo_color
	return Color(shown.r, shown.g, shown.b)


## The opacity currently shown, 0..1.
func get_alpha() -> float:
	return (material_override as StandardMaterial3D).albedo_color.a
