extends RefCounted

## The reactor drawn as a machine (#1310, GFX-2, GFX-4, GFX-6, ARC-4): the
## shipped look builds a cage, pipes and flames; every documented key changes
## what is built; a missing key falls back to its default and a look without a
## machine is the bare sphere of before; the wreck is breached and burning;
## the machine adds no light; pipes stop at the walls; pausing holds the flames.

const EPSILON: float = 1e-4


func _shipped_machine() -> Dictionary:
	var parsed: Dictionary = ReactorLook.parse(FileAccess.get_file_as_string(ReactorLook.DEFAULT_FILE))
	return parsed.get(ReactorLook.MACHINE_KEY, {})


## Everything the built machine shows, as text, so two builds can be compared.
func _signature(look: Dictionary) -> String:
	var machine: ReactorMachine = ReactorMachine.new(look)
	machine.set_radius(2.0)
	machine.set_destroyed(true)
	var parts: PackedStringArray = PackedStringArray()
	for node: Node in machine.get_children():
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node
			parts.append("%s %s %s %s" % [node.name, mesh_node.visible, mesh_node.transform, _mesh_text(mesh_node.mesh)])
			var material: StandardMaterial3D = mesh_node.material_override
			if material != null:
				parts.append("%s %s %s" % [material.albedo_color, material.metallic, material.roughness])
		elif node is GPUParticles3D:
			var particles: GPUParticles3D = node
			var process: ParticleProcessMaterial = particles.process_material
			var ramp: Gradient = (process.color_ramp as GradientTexture1D).gradient
			parts.append("%s %d %s %s %s %s %s %s" % [node.name, particles.get_meta("amount_wanted"),
				particles.lifetime, process.emission_sphere_radius, process.initial_velocity_max,
				process.scale_max, ramp.get_color(0), ramp.get_color(1)])
	parts.append(str(machine.scale))
	machine.set_destroyed(false)
	for node: Node in machine.get_children():
		if node is MeshInstance3D:
			var material_intact: StandardMaterial3D = (node as MeshInstance3D).material_override
			if material_intact != null:
				parts.append("%s %s %s" % [material_intact.albedo_color, material_intact.metallic, material_intact.roughness])
	machine.free()
	return "\n".join(parts)


