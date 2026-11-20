class_name CockpitMaterials
extends RefCounted

## The cockpit frame's surface materials and its own dim light (#659), built
## from a `CockpitSpec` and its `CockpitLook`. Split from `CockpitFrame` so
## that file stays about where the parts go.

const SURFACE_SHADER: String = "res://xr/cockpit_surface.gdshader"
const LIGHT_NAME: String = "CockpitLight"
## Which face edges of each part get the highlight: x the cell's yaw edges, y
## its pitch edges. The ledge and rim run across the view, so their long
## edges are the pitch edges; the pillars run up it. The shell gets none.
const EDGE_AXES: Dictionary[String, Vector2] = {
	"Solid": Vector2.ZERO,
	"Ledge": Vector2(0.0, 1.0),
	"Rim": Vector2(0.0, 1.0),
	"Pillars": Vector2(1.0, 0.0),
}

static var _shader: Shader = null


## The shared surface shader, loaded on first use.
static func shader() -> Shader:
	if _shader == null:
		_shader = load(SURFACE_SHADER) as Shader
	return _shader


## The material for part `part_name` (a key of `EDGE_AXES`) in colour `base`.
## `overlap` is how much larger than its cell each piece is drawn.
static func surface(part_name: String, base: Color, look: CockpitLook, overlap: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader()
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("edge_color", look.edge_color)
	var axis: Vector2 = EDGE_AXES.get(part_name, Vector2.ZERO)
	material.set_shader_parameter("edge_width_m", look.edge_width_m if axis != Vector2.ZERO else 0.0)
	material.set_shader_parameter("edge_axis", axis)
	material.set_shader_parameter("glow", look.glow)
	material.set_shader_parameter("pattern_scale_m", look.pattern_scale_m)
	material.set_shader_parameter("pattern_contrast", look.pattern_contrast)
	material.set_shader_parameter("rivet_size", look.rivet_size)
	material.set_shader_parameter("overlap_margin", (1.0 - 1.0 / overlap) * 0.5)
	return material


## The frame's own dim light above the eye, or null when its energy is 0. It
## casts no shadow (GFX-4 keeps shadows for the headlight) and its reach ends
## inside the ship, so it lights the cockpit and never the mine.
static func light(look: CockpitLook) -> OmniLight3D:
	if look.light_energy <= 0.0:
		return null
	var omni: OmniLight3D = OmniLight3D.new()
	omni.name = LIGHT_NAME
	omni.position = CockpitLook.LIGHT_OFFSET
	omni.light_color = look.light_color
	omni.light_energy = look.light_energy
	omni.omni_range = look.light_range_m
	omni.shadow_enabled = false
	return omni
