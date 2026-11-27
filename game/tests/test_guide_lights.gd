extends RefCounted

## Guide light strips along the mine's walls and corners (#1463, GFX-2, GFX-4,
## GFX-5, PRF-2, ARC-1, ARC-2, ARC-4): the look's `guide_lights` section is
## checked key by key, strips sit on the walls and ring every opening with none
## inside it, the same level always gets the same strips, each box kind has its
## colour, and the strips are drawn in the bevels' surface with no new light
## and no new draw call.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const GuideLightsCheck := preload("res://acceptance/checks/guide_lights_check.gd")
const SUITE_FILE: String = "res://acceptance/suites/m6/look.json"
const SHADER_FILE: String = "res://view/level_wall.gdshader"
const SEED: int = 4321


func _shipped() -> Dictionary:
	return LevelLook.load_file()[GuideLightRules.KEY]


func _rules() -> Dictionary:
	return GuideLightRules.parse(_shipped())


## A narrow tunnel along -z opening into a room at z = -18..-20.
func _tunnel_and_room() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-3, -3, -20), Vector3(3, 3, 0)),
		BoxBounds.new(Vector3(-10, -6, -40), Vector3(10, 6, -18))]
	return BoxUnion.new(boxes)


func _rejects(change: Dictionary, field: String) -> String:
	var data: Dictionary = _shipped().duplicate(true)
	for key: String in change:
		if change[key] == null:
			data.erase(key)
		else:
			data[key] = change[key]
	var parsed: Dictionary = GuideLightRules.parse(JSON.parse_string(JSON.stringify(data)))
	if not parsed.has("error"):
		return "%s was accepted" % JSON.stringify(change)
	return "" if (parsed["error"] as String).contains(field) else "error \"%s\" does not name %s" % [parsed["error"], field]


func _inside_another(union: BoxUnion, own: int, point: Vector3) -> bool:
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		if index != own and point.x > box.min_corner.x and point.x < box.max_corner.x \
				and point.y > box.min_corner.y and point.y < box.max_corner.y \
				and point.z > box.min_corner.z and point.z < box.max_corner.z:
			return true
	return false


func test_the_shipped_section_parses() -> String:
	var rules: Dictionary = _rules()
	if rules.has("error"):
		return "level_look.json: %s" % rules["error"]
	for kind: String in GuideLightRules.KINDS:
		if not (rules[GuideLightRules.COLORS_KEY] as Dictionary).has(kind):
			return "no colour for %s" % kind
	return ""


func test_each_bad_key_names_its_field() -> String:
	var cases: Array[Array] = [
		[{"glare": 1}, "glare"],
		[{"spacing_m": null}, "spacing_m"],
		[{"width_m": 2.0}, "width_m"],
		[{"energy": true}, "energy"],
		[{"energy": -1}, "energy"],
		[{"length_m": 9.0, "spacing_m": 4.0}, "length_m"],
		[{"junction_openings": 3.5}, "junction_openings"],
		[{"colors": {"tunnel": [1, 1, 1], "room": [1, 1, 1], "junction": [1, 1, 1]}}, "colors.reactor"],
		[{"colors": {"tunnel": [1, 1], "room": [1, 1, 1], "junction": [1, 1, 1], "reactor": [1, 1, 1]}}, "colors.tunnel"],
		[{"colors": {"tunnel": [1, 1, 1], "room": [1, 2, 1], "junction": [1, 1, 1], "reactor": [1, 1, 1]}}, "colors.room"],
		[{"colors": {"tunnel": [1, 1, 1], "room": [1, 1, 1], "junction": [1, 1, 1], "reactor": [1, 1, 1], "hub": [1, 1, 1]}}, "hub"],
	]
	for case: Array in cases:
		var problem: String = _rejects(case[0], case[1])
		if problem != "":
			return problem
	if not GuideLightRules.parse([]).has("error"):
		return "a list was accepted as the section"
	return ""


func test_a_bad_section_draws_nothing_and_says_why() -> String:
	var look: Dictionary = LevelLook.load_file().duplicate()
	look[GuideLightRules.KEY] = {"spacing_m": 4.0}
	var lights: GuideLights = GuideLights.for_look(_tunnel_and_room(), look, null)
	if lights.error == "" or not lights.strips.is_empty():
		return "a bad section drew %d strips with error \"%s\"" % [lights.strips.size(), lights.error]
	look.erase(GuideLightRules.KEY)
	lights = GuideLights.for_look(_tunnel_and_room(), look, null)
	if lights.error != "" or lights.enabled or not lights.strips.is_empty():
		return "a look without the section drew %d strips" % lights.strips.size()
	if lights.color_of(0) != Color.BLACK or lights.energy() != 0.0:
		return "a look without the section still glows"
	return ""


func test_the_look_file_keeps_the_section() -> String:
	var look: Dictionary = LevelLook.load_file()
	if look.has("error") or not look.has(GuideLightRules.KEY):
		return "the look file lost its guide_lights section: %s" % look.get("error", "")
	return ""


