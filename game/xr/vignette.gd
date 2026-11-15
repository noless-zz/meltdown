class_name Vignette
extends MeshInstance3D

## The node that shows the comfort vignette: one quad under the camera whose
## shader darkens the edge of view (CMF-1). Its strength comes from
## `ComfortVignette.strength`; this node only displays it.
##
## At strength 0 the node is hidden, so the quad costs no draw call and no
## fill on presets that turn the vignette off (PRF-2, CMF-2).

const STRENGTH_PARAM: StringName = &"strength"


## Shows `value` (clamped to 0..1) and hides the node when it is 0.
func set_strength(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	var material: ShaderMaterial = material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter(STRENGTH_PARAM, clamped)
	visible = clamped > 0.0


## The strength currently shown, 0..1.
func get_strength() -> float:
	var material: ShaderMaterial = material_override as ShaderMaterial
	if material == null:
		return 0.0
	var value: Variant = material.get_shader_parameter(STRENGTH_PARAM)
	return float(value) if value != null else 0.0