func _mesh_text(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		return str((mesh as BoxMesh).size)
	if mesh is CylinderMesh:
		var cylinder: CylinderMesh = mesh
		return "%s %s %s" % [cylinder.top_radius, cylinder.bottom_radius, cylinder.height]
	return ""


## A valid value for `key` other than its default.
func _other_value(key: String, look: Dictionary) -> Variant:
	var value: Variant = look[key]
	if value is Color:
		return [0.1, 0.9, 0.5]
	if value is Dictionary:
		return {"color": [0.6, 0.1, 0.2], "metallic": 0.1, "roughness": 0.2}
	var bounds: Array = ReactorMachineLook.RANGES[key]
	var low: float = float(bounds[0])
	var high: float = float(bounds[1])
	var other: float = low if absf(float(value) - low) > EPSILON else high
	if key == "ribs":
		other = high
	if key == "breached_ribs":
		other = 1.0 if int(value) != 1 else 2.0
	if key == "core_scale_r":
		# The machine shows the core's size through the flames' source.
		other = 0.3
	if ReactorMachineLook.WHOLE_KEYS.has(key):
		return int(other)
	return other


func test_shipped_look_has_a_machine_and_is_accepted() -> String:
	var view: ReactorView = ReactorView.new()
	var result: String = view.look_error
	if result == "" and view.machine() == null:
		result = "the shipped look builds no machine"
	elif result == "" and view.machine().ribs().size() != int(ReactorMachineLook.DEFAULTS["ribs"]):
		result = "%d ribs built" % view.machine().ribs().size()
	elif result == "" and view.machine().pipes().size() != int(ReactorMachineLook.DEFAULTS["pipes"]):
		result = "%d pipes built" % view.machine().pipes().size()
	view.free()
	return result


func test_defaults_match_the_shipped_file() -> String:
	var shipped: Dictionary = _shipped_machine()
	for key: String in ReactorMachineLook.DEFAULTS:
		if not shipped.has(key):
			return "the shipped machine lacks %s" % key
		if str(shipped[key]) != str(ReactorMachineLook.DEFAULTS[key]):
			return "%s: file %s, built-in %s" % [key, shipped[key], ReactorMachineLook.DEFAULTS[key]]
	return ""


func test_every_documented_key_changes_the_result() -> String:
	var base: String = _signature(ReactorMachineLook.DEFAULTS)
	for key: String in ReactorMachineLook.DEFAULTS:
		var data: Dictionary = {key: _other_value(key, ReactorMachineLook.DEFAULTS)}
		var look: Dictionary = ReactorMachineLook.parse(data)
		if look.has("error"):
			return "%s=%s was rejected: %s" % [key, data[key], look["error"]]
		if _signature(look) == base:
			return "changing %s to %s changes nothing that is built" % [key, data[key]]
	return ""


func test_each_missing_key_falls_back_to_its_default() -> String:
	var full: Dictionary = {}
	for key: String in ReactorMachineLook.DEFAULTS:
		full[key] = _other_value(key, ReactorMachineLook.DEFAULTS)
	for key: String in ReactorMachineLook.DEFAULTS:
		var data: Dictionary = full.duplicate(true)
		data.erase(key)
		if key == "ribs":
			data.erase("breached_ribs")
		var look: Dictionary = ReactorMachineLook.parse(data)
		if look.has("error"):
			return "without %s: %s" % [key, look["error"]]
		if str(look[key]) != str(ReactorMachineLook.DEFAULTS[key]):
			return "without %s it is %s, not the default %s" % [key, look[key], ReactorMachineLook.DEFAULTS[key]]
	if str(ReactorMachineLook.parse({})) != str(ReactorMachineLook.DEFAULTS):
		return "an empty machine is not the default machine"
	return ""


func test_a_look_without_a_machine_is_the_bare_sphere_of_before() -> String:
	var view: ReactorView = ReactorView.new()
	var path: String = "user://test_reactor_machine_bare.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ReactorLook.DEFAULT_FILE))
	data.erase(ReactorLook.MACHINE_KEY)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var error: String = view.load_look(path)
	view.show_state(Vector3.ZERO, 2.5, 1.0, false, 90.0)
	var result: String = ""
	if error != "":
		result = error
	elif view.machine() != null:
		result = "a look without a machine still builds one"
	elif absf(view.core_radius() - 2.5) > EPSILON:
		result = "bare core radius %s, expected the whole 2.5" % view.core_radius()
	elif view.get_child_count() != 2:
		result = "%d children, expected the core and the light" % view.get_child_count()
	view.free()
	DirAccess.remove_absolute(path)
	return result


func test_rejects_bad_machine_values_and_names_them() -> String:
	var cases: Dictionary[String, Variant] = {
		"ribs": 2, "pipes": 1.5, "flame_amount": true, "flame_hot_color": [1.0, 0.5],
		"housing_material": {"shine": 1.0}, "pipe_material": {"metallic": 2.0}, "unknown": 1,
	}
	for key: String in cases:
		var look: Dictionary = ReactorMachineLook.parse({key: cases[key]})
		if not look.has("error"):
			return "%s=%s was accepted" % [key, cases[key]]
		if not (look["error"] as String).contains(key):
			return "the error for %s does not name it: %s" % [key, look["error"]]
	if not ReactorMachineLook.parse({"ribs": 4, "breached_ribs": 4}).has("error"):
		return "a wreck with every rib breached was accepted"
	if not ReactorLook.parse("{\"machine\": 3}").has("error"):
		return "a machine that is not an object was accepted"
	return ""


func test_wreck_is_breached_scorched_and_burning() -> String:
	var machine: ReactorMachine = ReactorMachine.new(ReactorMachineLook.DEFAULTS)
	var intact_top: Transform3D = machine.top_cap().transform
	var hidden_intact: int = 0
	for rib: MeshInstance3D in machine.ribs():
		hidden_intact += 0 if rib.visible else 1
	var result: String = ""
	if hidden_intact != 0 or machine.flames().emitting or machine.embers().emitting:
		result = "the intact machine is already broken or burning"
	machine.set_destroyed(true)
	var hidden: int = 0
	for rib: MeshInstance3D in machine.ribs():
		hidden += 0 if rib.visible else 1
	if result == "" and hidden != int(ReactorMachineLook.DEFAULTS["breached_ribs"]):
		result = "%d ribs breached, expected %d" % [hidden, ReactorMachineLook.DEFAULTS["breached_ribs"]]
	elif result == "" and machine.top_cap().transform.is_equal_approx(intact_top):
		result = "the top cap did not move"
	elif result == "" and not (machine.flames().emitting and machine.embers().emitting):
		result = "the wreck does not burn"
	elif result == "" and (machine.ribs()[-1].material_override as StandardMaterial3D).albedo_color != ReactorMachineLook.DEFAULTS["scorched_material"]["color"]:
		result = "the remaining ribs are not scorched"
	machine.free()
	return result


func test_machine_adds_no_light_and_no_shadow() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 0.0, true, 30.0)
	var lights: int = 0
	var result: String = ""
	for node: Node in view.machine().find_children("*", "", true, false):
		if node is Light3D:
			lights += 1
		elif node is GeometryInstance3D and (node as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			result = "%s casts a shadow; only the headlight may (GFX-4)" % node.name
	if result == "" and lights != 0:
		result = "the machine adds %d lights (GFX-4)" % lights
	view.free()
	return result


func test_pipes_stop_at_the_walls() -> String:
	var box: BoxBounds = BoxBounds.new(Vector3(-6.0, -4.0, -6.0), Vector3(6.0, 4.0, 6.0))
	var walls: BoxUnion = BoxUnion.new([box] as Array[BoxBounds])
	var look: Dictionary = ReactorMachineLook.DEFAULTS
	var reach: PackedFloat32Array = ReactorMachine.reach_in(walls, look, Vector3.ZERO, 2.0)
	# Pipes leave at 45 degrees, so they meet a wall of a 12 m room at 6 * sqrt(2).
	var want: float = 6.0 * sqrt(2.0)
	for value: float in reach:
		if absf(value - want) > 0.3:
			return "a pipe reaches %s m, expected about %s m" % [value, want]
	var open: PackedFloat32Array = ReactorMachine.reach_in(BoxUnion.new([BoxBounds.new(Vector3.ONE * -100.0, Vector3.ONE * 100.0)] as Array[BoxBounds]), look, Vector3.ZERO, 2.0)
	if absf(open[0] - float(look["pipe_max_length_m"])) > EPSILON:
		return "in open space a pipe reaches %s m, not the longest %s" % [open[0], look["pipe_max_length_m"]]
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.0, 1.0, false, 90.0)
	view.fit_pipes(walls)
	var pipe: MeshInstance3D = view.machine().pipes()[0]
	var far_end: Vector3 = view.machine().transform * (pipe.transform * Vector3(0.0, 0.5, 0.0))
	var flat: float = Vector2(far_end.x, far_end.z).length()
	var result: String = ""
	if absf(flat - reach[0]) > 0.05:
		result = "the drawn pipe ends %s m out, its reach is %s m" % [flat, reach[0]]
	view.free()
	return result


func test_paused_view_holds_the_flames() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 0.0, true, 30.0)
	view.frozen = true
	var result: String = ""
	if view.machine().flames().speed_scale != 0.0 or view.machine().embers().speed_scale != 0.0:
		result = "the flames keep moving while paused (CMF-8)"
	view.frozen = false
	if result == "" and view.machine().flames().speed_scale != 1.0:
		result = "the flames do not resume"
	view.free()
	return result


func test_same_state_every_frame_does_not_rebuild_the_machine() -> String:
	var view: ReactorView = ReactorView.new()
	var machine: ReactorMachine = view.machine()
	var builds: int = machine.mesh_builds
	for frame: int in 60:
		view.show_state(Vector3(1, 2, 3), 2.5, 0.5, frame > 30, 60.0)
	var result: String = ""
	if view.machine() != machine or machine.mesh_builds != builds:
		result = "the machine was rebuilt"
	view.free()
	return result