func test_box_kinds_tunnel_room_junction_reactor() -> String:
	var rules: Dictionary = _rules()
	var kinds: Array[String] = GuideLightPlacement.kinds(_tunnel_and_room(), rules, null)
	if kinds != [GuideLightRules.KIND_TUNNEL, GuideLightRules.KIND_ROOM]:
		return "tunnel and room are %s" % [kinds]
	kinds = GuideLightPlacement.kinds(_tunnel_and_room(), rules, Vector3(0, 0, -30))
	if kinds[1] != GuideLightRules.KIND_REACTOR:
		return "the room holding the reactor is a %s" % kinds[1]
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-4, -4, -4), Vector3(4, 4, 4)),
		BoxBounds.new(Vector3(3, -2, -2), Vector3(20, 2, 2)), BoxBounds.new(Vector3(-20, -2, -2), Vector3(-3, 2, 2)),
		BoxBounds.new(Vector3(-2, -2, 3), Vector3(2, 2, 20))]
	kinds = GuideLightPlacement.kinds(BoxUnion.new(boxes), rules, null)
	if kinds[0] != GuideLightRules.KIND_JUNCTION or kinds[1] != GuideLightRules.KIND_TUNNEL:
		return "a box opening three ways is a %s, its arm a %s" % [kinds[0], kinds[1]]
	return ""


func test_strips_lie_on_the_walls_and_never_in_an_opening() -> String:
	var union: BoxUnion = _tunnel_and_room()
	var rules: Dictionary = _rules()
	var strips: Array[Dictionary] = GuideLightPlacement.strips(union, rules, GuideLightPlacement.kinds(union, rules, null))
	if strips.is_empty():
		return "no strips"
	var inset: float = float(rules["inset_m"])
	for strip: Dictionary in strips:
		var box: BoxBounds = union.boxes[int(strip["box"])]
		var axis: int = strip["axis"]
		var low: Vector3 = strip["min"]
		var high: Vector3 = strip["max"]
		var plane: float = box.min_corner[axis] if float((strip["normal"] as Vector3)[axis]) > 0.0 else box.max_corner[axis]
		if absf(low[axis] - plane) > 1e-4 or absf(high[axis] - plane) > 1e-4:
			return "a strip of box %d at %s is off its wall" % [strip["box"], low]
		for other: int in [(axis + 1) % 3, (axis + 2) % 3]:
			if low[other] < box.min_corner[other] + inset - 1e-4 or high[other] > box.max_corner[other] - inset + 1e-4:
				return "a strip of box %d at %s..%s reaches into the bevels" % [strip["box"], low, high]
		for share: Vector3 in [Vector3(0.01, 0.01, 0.01), Vector3(0.5, 0.5, 0.5), Vector3(0.99, 0.99, 0.99)]:
			var point: Vector3 = low + (high - low) * share
			if _inside_another(union, int(strip["box"]), point):
				return "a strip of box %d at %s lies in an opening" % [strip["box"], point]
	return ""


func test_the_opening_is_framed_on_the_room_side() -> String:
	var union: BoxUnion = _tunnel_and_room()
	var rules: Dictionary = _rules()
	var strips: Array[Dictionary] = GuideLightPlacement.strips(union, rules, GuideLightPlacement.kinds(union, rules, null))
	var reach: float = float(rules["margin_m"]) + float(rules["width_m"])
	var frames: int = 0
	var mouth: int = 0
	for strip: Dictionary in strips:
		if strip["part"] != GuideLightPlacement.PART_FRAME:
			continue
		var low: Vector3 = strip["min"]
		var high: Vector3 = strip["max"]
		if int(strip["box"]) == 0:
			# The tunnel's own walls end in the room: a strip marks the mouth.
			mouth += 1
			if low.z < -18.0 or high.z > -18.0 + reach + 1e-4:
				return "a tunnel frame strip at %s..%s is not at its mouth" % [low, high]
			continue
		frames += 1
		# The room's wall at z = -18, around the tunnel's 6 m square mouth.
		if not is_equal_approx(low.z, -18.0) or low.x < -3.0 - reach - 1e-4 \
				or high.x > 3.0 + reach + 1e-4 or low.y < -3.0 - reach - 1e-4 or high.y > 3.0 + reach + 1e-4:
			return "a frame strip of box %d at %s..%s does not ring the opening" % [strip["box"], low, high]
	if mouth != 4:
		return "the tunnel's mouth is marked on %d walls, not 4" % mouth
	return "" if frames == 4 else "the opening has %d frame strips, not 4" % frames


func test_tunnels_run_lengthwise_and_rooms_are_outlined() -> String:
	var union: BoxUnion = _tunnel_and_room()
	var rules: Dictionary = _rules()
	var strips: Array[Dictionary] = GuideLightPlacement.strips(union, rules, GuideLightPlacement.kinds(union, rules, null))
	var room_across: int = 0
	for strip: Dictionary in strips:
		if strip["part"] != GuideLightPlacement.PART_CORNER:
			continue
		var size: Vector3 = (strip["max"] as Vector3) - (strip["min"] as Vector3)
		var along_z: bool = size.z >= size.x and size.z >= size.y
		if int(strip["box"]) == 0 and not along_z:
			return "a tunnel strip runs across it: %s" % size
		if int(strip["box"]) == 1 and not along_z:
			room_across += 1
	return "" if room_across > 0 else "the room's walls are not outlined across"


