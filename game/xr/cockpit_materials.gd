class_name CockpitMaterials
extends RefCounted

## The cockpit frame's surface materials and its own dim light (#659), built
## from a `CockpitSpec`, its `CockpitLook` and its `CockpitFinish` (#1306),
## and the glass. Split from `CockpitFrame` so that file stays about where
## the parts go.

const SURFACE_SHADER: String = "res://xr/cockpit_surface.gdshader"
const GLASS_SHADER: String = "res://xr/cockpit_glass.gdshader"
const GLASS_REFLECTION_SHADER: String = "res://xr/cockpit_glass_reflection.gdshader"
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
static var _glass_shader: Shader = null
static var _reflection_shader: Shader = null


## The shared surface shader, loaded on first use.
static func shader() -> Shader:
	if _shader == null:
		_shader = load(SURFACE_SHADER) as Shader
	return _shader


## The material for part `part_name` (a key of `EDGE_AXES`) in colour `base`
## with the finish of its surface (#1306). `overlap` is how much larger than
## its cell each piece is drawn.
static func surface(part_name: String, base: Color, look: CockpitLook, overlap: float,
		finish: CockpitFinish = null) -> ShaderMaterial:
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
	var used: CockpitFinish = finish if finish != null else CockpitFinish.new()
	for key: String in CockpitFinish.SURFACE_NEUTRAL:
		material.set_shader_parameter(key, used.value(part_name, key))
	material.set_shader_parameter("wear_scale_m", used.wear_scale_m)
	return material


## The material of the dash pieces of part `part_name` (#1306): the surface's
## finish with no panel pattern, seams or edge highlight, since a piece is far
## smaller than a panel; each instance carries its tone and lamp.
static func dash(part_name: String, base: Color, look: CockpitLook, finish: CockpitFinish) -> ShaderMaterial:
	var material: ShaderMaterial = surface(part_name, base, look, 1.0, finish)
	material.set_shader_parameter("pattern_contrast", 0.0)
	material.set_shader_parameter("rivet_size", 0.0)
	material.set_shader_parameter("seam_depth_m", 0.0)
	material.set_shader_parameter("bolt_height_m", 0.0)
	material.set_shader_parameter("instance_tint", true)
	return material


## The canopy glass (#1459): `tint`'s colour, its alpha the share of light
## the glass takes away straight ahead, becomes the filter the view is
## multiplied by (`glass_filter`). With a reflection in `finish`, a next pass
## adds it toward the edge of a window of half-angles `window` degrees (#1306).
static func glass(tint: Color, window: Vector2, finish: CockpitFinish) -> Material:
	if _glass_shader == null:
		_glass_shader = load(GLASS_SHADER) as Shader
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _glass_shader
	var filter: Color = glass_filter(tint)
	material.set_shader_parameter("filter_color", Vector3(filter.r, filter.g, filter.b))
	if finish.glass_fresnel > 0.0:
		if _reflection_shader == null:
			_reflection_shader = load(GLASS_REFLECTION_SHADER) as Shader
		var reflection: ShaderMaterial = ShaderMaterial.new()
		reflection.shader = _reflection_shader
		reflection.set_shader_parameter("fresnel_color", finish.glass_fresnel_color)
		reflection.set_shader_parameter("fresnel", finish.glass_fresnel)
		reflection.set_shader_parameter("fresnel_power", finish.glass_fresnel_power)
		reflection.set_shader_parameter("window_half_angle", Vector2(deg_to_rad(window.x), deg_to_rad(window.y)))
		material.next_pass = reflection
	return material


## What the glass multiplies the view by: the transmission (`1 - tint.a`) on
## the brightest channel of `tint`, the other channels in proportion, so a
## near-neutral tint barely colours the mine and never darkens it past the
## transmission.
static func glass_filter(tint: Color) -> Color:
	var brightest: float = maxf(tint.r, maxf(tint.g, tint.b))
	var through: float = 1.0 - tint.a
	if brightest <= 0.0:
		return Color(through, through, through)
	return Color(tint.r / brightest * through, tint.g / brightest * through, tint.b / brightest * through)


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
