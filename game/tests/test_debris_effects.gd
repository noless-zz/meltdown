extends RefCounted

## The meltdown fire and debris look (#1331, GFX-2, GFX-4, GFX-6, ARC-4): the
## shipped file builds; a burning fire gets particle flames and embers, a
## landing rock or slab one dust puff; rock and metal take the walls' surface;
## every documented key changes what is drawn; a missing section or file
## leaves today's look; nothing adds a light or a collision.

const SCRATCH_DIR: String = "user://test_debris_effects"
const EPSILON: float = 1e-4
const SLAB: Vector3 = Vector3(3, 2, 1)


## A rock sphere, a fire sphere and a slab: all warning, then the rock and
## slab land and the fire burns.
func _drive(view: DebrisView) -> void:
	var kinds: Array[String] = [MeltdownFire.KIND_SOLID, MeltdownFire.KIND_FIRE, MeltdownFire.KIND_SOLID]
	var positions: Array[Vector3] = [Vector3(0, 0, -20), Vector3(0, 0, -30), Vector3(0, 0, -40)]
	var radii: Array[float] = [2.0, 1.5, 0.0]
	var sizes: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, SLAB]
	var held: Array[bool] = [false, false, false]
	view.show_debris(positions, radii, [false, false, false] as Array[bool], held,
		[1.0, 1.0, 1.0] as Array[float], sizes, kinds, 10)
	view.show_debris(positions, radii, [true, false, true] as Array[bool], held,
		[0.0, 0.0, 0.0] as Array[float], sizes, kinds, 70)


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DebrisEffectsLook.DEFAULT_FILE))


func _view_with(data: Dictionary) -> DebrisView:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = "%s/look.json" % SCRATCH_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var view: DebrisView = DebrisView.new()
	view.load_effects(path)
	return view


func test_shipped_look_has_every_section() -> String:
	var look: Dictionary = DebrisEffectsLook.parse(FileAccess.get_file_as_string(DebrisEffectsLook.DEFAULT_FILE))
	if look.has("error"):
		return "shipped look rejected: %s" % look["error"]
	for section: String in DebrisEffectsLook.RANGES:
		if not look.has(section):
			return "shipped look has no \"%s\"" % section
	return ""


func test_a_burning_fire_has_flames_and_embers_and_a_landing_raises_dust() -> String:
	var view: DebrisView = DebrisView.new()
	_drive(view)
	var result: String = _check_effects(view)
	view.free()
	return result


func _check_effects(view: DebrisView) -> String:
	var fire: MeshInstance3D = view.entry(1)
	var flames: GPUParticles3D = DebrisEffects.flames_of(fire)
	var embers: GPUParticles3D = DebrisEffects.embers_of(fire)
	if flames == null or embers == null or not flames.emitting or not embers.emitting:
		return "the burning fire has no emitting flames and embers"
	var drawn: StandardMaterial3D = (flames.draw_pass_1 as QuadMesh).material
	if drawn.billboard_mode != BaseMaterial3D.BILLBOARD_PARTICLES:
		return "the flames are not particle billboards"
	if DebrisEffects.flames_of(view.entry(0)) != null or DebrisEffects.flames_of(view.entry(2)) != null:
		return "a rock or slab burns"
	if view.effects().landings != 2:
		return "%d landings raised dust, expected the rock and the slab" % view.effects().landings
	for index: int in [0, 2]:
		var dust: GPUParticles3D = DebrisEffects.dust_of(view.entry(index))
		if dust == null or not dust.one_shot or not dust.visible:
			return "entry %d landed without a dust puff" % index
	if DebrisEffects.dust_of(fire) != null:
		return "a fire raised dust"
	if not view.find_children("*", "Light3D", true, false).is_empty():
		return "the effects add a light (GFX-4)"
	if not view.find_children("*", "CollisionShape3D", true, false).is_empty():
		return "the effects add a collision"
	return ""


