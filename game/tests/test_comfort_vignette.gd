extends RefCounted

## The vignette row of the comfort table (CMF-1, CMF-2) and the node that
## shows it (PRF-2). The headless dummy renderer still parses shaders, so a
## shader that does not compile reports no uniforms.

const PRESET_DIR: String = "res://xr/presets"
const Trigger = ComfortPreset.VignetteTrigger

## Straight flight at the ship's normal top speed, metres per second.
const CRUISE_M_PER_S: float = 20.0
## A brisk smooth turn, radians per second.
const TURN_RAD_PER_S: float = deg_to_rad(60.0)
## Speeds that cover standing still to far past every threshold.
const ANGULAR_SAMPLES: Array[float] = [0.0, 0.05, 0.5, 1.0, 1.6, 3.0, 6.0, 60.0]
const LINEAR_SAMPLES: Array[float] = [0.0, 0.4, 1.0, 10.0, 20.0, 35.0, 500.0]


func _preset(name: String) -> ComfortPreset:
	return load("%s/comfort_%s.tres" % [PRESET_DIR, name]) as ComfortPreset


func _custom(trigger: ComfortPreset.VignetteTrigger, strength: float) -> ComfortPreset:
	var preset: ComfortPreset = ComfortPreset.new()
	preset.vignette_trigger = trigger
	preset.vignette_strength = strength
	return preset


func test_preset_4_gives_zero_for_any_motion() -> String:
	var preset: ComfortPreset = _preset("unrestricted")
	for angular: float in ANGULAR_SAMPLES:
		for linear: float in LINEAR_SAMPLES:
			var value: float = ComfortVignette.strength(preset, angular, linear)
			if value != 0.0:
				return "preset 4 gave %f at %f rad/s, %f m/s" % [value, angular, linear]
	return ""


func test_all_motion_is_on_for_straight_flight() -> String:
	var preset: ComfortPreset = _custom(Trigger.ALL_MOTION, 0.8)
	if ComfortVignette.strength(preset, 0.0, CRUISE_M_PER_S) <= 0.0:
		return "ALL_MOTION gave 0 for straight flight"
	if ComfortVignette.strength(_preset("anchored"), 0.0, CRUISE_M_PER_S) <= 0.0:
		return "preset 1 gave 0 for straight flight"
	if ComfortVignette.strength(preset, 0.0, 0.0) != 0.0:
		return "ALL_MOTION is on while the ship hovers"
	return ""


func test_rotation_is_off_for_straight_flight_and_on_when_turning() -> String:
	var preset: ComfortPreset = _custom(Trigger.ROTATION, 0.5)
	if ComfortVignette.strength(preset, 0.0, CRUISE_M_PER_S) != 0.0:
		return "ROTATION is on in straight flight"
	if ComfortVignette.strength(preset, TURN_RAD_PER_S, CRUISE_M_PER_S) <= 0.0:
		return "ROTATION is off while turning"
	if ComfortVignette.strength(preset, -TURN_RAD_PER_S, 0.0) <= 0.0:
		return "ROTATION ignores a negative turn rate"
	if ComfortVignette.strength(_preset("guided"), TURN_RAD_PER_S, 0.0) <= 0.0:
		return "preset 2 is off while turning"
	return ""


func test_fast_rotation_is_off_below_its_threshold() -> String:
	var preset: ComfortPreset = _custom(Trigger.FAST_ROTATION, 0.25)
	var threshold: float = ComfortVignette.FAST_ROTATION_START_RAD_PER_S
	for angular: float in [0.0, TURN_RAD_PER_S, threshold * 0.99, threshold]:
		if ComfortVignette.strength(preset, angular, 500.0) != 0.0:
			return "FAST_ROTATION is on at %f rad/s" % angular
	if ComfortVignette.strength(preset, threshold * 1.5, 0.0) <= 0.0:
		return "FAST_ROTATION is off above its threshold"
	if ComfortVignette.strength(_preset("pilot"), ComfortVignette.FAST_ROTATION_FULL_RAD_PER_S, 0.0) <= 0.0:
		return "preset 3 is off in a fast turn"
	return ""


