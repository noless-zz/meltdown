extends RefCounted

## Robot bodies (#1307, GFX-2, CMB-3, LGT-1, LGT-2, GFX-4, ARC-4): every type
## ships a lit metal finish and two to four more parts, among them thrusters
## that glow with its speed; each `finish` and `thrust` key changes what is
## drawn, a missing key keeps today's look, bad values are rejected naming the
## field, and the view adds no light and never writes to the robots (MP-2).

const LOOK_FILE: String = "res://view/robot_look.json"
const ROBOTS_DIR: String = "res://data/robots"
## Parts beyond the body each type had before #1307.
const PARTS_BEFORE: Dictionary[String, int] = {
	"drone": 3, "glider": 5, "hauler": 4, "needler": 4, "skimmer": 3, "warden": 5,
}
## A value for each finish key unlike its `NO_FINISH` value, with the uniform it drives.
const FINISH_CHANGES: Dictionary[String, Array] = {
	"albedo": [[0.9, 0.1, 0.1], "metal_albedo"],
	"roughness": [0.9, "metal_roughness"],
	"metallic": [0.1, "metal_metallic"],
	"panel_scale": [6.0, "panel_scale"],
	"panel_depth": [0.9, "panel_depth"],
	"wear": [0.8, "wear"],
}
const EPSILON: float = 0.0001


func _shipped() -> Dictionary:
	return RobotLook.parse(FileAccess.get_file_as_string(LOOK_FILE))


func _def(id: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))


func _parse_entry(extra: Dictionary) -> Dictionary:
	var entry: Dictionary = {"shape": "box", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]}
	entry.merge(extra, true)
	return RobotLook.parse(JSON.stringify({"default": {"shape": "box", "scale": 1.0,
		"emission_color": [0.5, 0.5, 0.5]}, "robots": {"drone": entry}}))


func _thrusters(look: Dictionary) -> int:
	var count: int = 0
	for part: Dictionary in look["parts"]:
		if part["thruster"]:
			count += 1
	return count


func test_every_type_ships_a_metal_body_and_more_parts() -> String:
	var parsed: Dictionary = _shipped()
	if parsed.has("error"):
		return "shipped look rejected: %s" % parsed["error"]
	if parsed["default"]["finish"]["lit"]:
		return "the default look changed; an unknown type should keep today's glowing body"
	for id: String in PARTS_BEFORE:
		var look: Dictionary = parsed["robots"][id]
		var finish: Dictionary = look["finish"]
		if not finish["lit"]:
			return "\"%s\" has no finish, so its body still glows whole" % id
		if float(finish["metallic"]) < 0.5:
			return "\"%s\" does not read as metal (metallic %.2f)" % [id, finish["metallic"]]
		var added: int = (look["parts"] as Array).size() - PARTS_BEFORE[id]
		if added < 2 or added > 4:
			return "\"%s\" gained %d parts, not two to four" % [id, added]
		if _thrusters(look) == 0:
			return "\"%s\" has no thruster" % id
	return ""


func test_the_view_lights_the_body_and_gives_thrusters_their_own_glow() -> String:
	var view: RobotView = RobotView.new()
	var robots: Array[RobotState] = [RobotState.new(_def("glider"), Vector3.ZERO)]
	view.show_robots(robots, robots, 1.0)
	var look: Dictionary = view.look_for("glider")
	var result: String = ""
	var body: ShaderMaterial = view.body_material(0)
	if float(body.get_shader_parameter("lit_body")) != 1.0:
		result = "the glider's body is not drawn lit"
	elif body.get_shader_parameter("metal_albedo") != look["finish"]["albedo"]:
		result = "the glider's body does not take its albedo"
	var pieces: Array[Node] = view.node(0).get_children()
	var thrusters: int = 0
	for index: int in range(1, pieces.size()):
		var part: Dictionary = look["parts"][index - 1]
		var material: Material = (pieces[index] as MeshInstance3D).material_override
		if part["thruster"]:
			thrusters += 1
			if material != view.thruster_material(0):
				result = "thruster part %d does not wear the thruster material" % (index - 1)
		elif material == view.thruster_material(0):
			result = "part %d glows as a thruster" % (index - 1)
	if result == "" and thrusters != _thrusters(look):
		result = "%d thruster parts drawn, %d listed" % [thrusters, _thrusters(look)]
	if result == "" and not view.find_children("*", "Light3D", true, false).is_empty():
		result = "the robot view adds a dynamic light (GFX-4)"
	view.free()
	return result


func test_thrusters_glow_with_speed_and_the_view_writes_nothing() -> String:
	var view: RobotView = RobotView.new()
	var def: RobotDef = _def("needler")
	var still: RobotState = RobotState.new(def, Vector3.ZERO)
	var fast: RobotState = RobotState.new(def, Vector3(10.0, 0.0, 0.0))
	fast.velocity = Vector3(0.0, 0.0, -def.max_speed)
	var robots: Array[RobotState] = [still, fast]
	var hash_before: int = still.state_hash() ^ fast.state_hash()
	view.show_robots(robots, robots, 1.0)
	var thrust: Dictionary = view.look_for("needler")["thrust"]
	var idle: float = view.thruster_material(0).emission_energy_multiplier
	var full: float = view.thruster_material(1).emission_energy_multiplier
	var result: String = ""
	if absf(idle - float(thrust["energy"]) * float(thrust["idle"])) > EPSILON:
		result = "a still needler's thrusters glow %.3f, not idle" % idle
	elif full <= idle * 2.0:
		result = "a needler at full speed glows %.3f, hardly over idle %.3f" % [full, idle]
	elif still.state_hash() ^ fast.state_hash() != hash_before or fast.velocity.z != -def.max_speed:
		result = "drawing the thrusters changed the robots"
	elif view.thruster_material(1).emission != view.look_for("needler")["emission_color"]:
		result = "the thrusters do not glow in the type's colour"
	view.free()
	return result