func test_the_flames_go_out_before_the_fire_burns_and_dust_rises_once() -> String:
	var view: DebrisView = DebrisView.new()
	_drive(view)
	var kinds: Array[String] = [MeltdownFire.KIND_SOLID, MeltdownFire.KIND_FIRE, MeltdownFire.KIND_SOLID]
	# The same landed snapshot again: nothing new lands.
	view.show_debris([Vector3(0, 0, -20), Vector3(0, 0, -30), Vector3(0, 0, -40)] as Array[Vector3],
		[2.0, 1.5, 0.0] as Array[float], [true, false, true] as Array[bool],
		[false, false, false] as Array[bool], [0.0, 2.0, 0.0] as Array[float],
		[Vector3.ZERO, Vector3.ZERO, SLAB] as Array[Vector3], kinds, 80)
	var result: String = ""
	if view.effects().landings != 2:
		result = "dust rose again on the same landing: %d" % view.effects().landings
	elif DebrisEffects.flames_of(view.entry(1)).emitting:
		result = "a fire that is only warning again still emits flames"
	view.free()
	if result != "":
		return result
	# A view that first sees debris already down raises no dust: it fell unseen.
	var late: DebrisView = DebrisView.new()
	late.show_debris([Vector3.ZERO] as Array[Vector3], [2.0] as Array[float], [true] as Array[bool],
		[false] as Array[bool], [0.0] as Array[float])
	if late.effects().landings != 0:
		result = "debris already down when first drawn raised dust"
	late.free()
	return result


func test_particles_keep_their_shape_on_a_stretched_slab() -> String:
	var data: Dictionary = _shipped()
	var view: DebrisView = _view_with(data)
	_drive(view)
	var slab: MeshInstance3D = view.entry(2)
	var dust: GPUParticles3D = DebrisEffects.dust_of(slab)
	var seen: Vector3 = slab.scale * dust.scale
	var want: float = 0.5 * maxf(SLAB.x, SLAB.z)
	view.free()
	if not seen.is_equal_approx(Vector3.ONE * want):
		return "the slab's dust is scaled %s, expected a uniform %s" % [seen, want]
	return ""


func test_rock_and_metal_take_the_walls_surface() -> String:
	var view: DebrisView = DebrisView.new()
	var walls: Dictionary = LevelLook.load_or_fallback()
	var theme: Dictionary = LevelWallMaterial.load_theme()
	var effects: Dictionary = view.effects().look()
	var rock: Color = (view.look()["solid_color"] as Color).lerp(walls["wall_color"], float(effects["rock"]["wall_mix"]))
	var metal: Color = (view.look()["slab_color"] as Color).lerp(walls["wall_color"], float(effects["metal"]["wall_mix"]))
	var solid: StandardMaterial3D = view.material_for(DebrisView.EntryState.SOLID)
	var slab: StandardMaterial3D = view.slab_material_for(DebrisView.EntryState.SOLID)
	var result: String = ""
	if not solid.albedo_color.is_equal_approx(Color(rock.r, rock.g, rock.b, 1.0)) \
			or absf(solid.roughness - float(walls["roughness"])) > EPSILON or solid.metallic != 0.0:
		result = "the rock is %s rough %.2f metal %.2f, not the walls' rock" % [solid.albedo_color, solid.roughness, solid.metallic]
	elif not slab.albedo_color.is_equal_approx(Color(metal.r, metal.g, metal.b, 1.0)) \
			or absf(slab.metallic - float(theme["metallic"])) > EPSILON \
			or absf(slab.roughness - float(theme["metal_roughness"])) > EPSILON:
		result = "the slab is %s metal %.2f rough %.2f, not the walls' metal" % [slab.albedo_color, slab.metallic, slab.roughness]
	elif not solid.emission.is_equal_approx(view.look()["solid_color"]):
		result = "the rock lost its faint glow (LGT-1)"
	view.free()
	return result


