class_name ReactorFlames
extends RefCounted

## Builds the GPU particle systems that burn on the reactor's wreck (#1310,
## GFX-6): flames rising from the core and a few embers thrown higher. They
## are billboards with additive blending, never a full-screen pass, and add no
## light (GFX-4). Sizes are in the machine's unit space, where 1 is the
## reactor's radius. The colours never flash: each particle fades from the hot
## colour to the cool one and out over its life.


## The flames: `look` is a parsed `ReactorMachineLook`.
static func flames(look: Dictionary) -> GPUParticles3D:
	var lifetime: float = float(look["flame_lifetime"])
	var size: float = float(look["flame_size_r"])
	var height: float = float(look["flame_height_r"])
	return build("Flames", int(look["flame_amount"]), lifetime,
		float(look["core_scale_r"]), height / lifetime, 12.0, size,
		look["flame_hot_color"], look["flame_cool_color"])


## The embers: smaller, longer lived, thrown higher and wider than the flames.
static func embers(look: Dictionary) -> GPUParticles3D:
	var lifetime: float = float(look["flame_lifetime"]) * 2.0
	var height: float = float(look["flame_height_r"]) * 1.5
	return build("Embers", int(look["ember_amount"]), lifetime,
		float(look["core_scale_r"]), height / lifetime, 35.0, float(look["flame_size_r"]) * 0.15,
		look["flame_hot_color"], look["flame_hot_color"])


## One soft-billboard particle system rising from a sphere of `emit_radius`
## at `speed`, fading from `hot` to `cool`. Shared with the meltdown fire and
## dust (`DebrisEffects`, #1331), so every fire in the mine burns alike.
static func build(node_name: String, amount: int, lifetime: float, emit_radius: float,
		speed: float, spread_deg: float, size: float, hot: Color, cool: Color) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = node_name
	# Zero particles is allowed by the look; the node needs at least one, so it
	# is kept and never emits.
	particles.amount = maxi(amount, 1)
	particles.set_meta("amount_wanted", amount)
	particles.lifetime = lifetime
	particles.local_coords = true
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach: float = speed * lifetime + emit_radius + size
	particles.visibility_aabb = AABB(Vector3(-reach, -emit_radius, -reach), Vector3(reach * 2.0, reach + emit_radius, reach * 2.0))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = emit_radius
	process.direction = Vector3.UP
	process.spread = spread_deg
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = speed * 0.7
	process.initial_velocity_max = speed
	process.scale_min = size * 0.6
	process.scale_max = size
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(hot.r, hot.g, hot.b, 1.0))
	ramp.set_color(1, Color(cool.r, cool.g, cool.b, 0.0))
	ramp.add_point(0.5, Color(cool.r, cool.g, cool.b, 0.7))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = ramp
	process.color_ramp = texture
	particles.process_material = process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _soft_dot()
	quad.material = material
	particles.draw_pass_1 = quad
	return particles


## A round spot that fades to nothing at its edge, generated in code, so each
## particle reads as a soft tongue of flame rather than a square (ARC-5: no
## image file).
static func _soft_dot() -> GradientTexture2D:
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = fade
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	return texture
