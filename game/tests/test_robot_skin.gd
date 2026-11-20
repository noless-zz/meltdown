extends RefCounted

## Robot skins (#661, GFX-2, CMB-3, ARC-4): each robot type's surface pattern,
## accent colour and face plate come from `robot_look.json`, bad values are
## rejected naming the field, the face plate is on the robot's forward side,
## and #604's flash, damage dim and wind-up glow still reach the patterned body.

const LOOK_FILE: String = "res://view/robot_look.json"
const ROBOTS_DIR: String = "res://data/robots"
const EPSILON: float = 0.001


func _shipped() -> Dictionary:
	return RobotLook.parse(FileAccess.get_file_as_string(LOOK_FILE))


func _def(id: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))


func _robot_ids() -> Array[String]:
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			ids.append(_def(file.get_basename()).id)
	return ids


func _look_with_skin(skin: Variant) -> String:
	var entry: Dictionary = {"shape": "box", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5], "skin": skin}
	return JSON.stringify({"default": {"shape": "box", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]},
		"robots": {"drone": entry}})


func test_the_shipped_look_file_parses_with_skins() -> String:
	var parsed: Dictionary = _shipped()
	if parsed.has("error"):
		return "shipped look rejected: %s" % parsed["error"]
	var skin: Dictionary = parsed["robots"]["drone"]["skin"]
	if skin["pattern"] != "rings" or not (skin["accent_color"] is Color):
		return "the drone's skin was not read: %s" % [skin]
	if parsed["default"]["skin"]["pattern"] != "plain":
		return "an entry without a skin is not plain"
	return ""


func test_every_robot_type_has_its_own_pattern_and_accent() -> String:
	var robots: Dictionary = _shipped()["robots"]
	var ids: Array[String] = _robot_ids()
	if ids.size() < 6:
		return "only %d robot data files found" % ids.size()
	var patterns: Dictionary = {}
	var accents: Dictionary = {}
	for id: String in ids:
		if not robots.has(id):
			return "robot_look.json has no entry for \"%s\"" % id
		var look: Dictionary = robots[id]
		var skin: Dictionary = look["skin"]
		if skin["pattern"] == "plain":
			return "\"%s\" has no pattern" % id
		if patterns.has(skin["pattern"]):
			return "\"%s\" and \"%s\" share the pattern %s" % [patterns[skin["pattern"]], id, skin["pattern"]]
		patterns[skin["pattern"]] = id
		var accent: Color = skin["accent_color"]
		if accents.has(accent):
			return "\"%s\" and \"%s\" share the accent colour" % [accents[accent], id]
		accents[accent] = id
		var base: Color = look["emission_color"]
		if absf(base.get_luminance() - accent.get_luminance()) < 0.15:
			return "\"%s\"'s accent is too close in brightness to its colour to read" % id
	return ""


func test_bad_skins_are_rejected_with_the_field_named() -> String:
	var cases: Array[Array] = [
		["not an object", "robots.drone.skin"],
		[{"accent_color": [0.1, 0.1, 0.1]}, "pattern"],
		[{"pattern": "spots", "accent_color": [0.1, 0.1, 0.1]}, "robots.drone.skin.pattern"],
		[{"pattern": "rings"}, "accent_color"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1]}, "robots.drone.skin.accent_color"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1, 1.5]}, "robots.drone.skin.accent_color"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1, 0.1], "scale": 0.0}, "robots.drone.skin.scale"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1, 0.1], "width": true}, "robots.drone.skin.width"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1, 0.1], "face_depth": -1.0}, "robots.drone.skin.face_depth"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1, 0.1], "face_color": "white"}, "robots.drone.skin.face_color"],
		[{"pattern": "rings", "accent_color": [0.1, 0.1, 0.1], "texture": "a.png"}, "texture"],
	]
	for item: Array in cases:
		var parsed: Dictionary = RobotLook.parse(_look_with_skin(item[0]))
		if not parsed.has("error"):
			return "skin %s was accepted" % [item[0]]
		if not str(parsed["error"]).contains(item[1]):
			return "skin %s rejected as \"%s\", which does not name %s" % [item[0], parsed["error"], item[1]]
	return ""