func test_every_documented_key_changes_what_is_drawn() -> String:
	var base: Array = _fingerprint(_shipped())
	for section: String in DebrisEffectsLook.RANGES:
		var keys: Array = (DebrisEffectsLook.RANGES[section] as Dictionary).keys()
		keys.append_array(DebrisEffectsLook.COLOR_KEYS[section])
		for key: String in keys:
			var data: Dictionary = _shipped()
			var value: Variant = data[section][key]
			if typeof(value) == TYPE_ARRAY:
				data[section][key] = [1.0 - float(value[0]), 1.0 - float(value[1]), 0.5]
			else:
				var bounds: Array = DebrisEffectsLook.RANGES[section][key]
				var middle: float = (float(bounds[0]) + float(bounds[1])) * 0.5
				data[section][key] = roundf(middle) + 1.0 if DebrisEffectsLook.INT_KEYS.has(key) \
					else (float(bounds[0]) if float(value) > middle else float(bounds[1]))
			if _fingerprint(data) == base:
				return "changing %s.%s changed nothing drawn" % [section, key]
	return ""


func test_a_missing_section_or_file_leaves_todays_look() -> String:
	var data: Dictionary = {}
	var view: DebrisView = _view_with(data)
	_drive(view)
	var result: String = ""
	if DebrisEffects.flames_of(view.entry(1)) != null or DebrisEffects.dust_of(view.entry(0)) != null:
		result = "without sections the debris still has particles"
	elif not view.material_for(DebrisView.EntryState.SOLID).albedo_color.is_equal_approx(view.look()["solid_color"]):
		result = "without a rock section the rock is not today's colour"
	elif view.slab_material_for(DebrisView.EntryState.SOLID).metallic != 0.0:
		result = "without a metal section the slab is metal"
	view.free()
	if result != "":
		return result
	var gone: DebrisView = DebrisView.new()
	gone.load_effects("%s/missing.json" % SCRATCH_DIR)
	if not gone.effects().look().is_empty():
		result = "a missing file left effects on"
	gone.free()
	return result


func test_bad_values_are_rejected_naming_the_key() -> String:
	var cases: Dictionary[String, String] = {
		'{"fire_flames": {"amount": 20}}': "fire_flames.hot_color",
		'{"dust": {"amount": 1.5, "lifetime": 1, "size_r": 1, "spread_r": 1, "color": [0,0,0], "alpha": 1}}': "dust.amount",
		'{"rock": {"wall_mix": 2}}': "rock.wall_mix",
		'{"metal": {"wall_mix": true}}': "metal.wall_mix",
		'{"rock": {"wall_mix": 0.5, "shine": 1}}': "rock.shine",
		'{"smoke": {}}': "smoke",
	}
	for text: String in cases:
		var look: Dictionary = DebrisEffectsLook.parse(text)
		if not look.has("error") or not str(look["error"]).contains(cases[text]):
			return "%s gave %s, expected an error naming %s" % [text, look, cases[text]]
	return ""


## What the look decides, as plain values, for comparing two looks.
func _fingerprint(data: Dictionary) -> Array:
	var view: DebrisView = _view_with(data)
	_drive(view)
	var values: Array = []
	for particles: GPUParticles3D in [DebrisEffects.flames_of(view.entry(1)),
			DebrisEffects.embers_of(view.entry(1)), DebrisEffects.dust_of(view.entry(0))]:
		var process: ParticleProcessMaterial = particles.process_material
		var ramp: Gradient = (process.color_ramp as GradientTexture1D).gradient
		var material: StandardMaterial3D = (particles.draw_pass_1 as QuadMesh).material
		values.append_array([particles.get_meta("amount_wanted"), particles.lifetime,
			process.initial_velocity_max, process.scale_max, process.emission_sphere_radius,
			ramp.get_color(0), ramp.get_color(1), material.albedo_color])
	for material: StandardMaterial3D in [view.material_for(DebrisView.EntryState.SOLID),
			view.slab_material_for(DebrisView.EntryState.SOLID)]:
		values.append_array([material.albedo_color, material.roughness, material.metallic])
	view.free()
	return values
