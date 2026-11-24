class_name DebrisEffects
extends RefCounted

## The meltdown fire and debris look on top of `DebrisView`'s shapes (#1331,
## GFX-2, GFX-6, RUN-4): particle flames and embers on every burning fire, a
## dust puff when a rock or slab lands, and rock and metal surfaces that match
## the theme's walls (#1292). The values come from `DebrisEffectsLook`; a
## section it lacks leaves that part as before.
##
## Particles hang under the entry they belong to, so a hidden entry hides them
## and freeing an entry frees them. The entry is scaled to its size, so each
## particle node carries the inverse of that scale times one uniform size: the
## particles keep their shape on a stretched slab. Nothing here adds a light
## (GFX-4), a collision or a full-screen pass (GFX-6), and nothing reads the
## simulation: the owner hands in each entry's state (MP-2).

const FLAMES_NAME: String = "Flames"
const EMBERS_NAME: String = "Embers"
const DUST_NAME: String = "Dust"
## The flames rise from this share of the fire's radius, so they fill the cone
## without spilling past the fire's edge, which still hurts the ship.
const FIRE_CORE_R: float = 0.7
## How widely the dust is thrown, in degrees from straight up: a low ring
## spreading over the floor rather than a fountain.
const DUST_SPREAD_DEG: float = 80.0

## Landings that raised dust, for tests and the acceptance check.
var landings: int = 0

var _look: Dictionary = {}
var _walls: Dictionary = {}
var _theme: Dictionary = {}


## `look` is a parsed `DebrisEffectsLook`, `walls` a `LevelLook` and `theme` a
## `LevelWallMaterial` theme, both of the walls the debris lies among.
func _init(look: Dictionary, walls: Dictionary, theme: Dictionary) -> void:
	_look = look
	_walls = walls
	_theme = theme


func look() -> Dictionary:
	return _look


## Gives the solid rock and the slab their surfaces from the walls, when the
## look has a `rock` or `metal` section; `debris_look` is the `DebrisLook` the
## materials were painted from. Without a section that material gets back
## the plain surface it had before #1331.
func paint_surfaces(materials: DebrisMaterials, debris_look: Dictionary) -> void:
	for material: StandardMaterial3D in [materials.solid, materials.slab]:
		material.roughness = 1.0
		material.metallic = 0.0
	if _look.has("rock"):
		var rock: Color = (debris_look["solid_color"] as Color).lerp(_walls["wall_color"], float(_look["rock"]["wall_mix"]))
		materials.solid.albedo_color = Color(rock.r, rock.g, rock.b, 1.0)
		materials.solid.roughness = float(_walls["roughness"])
		materials.solid.metallic = 0.0
	if _look.has("metal"):
		var metal: Color = (debris_look["slab_color"] as Color).lerp(_walls["wall_color"], float(_look["metal"]["wall_mix"]))
		materials.slab.albedo_color = Color(metal.r, metal.g, metal.b, 1.0)
		materials.slab.metallic = float(_theme["metallic"])
		materials.slab.roughness = float(_theme["metal_roughness"])


## Brings `entry`'s particles up to date. `burning` says a fire entry burns now;
## `landed` says a rock or slab became solid since the last call; `size_m` is
## the entry's half width in metres, which the particle sizes are in units of.
func update(entry: MeshInstance3D, burning: bool, landed: bool, size_m: float) -> void:
	if burning and _look.has("fire_flames"):
		_burn(entry, size_m)
	else:
		for node_name: String in [FLAMES_NAME, EMBERS_NAME]:
			var particles: GPUParticles3D = entry.get_node_or_null(node_name)
			if particles != null:
				particles.emitting = false
	if landed and _look.has("dust"):
		_raise_dust(entry, size_m)


## The flames of `entry`, or null.
static func flames_of(entry: MeshInstance3D) -> GPUParticles3D:
	return entry.get_node_or_null(FLAMES_NAME)


## The embers of `entry`, or null.
static func embers_of(entry: MeshInstance3D) -> GPUParticles3D:
	return entry.get_node_or_null(EMBERS_NAME)


## The dust of `entry`, or null when it never landed.
static func dust_of(entry: MeshInstance3D) -> GPUParticles3D:
	return entry.get_node_or_null(DUST_NAME)


func _burn(entry: MeshInstance3D, size_m: float) -> void:
	var flames: GPUParticles3D = flames_of(entry)
	if flames == null:
		var section: Dictionary = _look["fire_flames"]
		# The reactor's builder, handed the fire's values under its key names,
		# so the wreck and the meltdown fire burn alike (#1310).
		var shared: Dictionary = {
			"flame_amount": section["amount"], "ember_amount": section["ember_amount"],
			"flame_lifetime": section["lifetime"], "flame_height_r": section["height_r"],
			"flame_size_r": section["size_r"], "core_scale_r": FIRE_CORE_R,
			"flame_hot_color": section["hot_color"], "flame_cool_color": section["cool_color"],
		}
		flames = ReactorFlames.flames(shared)
		flames.name = FLAMES_NAME
		entry.add_child(flames)
		var embers: GPUParticles3D = ReactorFlames.embers(shared)
		embers.name = EMBERS_NAME
		entry.add_child(embers)
	for particles: GPUParticles3D in [flames, embers_of(entry)]:
		particles.scale = _uniform(entry, size_m)
		particles.emitting = int(particles.get_meta("amount_wanted", 1)) > 0


func _raise_dust(entry: MeshInstance3D, size_m: float) -> void:
	var dust: GPUParticles3D = dust_of(entry)
	if dust == null:
		dust = _build_dust(_look["dust"])
		entry.add_child(dust)
	dust.scale = _uniform(entry, size_m)
	if int(dust.get_meta("amount_wanted", 1)) <= 0:
		return
	dust.visible = true
	dust.restart()
	landings += 1


static func _build_dust(section: Dictionary) -> GPUParticles3D:
	var lifetime: float = float(section["lifetime"])
	var color: Color = section["color"]
	var dust: GPUParticles3D = ReactorFlames.build(DUST_NAME, int(section["amount"]), lifetime,
		1.0, float(section["spread_r"]) / lifetime, DUST_SPREAD_DEG, float(section["size_r"]),
		color, color)
	dust.one_shot = true
	dust.explosiveness = 1.0
	# Hidden once settled, so a landed rock costs no draw call afterwards.
	dust.finished.connect(func() -> void: dust.visible = false)
	var process: ParticleProcessMaterial = dust.process_material
	process.gravity = Vector3.DOWN * float(section["spread_r"]) / lifetime
	process.damping_min = float(section["spread_r"]) / lifetime
	process.damping_max = process.damping_min
	var quad: QuadMesh = dust.draw_pass_1
	var material: StandardMaterial3D = quad.material
	# Dust is dull and dark; added light would make it glow like the fire.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_color = Color(1.0, 1.0, 1.0, float(section["alpha"]))
	return dust


## The scale that makes a child of `entry` uniform at `size_m` per unit.
static func _uniform(entry: MeshInstance3D, size_m: float) -> Vector3:
	var parent: Vector3 = entry.scale.max(Vector3.ONE * 0.001)
	return Vector3(size_m / parent.x, size_m / parent.y, size_m / parent.z)