func test_the_face_plate_is_on_the_forward_axis() -> String:
	var robot: RobotState = RobotState.new(_def("drone"), Vector3.ZERO)
	# The face axis is the robot's forward in its own frame.
	var local_forward: Vector3 = robot.orientation.inverse() * robot.forward()
	if not local_forward.is_equal_approx(RobotSkin.FACE_AXIS):
		return "the face axis %s is not the robot's forward %s" % [RobotSkin.FACE_AXIS, local_forward]
	var robots: Dictionary = _shipped()["robots"]
	for id: String in _robot_ids():
		var look: Dictionary = robots[id]
		var skin: Dictionary = look["skin"]
		var front: Vector3 = RobotSkin.FACE_AXIS * (look["stretch"] as Vector3).z
		if not RobotSkin.is_face(front, skin):
			return "the front of \"%s\"'s body is not on its face plate" % id
		if RobotSkin.is_face(-front, skin) or RobotSkin.is_face(Vector3.ZERO, skin):
			return "the back or centre of \"%s\" is on its face plate" % id
		for part: Dictionary in look["parts"]:
			if part["eye"] and not RobotSkin.is_face(part["offset"], skin):
				return "\"%s\"'s eye at %s is off its face plate" % [id, part["offset"]]
	return ""


func test_the_view_gives_each_type_its_skin_laid_out_in_the_robot_frame() -> String:
	var view: RobotView = RobotView.new()
	var robots: Array[RobotState] = []
	for id: String in ["drone", "warden"]:
		robots.append(RobotState.new(_def(id), Vector3(robots.size() * 6.0, 0.0, 0.0)))
	view.show_robots(robots, robots, 1.0)
	var result: String = ""
	for index: int in robots.size():
		var skin: Dictionary = view.look_for(robots[index].def.id)["skin"]
		var material: ShaderMaterial = view.body_material(index)
		if material.get_shader_parameter("pattern") != RobotSkin.PATTERNS.find(skin["pattern"]):
			result = "robot %d draws pattern %s, not its %s" % [index, material.get_shader_parameter("pattern"), skin["pattern"]]
		elif material.get_shader_parameter("accent_color") != skin["accent_color"]:
			result = "robot %d has the wrong accent colour" % index
	var look: Dictionary = view.look_for("drone")
	var parts: Array[Node] = view.node(0).get_children()
	var body: MeshInstance3D = parts[0]
	var torus: MeshInstance3D = parts[1]
	if result == "" and body.get_instance_shader_parameter("part_size") != look["stretch"]:
		result = "the body is not laid out at its stretch"
	if result == "" and torus.get_instance_shader_parameter("part_offset") != look["parts"][0]["offset"]:
		result = "a part is not laid out at its offset"
	view.free()
	return result


func test_flash_dim_and_glow_show_over_the_pattern() -> String:
	var material: ShaderMaterial = RobotSkin.make_material()
	var base: Color = Color(1.0, 0.2, 0.15)
	RobotSkin.paint(material, base, 1.0, 0.0, Color.WHITE, 1.0)
	var calm: Color = RobotSkin.shown_color(material)
	RobotSkin.paint(material, base, 1.0, 1.0, Color.WHITE, 4.0)
	if not RobotSkin.shown_color(material).is_equal_approx(Color.WHITE) or RobotSkin.energy(material) != 4.0:
		return "a full flash does not cover the body in the flash colour"
	RobotSkin.paint(material, base, 0.45, 0.0, Color.WHITE, 1.0)
	if absf(RobotSkin.shown_color(material).get_luminance() - calm.get_luminance() * 0.45) > EPSILON:
		return "the damage dim does not scale the body"
	# The shader mixes the flash in after the pattern and face plate, and
	# dims and glows them with the body.
	var code: String = RobotSkin.SHADER.code
	var pattern_at: int = code.find("mix(base_color, accent_color")
	var face_at: int = code.find("face_color, smoothstep")
	var flash_at: int = code.find("surface * brightness, flash_color, flash")
	if pattern_at < 0 or face_at < pattern_at or flash_at < face_at or not code.contains("ALBEDO * energy"):
		return "the shader does not apply the flash, dim and glow after the pattern"
	return ""