func test_thrust_energy_follows_each_key() -> String:
	var base: Dictionary = RobotFinish.NO_THRUST
	var at: float = 3.0
	var reference: float = RobotFinish.thrust_energy(base, at)
	for key: String in ["idle", "full_mps", "energy"]:
		var changed: Dictionary = base.duplicate()
		changed[key] = float(base[key]) * 2.0
		if absf(RobotFinish.thrust_energy(changed, at) - reference) < EPSILON:
			return "changing thrust.%s does not change the glow" % key
	if RobotFinish.thrust_energy(base, 1000.0) != float(base["energy"]):
		return "the glow does not stop at full speed"
	return ""


func test_each_finish_key_changes_the_drawn_body() -> String:
	var reference: ShaderMaterial = RobotSkin.make_material()
	var plain: Dictionary = _parse_entry({"finish": {}})
	if plain.has("error"):
		return "an empty finish was rejected: %s" % plain["error"]
	RobotFinish.apply(reference, plain["robots"]["drone"]["finish"])
	for key: String in FINISH_CHANGES:
		var parsed: Dictionary = _parse_entry({"finish": {key: FINISH_CHANGES[key][0]}})
		if parsed.has("error"):
			return "finish.%s rejected: %s" % [key, parsed["error"]]
		var material: ShaderMaterial = RobotSkin.make_material()
		RobotFinish.apply(material, parsed["robots"]["drone"]["finish"])
		var uniform: String = FINISH_CHANGES[key][1]
		if material.get_shader_parameter(uniform) == reference.get_shader_parameter(uniform):
			return "finish.%s does not change %s" % [key, uniform]
	return ""


func test_missing_keys_keep_todays_look() -> String:
	var bare: Dictionary = _parse_entry({})
	if bare.has("error"):
		return "an entry with no finish was rejected: %s" % bare["error"]
	var look: Dictionary = bare["robots"]["drone"]
	if look["finish"]["lit"] or look["thrust"] != RobotFinish.NO_THRUST:
		return "an entry with no finish or thrust does not keep today's look"
	var material: ShaderMaterial = RobotSkin.make_material()
	RobotFinish.apply(material, look["finish"])
	if float(material.get_shader_parameter("lit_body")) != 0.0:
		return "an entry with no finish draws a lit body"
	var partial: Dictionary = _parse_entry({"finish": {"metallic": 0.3}, "thrust": {"energy": 1.0}})
	var finish: Dictionary = partial["robots"]["drone"]["finish"]
	if float(finish["metallic"]) != 0.3 or float(finish["roughness"]) != float(RobotFinish.NO_FINISH["roughness"]):
		return "a partial finish does not fill its missing keys from NO_FINISH: %s" % finish
	if float(partial["robots"]["drone"]["thrust"]["idle"]) != float(RobotFinish.NO_THRUST["idle"]):
		return "a partial thrust does not fill its missing keys from NO_THRUST"
	return ""


func test_bad_values_are_rejected_with_the_field_named() -> String:
	var part: Dictionary = {"shape": "box", "size": [0.1, 0.1, 0.1], "offset": [0.0, 0.0, 0.5]}
	var cases: Array[Array] = [
		[{"finish": {"metallic": 1.5}}, "robots.drone.finish.metallic"],
		[{"finish": {"albedo": [2.0, 0.0, 0.0]}}, "robots.drone.finish.albedo"],
		[{"finish": {"shine": 1.0}}, "robots.drone.finish"],
		[{"finish": 3}, "robots.drone.finish"],
		[{"thrust": {"full_mps": 0.0}}, "robots.drone.thrust.full_mps"],
		[{"thrust": {"energy": true}}, "robots.drone.thrust.energy"],
		[{"parts": [part.merged({"thruster": 1})]}, "robots.drone.parts.0.thruster"],
		[{"parts": [part.merged({"thruster": true, "eye": true})]}, "robots.drone.parts.0"],
	]
	for case: Array in cases:
		var parsed: Dictionary = _parse_entry(case[0])
		if not parsed.has("error"):
			return "accepted %s" % JSON.stringify(case[0])
		if not String(parsed["error"]).contains(case[1]):
			return "error \"%s\" does not name \"%s\"" % [parsed["error"], case[1]]
	return ""


func test_the_lit_body_glows_only_on_its_lines() -> String:
	var code: String = RobotSkin.SHADER.code
	if not code.contains("uniform float lit_body"):
		return "the shader has no lit body"
	if not code.contains("emission = mix(base_color * lines"):
		return "the lit body's glow is not limited to its accent lines"
	if not code.contains("METALLIC = metallic") or not code.contains("ROUGHNESS = roughness"):
		return "the lit body does not take its metalness and roughness"
	return ""