func test_the_same_level_gets_the_same_strips() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var first: MineGenerator = MineGenerator.generate(SEED, modules, SeedSweep.MODULE_COUNT)
	var second: MineGenerator = MineGenerator.generate(SEED, modules, SeedSweep.MODULE_COUNT)
	var look: Dictionary = LevelLook.load_file()
	var a: GuideLights = GuideLights.for_look(first.union, look, null)
	var b: GuideLights = GuideLights.for_look(second.union, look, null)
	if a.strips.is_empty():
		return "seed %d has no strips" % SEED
	if a.strips != b.strips or a.kinds != b.kinds:
		return "seed %d placed %d and %d strips" % [SEED, a.strips.size(), b.strips.size()]
	if first.output_hash() != second.output_hash():
		return "the level itself changed between runs"
	return ""


func test_the_view_draws_strips_in_the_bevels_surface() -> String:
	var view: LevelView = LevelView.new()
	view.build(_tunnel_and_room())
	var lights: GuideLights = view.guide_lights
	var result: String = ""
	for box: int in view.box_count():
		var node: MeshInstance3D = view.bevels_of(box)
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var glowing: int = 0
		for color: Color in arrays[Mesh.ARRAY_COLOR] as PackedColorArray:
			if color != Color.BLACK:
				glowing += 1
		var strips: int = lights.strips_of(box).size()
		if view.surfaces_of(box) > 2:
			result = "box %d costs %d draw calls" % [box, view.surfaces_of(box)]
		elif strips == 0 or glowing != strips * 6 or vertices < glowing:
			result = "box %d draws %d glowing vertices for %d strips" % [box, glowing, strips]
		if result != "":
			break
	var material: ShaderMaterial = view.bevels_of(0).mesh.surface_get_material(0)
	if result == "" and not is_equal_approx(float(material.get_shader_parameter(GuideLights.ENERGY_PARAMETER)),
			float(lights.rules["energy"])):
		result = "the bevels glow the strips at %s" % material.get_shader_parameter(GuideLights.ENERGY_PARAMETER)
	lights.set_on(false)
	if result == "" and float(material.get_shader_parameter(GuideLights.ENERGY_PARAMETER)) != 0.0:
		result = "switching the strips off left them glowing"
	var walls: ShaderMaterial = view.walls_of(0).mesh.surface_get_material(0)
	if result == "" and walls.get_shader_parameter(GuideLights.ENERGY_PARAMETER) != null \
			and float(walls.get_shader_parameter(GuideLights.ENERGY_PARAMETER)) != 0.0:
		result = "the walls glow as strips"
	view.free()
	return result


func test_the_wall_shader_adds_the_strip_glow() -> String:
	var source: String = FileAccess.get_file_as_string(SHADER_FILE)
	for needle: String in ["uniform float strip_energy", "COLOR.rgb * strip_energy", "strip_glow"]:
		if not source.contains(needle):
			return "the wall shader lacks %s" % needle
	return ""


func test_the_check_passes_a_lit_level_and_fails_an_unlit_one() -> String:
	var view: LevelView = LevelView.new()
	view.build(_tunnel_and_room())
	var measurements: Dictionary = {}
	var verdict: Array = GuideLightsCheck.judge_view(view, measurements)
	var result: String = ""
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		result = "a lit level failed: %s" % verdict[1]
	elif int(measurements["guide_draw_calls"]) != 0 or int(measurements["guide_triangles"]) != view.guide_lights.strips.size() * 2:
		result = "the cost is reported as %s" % measurements
	view.guide_lights = GuideLights.new()
	if result == "" and GuideLightsCheck.judge_view(view, {})[0] != AcceptanceReport.RESULT_FAIL:
		result = "a level without strips passed"
	view.free()
	return result


func test_mean_luminance_of_a_flat_image() -> String:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 0.5))
	var dark: float = GuideLightsCheck.mean_luminance(image)
	image.fill_rect(Rect2i(0, 0, 8, 1), Color(1, 1, 1))
	var lit: float = GuideLightsCheck.mean_luminance(image)
	if absf(dark - 0.5) > 0.01 or lit <= dark:
		return "a grey image reads %.3f and with a white line %.3f" % [dark, lit]
	return ""


func test_the_m6_look_suite_flies_the_guide_lights_step() -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUITE_FILE))
	for step: Variant in (data as Dictionary)["steps"]:
		if (step as Dictionary)["id"] == "guide_lights":
			var checks: Array = step["checks"]
			if not checks.has(GuideLightsCheck.CHECK_DRAWN) or not checks.has(GuideLightsCheck.CHECK_BRIGHTER):
				return "the guide_lights step lists %s" % [checks]
			return "" if str(step["replay"]).ends_with("stress_scene.replay") else "the step flies %s" % step["replay"]
	return "suites/m6/look.json has no guide_lights step"
