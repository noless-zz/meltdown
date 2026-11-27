extends RefCounted

## The mine's emergency look after the reactor dies (#1454, GFX-6, GFX-4,
## CMF-8, ARC-4, MP-2): the look's `meltdown` section is checked key by key and
## against the comfort caps, the pulse is zero before the death, ramps in and
## stays within its bounds, the level's two materials carry it in one uniform,
## and without the section nothing changes.

const SHADER_FILE: String = "res://view/level_wall.gdshader"


func _shipped() -> Dictionary:
	return LevelLook.load_file()[MeltdownWallRules.KEY]


func _rules() -> Dictionary:
	return MeltdownWallRules.parse(_shipped())


func _one_box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	return BoxUnion.new(boxes)


func _rejects(change: Dictionary, field: String) -> String:
	var data: Dictionary = _shipped().duplicate(true)
	for key: String in change:
		if change[key] == null:
			data.erase(key)
		else:
			data[key] = change[key]
	var parsed: Dictionary = MeltdownWallRules.parse(JSON.parse_string(JSON.stringify(data)))
	if not parsed.has("error"):
		return "%s was accepted" % JSON.stringify(change)
	return "" if (parsed["error"] as String).contains(field) else "error \"%s\" does not name %s" % [parsed["error"], field]


## Unset (the shader's default) or set to the off value.
func _off(value: Variant) -> bool:
	return value == null or (value is Vector3 and value == MeltdownWalls.OFF)


func test_the_shipped_section_parses() -> String:
	var rules: Dictionary = _rules()
	if rules.has("error"):
		return "level_look.json: %s" % rules["error"]
	for key: String in MeltdownWallRules.keys():
		if not rules.has(key):
			return "the parsed rules lack %s" % key
	return ""


func test_each_bad_key_names_its_field() -> String:
	var cases: Array[Array] = [
		[{"strobe": 1}, "strobe"],
		[{"period_s": null}, "period_s"],
		[{"ramp_s": null}, "ramp_s"],
		[{"ramp_s": 0.1}, "ramp_s"],
		[{"low_emission": true}, "low_emission"],
		[{"ambient_shift": 1.5}, "ambient_shift"],
		[{"wall_color": [1, 0]}, "wall_color"],
		[{"ambient_color": [1, 2, 0]}, "ambient_color"],
		[{"strip_color": "red"}, "strip_color"],
		[{"strip_color": null}, "strip_color"],
		[{"low_emission": 0.1, "high_emission": 0.05}, "low_emission"],
	]
	for case: Array in cases:
		var problem: String = _rejects(case[0], case[1])
		if problem != "":
			return problem
	if not MeltdownWallRules.parse([1, 2]).has("error"):
		return "a section that is not an object was accepted"
	return ""


func test_the_comfort_caps_refuse_a_flashing_pulse() -> String:
	var cases: Array[Array] = [
		[{"period_s": 0.9}, "period_s"],
		[{"period_s": 0.2}, "period_s"],
		[{"high_emission": MeltdownWallRules.MAX_EMISSION + 0.01}, "high_emission"],
		[{"low_emission": 0.0, "high_emission": MeltdownWallRules.MAX_EMISSION_SWING + 0.01}, "high_emission"],
		[{"strip_swing": MeltdownWallRules.MAX_STRIP_SWING + 0.01}, "strip_swing"],
	]
	for case: Array in cases:
		var problem: String = _rejects(case[0], case[1])
		if problem != "":
			return problem
	var slowest: Dictionary = _shipped().duplicate(true)
	slowest["period_s"] = MeltdownWallRules.MIN_PERIOD_S
	slowest["low_emission"] = 0.0
	slowest["high_emission"] = MeltdownWallRules.MAX_EMISSION_SWING
	if MeltdownWallRules.parse(slowest).has("error"):
		return "the caps themselves were refused: %s" % MeltdownWallRules.parse(slowest)["error"]
	return ""


