class_name LevelLookMaterials
extends RefCounted

## Builds the wall and bevel materials and the environment of a mine from a
## look parsed by `LevelLook` (GFX-4, LGT-1). Kept apart from the parser so
## each file holds one job: `LevelLook` reads and checks the file, this turns
## the result into what Godot draws (#1446).

## A lit material in `tint` with `look`'s plating, world-space grid and
## distance fog. One per surface class; walls of every level share the shader.
## Every material carries the plating of all three kinds, since the shader
## picks one per face from its normal. `surface` is a `LevelWallMaterial`
## theme; empty takes the shipped default theme (GFX-2).
static func wall_material(look: Dictionary, tint: Color, surface: Dictionary = {}) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(LevelLook.WALL_SHADER) as Shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("roughness_value", float(look["roughness"]))
	material.set_shader_parameter("grid_spacing", float(look["grid_spacing_m"]))
	material.set_shader_parameter("line_width", float(look["grid_line_width_m"]))
	material.set_shader_parameter("line_factor", float(look["grid_line_factor"]))
	material.set_shader_parameter("plate_size", plate_vector(look, "m"))
	material.set_shader_parameter("plate_aspect", plate_vector(look, "aspect"))
	material.set_shader_parameter("plate_stagger", plate_vector(look, "stagger"))
	material.set_shader_parameter("seam_width", float(look["plate_seam_m"]))
	material.set_shader_parameter("plate_contrast", float(look["plate_contrast"]))
	material.set_shader_parameter("floor_min_up", LevelLook.FLOOR_MIN_UP)
	material.set_shader_parameter("fog_color", look["fog_color"])
	material.set_shader_parameter("fog_density", float(look["fog_density"]))
	# The shader adds ambient itself (#1400); without a bake it is the global one.
	var ambient: Color = AmbientBake.global(look)
	material.set_shader_parameter("ambient_light", Vector3(ambient.r, ambient.g, ambient.b))
	LevelWallMaterial.apply(material, surface if not surface.is_empty() else LevelWallMaterial.load_theme())
	return material


## The material of the bevels along box edges: the walls' material in the
## wall tint, glowing dimly in `edge_color` at `edge_energy`, so box edges
## still read in the dark (#609). Walls themselves never glow.
static func bevel_material(look: Dictionary, surface: Dictionary = {}) -> ShaderMaterial:
	var material: ShaderMaterial = wall_material(look, look["wall_color"], surface)
	var edge: Color = look["edge_color"]
	material.set_shader_parameter("glow", edge * float(look["edge_energy"]))
	return material


## One plating value per kind, in `LevelLook.SHADER_KINDS` order: `part` is "m",
## "aspect" or "stagger".
static func plate_vector(look: Dictionary, part: String) -> Vector3:
	var values: Array[float] = []
	for kind: String in LevelLook.SHADER_KINDS:
		values.append(float(look["plate_%s_%s" % [kind, part]]))
	return Vector3(values[0], values[1], values[2])


## The environment every level is drawn in: dark background in the fog's
## colour and low ambient light. Fog is the walls' own (`wall_material`).
static func environment(look: Dictionary) -> Environment:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = look["fog_color"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = look["ambient_color"]
	env.ambient_light_energy = float(look["ambient_energy"])
	env.fog_enabled = false
	return env


## A `WorldEnvironment` node named `node_name` holding `environment(look)`.
static func world_environment(look: Dictionary, node_name: String) -> WorldEnvironment:
	var world: WorldEnvironment = WorldEnvironment.new()
	world.name = node_name
	world.environment = environment(look)
	return world