func test_never_exceeds_preset_strength() -> String:
	var presets: Array[ComfortPreset] = [
		_preset("anchored"), _preset("guided"), _preset("pilot"), _preset("unrestricted"),
	]
	for trigger: int in [Trigger.NEVER, Trigger.FAST_ROTATION, Trigger.ROTATION, Trigger.ALL_MOTION]:
		presets.append(_custom(trigger as ComfortPreset.VignetteTrigger, 0.6))
	for preset: ComfortPreset in presets:
		var peak: float = 0.0
		for angular: float in ANGULAR_SAMPLES:
			for linear: float in LINEAR_SAMPLES:
				var value: float = ComfortVignette.strength(preset, angular, linear)
				if value < 0.0 or value > preset.vignette_strength:
					return "%s/%d gave %f, cap %f" % [preset.display_name, preset.vignette_trigger,
						value, preset.vignette_strength]
				peak = maxf(peak, value)
		if preset.vignette_trigger != Trigger.NEVER and not is_equal_approx(peak, preset.vignette_strength):
			return "%s/%d never reaches its strength (peak %f)" % [preset.display_name,
				preset.vignette_trigger, peak]
	return ""


func test_never_trigger_and_null_preset_give_zero() -> String:
	if ComfortVignette.strength(_custom(Trigger.NEVER, 1.0), 60.0, 500.0) != 0.0:
		return "NEVER gave a vignette"
	if ComfortVignette.strength(null, 60.0, 500.0) != 0.0:
		return "a missing preset gave a vignette"
	return ""


func test_shader_compiles() -> String:
	var shader: Shader = load("res://xr/vignette.gdshader") as Shader
	if shader == null:
		return "vignette.gdshader did not load"
	if shader.get_mode() != Shader.MODE_SPATIAL:
		return "vignette shader is not a spatial shader"
	var names: Array[String] = []
	for uniform: Dictionary in shader.get_shader_uniform_list():
		names.append(str(uniform["name"]))
	if not names.has("strength"):
		return "shader did not compile or has no strength uniform: %s" % str(names)
	if shader.code.contains("screen_texture") or shader.code.contains("hint_screen"):
		return "vignette reads the screen; it must not be a post-process pass"
	return ""


func test_scene_loads_and_hides_at_zero() -> String:
	var scene: PackedScene = load("res://xr/vignette.tscn") as PackedScene
	if scene == null:
		return "vignette.tscn did not load"
	var node: Node = scene.instantiate()
	var vignette: Vignette = node as Vignette
	if vignette == null:
		node.free()
		return "vignette.tscn root is not a Vignette"
	var result: String = ""
	if vignette.visible:
		result = "vignette is visible before any strength is set"
	elif not (vignette.mesh is QuadMesh) or not (vignette.material_override is ShaderMaterial):
		result = "vignette is not a quad with a shader material"
	else:
		vignette.set_strength(0.6)
		if not vignette.visible or not is_equal_approx(vignette.get_strength(), 0.6):
			result = "strength 0.6 not shown (visible %s, %f)" % [vignette.visible, vignette.get_strength()]
		vignette.set_strength(2.0)
		if result == "" and not is_equal_approx(vignette.get_strength(), 1.0):
			result = "strength above 1 is not clamped"
		vignette.set_strength(0.0)
		if result == "" and vignette.visible:
			result = "vignette stays visible at strength 0"
	node.free()
	return result


func test_rig_camera_carries_the_vignette() -> String:
	var rig: Node = (load("res://xr/xr_rig.tscn") as PackedScene).instantiate()
	var ok: bool = rig.get_node_or_null("Camera/Vignette") is Vignette
	rig.free()
	return "" if ok else "XRRig/Camera has no Vignette"