func test_the_pulse_is_off_before_the_death_and_ramps_in() -> String:
	var rules: Dictionary = _rules()
	for before: float in [-10.0, -0.01]:
		if MeltdownWalls.amount(rules, before) != MeltdownWalls.OFF:
			return "%s s before the death the look is %s, not off" % [before, MeltdownWalls.amount(rules, before)]
	var at_death: Vector3 = MeltdownWalls.amount(rules, 0.0)
	if at_death.x != 0.0 or at_death.y != 0.0 or at_death.z != 1.0:
		return "at the moment of death the look is already %s" % at_death
	var ramp_s: float = float(rules["ramp_s"])
	var last: float = -1.0
	for step: int in 11:
		var ramp: float = MeltdownWalls.amount(rules, ramp_s * float(step) / 10.0).x
		if ramp < last:
			return "the ramp falls from %s to %s" % [last, ramp]
		last = ramp
	if not is_equal_approx(MeltdownWalls.amount(rules, ramp_s).x, 1.0):
		return "after ramp_s the ramp is %s, not 1" % MeltdownWalls.amount(rules, ramp_s).x
	return ""


func test_the_pulse_stays_within_its_bounds_and_repeats() -> String:
	var rules: Dictionary = _rules()
	var low: float = float(rules["low_emission"])
	var high: float = float(rules["high_emission"])
	var lowest_strip: float = 1.0 - float(rules["strip_swing"])
	var seen_low: float = INF
	var seen_high: float = -INF
	# Ten seconds at 60 a second, the simulation's ticks.
	for tick: int in 600:
		var value: Vector3 = MeltdownWalls.amount(rules, float(tick) / 60.0)
		if value.y < 0.0 or value.y > high + 1e-6 or value.y > MeltdownWallRules.MAX_EMISSION:
			return "at tick %d the emission is %s, outside 0..%s" % [tick, value.y, high]
		if value.z < lowest_strip - 1e-6 or value.z > 1.0:
			return "at tick %d the strips are at %s, outside %s..1" % [tick, value.z, lowest_strip]
		if float(tick) / 60.0 >= float(rules["ramp_s"]):
			seen_low = minf(seen_low, value.y)
			seen_high = maxf(seen_high, value.y)
	if absf(seen_low - low) > 0.005 or absf(seen_high - high) > 0.005:
		return "after the ramp the emission swings %s..%s, not %s..%s" % [seen_low, seen_high, low, high]
	var later: float = float(rules["ramp_s"]) + 1.3
	var a: Vector3 = MeltdownWalls.amount(rules, later)
	var b: Vector3 = MeltdownWalls.amount(rules, later + float(rules["period_s"]))
	if not a.is_equal_approx(b):
		return "one period apart the look is %s and %s" % [a, b]
	return ""


func test_show_sets_one_uniform_on_every_material() -> String:
	var look: Dictionary = LevelLook.load_file()
	var materials: Array[ShaderMaterial] = [LevelViewMeshes.kind_material(look), LevelLook.bevel_material(look)]
	var walls: MeltdownWalls = MeltdownWalls.for_look(look, materials)
	if not walls.enabled or walls.error != "":
		return "the shipped look gives no meltdown walls (%s)" % walls.error
	for material: ShaderMaterial in materials:
		if material.get_shader_parameter(MeltdownWalls.PARAMETER) != MeltdownWalls.OFF:
			return "a material starts with meltdown %s" % material.get_shader_parameter(MeltdownWalls.PARAMETER)
		var glow: Color = material.get_shader_parameter(MeltdownWalls.GLOW_PARAMETER)
		if not glow.is_equal_approx(walls.rules["wall_color"]):
			return "a material glows %s, not the look's %s" % [glow, walls.rules["wall_color"]]
	walls.show(5.0)
	var want: Vector3 = MeltdownWalls.amount(walls.rules, 5.0)
	for material: ShaderMaterial in materials:
		if material.get_shader_parameter(MeltdownWalls.PARAMETER) != want:
			return "after show(5) a material has %s, not %s" % [material.get_shader_parameter(MeltdownWalls.PARAMETER), want]
	walls.show(-1.0)
	if materials[0].get_shader_parameter(MeltdownWalls.PARAMETER) != MeltdownWalls.OFF:
		return "show(-1) did not turn the look off"
	return ""


func test_without_the_section_nothing_changes() -> String:
	var look: Dictionary = LevelLook.FALLBACK
	if look.has(MeltdownWallRules.KEY):
		return "the fallback look has a meltdown section"
	var material: ShaderMaterial = LevelLook.bevel_material(look)
	var materials: Array[ShaderMaterial] = [material]
	var walls: MeltdownWalls = MeltdownWalls.for_look(look, materials)
	walls.show(5.0)
	if walls.enabled or walls.error != "":
		return "no section gave enabled %s, error \"%s\"" % [walls.enabled, walls.error]
	if not _off(material.get_shader_parameter(MeltdownWalls.PARAMETER)):
		return "no section still set meltdown %s" % material.get_shader_parameter(MeltdownWalls.PARAMETER)
	var bad: Dictionary = LevelLook.FALLBACK.duplicate()
	bad[MeltdownWallRules.KEY] = {"period_s": 0.2}
	var rejected: MeltdownWalls = MeltdownWalls.for_look(bad, materials)
	rejected.show(5.0)
	if rejected.enabled or rejected.error == "" or not _off(material.get_shader_parameter(MeltdownWalls.PARAMETER)):
		return "a bad section was drawn (error \"%s\")" % rejected.error
	return ""


func test_the_level_view_draws_it_in_its_two_materials_and_adds_no_draw_call() -> String:
	var view: LevelView = LevelView.new()
	view.build(_one_box())
	var walls: MeltdownWalls = view.meltdown_walls
	var surfaces: int = view.surfaces_of(0)
	walls.show(3.0)
	var want: Vector3 = walls.value()
	var problem: String = ""
	if not walls.enabled:
		problem = "the shipped look's meltdown section was not used (%s)" % walls.error
	elif walls.materials().size() != 2:
		problem = "the look is drawn in %d materials, not the walls' and the bevels'" % walls.materials().size()
	elif surfaces > 2:
		problem = "the box costs %d draw calls" % surfaces
	elif view.box_node(0).find_children("*", "Light3D", true, false).size() > 0:
		problem = "the level holds a light"
	else:
		for part: MeshInstance3D in [view.walls_of(0), view.bevels_of(0)]:
			var material: ShaderMaterial = part.mesh.surface_get_material(0) as ShaderMaterial
			if material.get_shader_parameter(MeltdownWalls.PARAMETER) != want:
				problem = "%s draws %s, not %s" % [part.name, material.get_shader_parameter(MeltdownWalls.PARAMETER), want]
	view.free()
	return problem


func test_the_shader_declares_the_uniforms_with_a_calm_default() -> String:
	var text: String = FileAccess.get_file_as_string(SHADER_FILE)
	if not text.contains("uniform vec3 %s = vec3(0.0, 0.0, 1.0);" % MeltdownWalls.PARAMETER):
		return "the wall shader does not declare meltdown with the off value"
	for name: String in [MeltdownWalls.GLOW_PARAMETER, MeltdownWalls.AMBIENT_PARAMETER,
			MeltdownWalls.SHIFT_PARAMETER, MeltdownWalls.STRIP_PARAMETER]:
		if not text.contains("uniform") or not text.contains(" %s " % name):
			return "the wall shader does not declare %s" % name
	if text.contains("hint_screen_texture"):
		return "the wall shader reads the screen"
	return ""


func test_the_m6_step_flies_the_stress_replay_past_the_death_with_the_check() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return "the m6 suite did not load"
	var step: AcceptanceStep = null
	var stress: AcceptanceStep = null
	for each: AcceptanceStep in found[0].steps:
		if each.id == "meltdown_walls":
			step = each
		elif each.id == "stress_scene":
			stress = each
	if step == null or stress == null:
		return "steps found: meltdown_walls %s, stress_scene %s" % [step, stress]
	# The stress scene's reactor dies within its first second (`StressScene`).
	if step.replay_path != stress.replay_path or step.expected_hash != stress.expected_hash or step.level != "stress":
		return "the step flies %s pinned at %d, not the stress scene" % [step.replay_path, step.expected_hash]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS, "meltdown_walls_shown"]:
		if not step.checks.has(check):
			return "the step does not check %s: %s" % [check, step.checks]
	if not step.screenshot_at_end:
		return "the step saves no screenshot at its end"
	return ""
