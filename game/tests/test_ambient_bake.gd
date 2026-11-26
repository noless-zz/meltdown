extends RefCounted

## Baked ambient light per box (#1400, GFX-5, GFX-4, PRF-4, ARC-1): each box's
## colour comes from its size and the reactor, two boxes blend across their
## opening with no seam, the same level bakes the same every time, and the bake
## adds no light and no draw call.

const AmbientBakeCheck := preload("res://acceptance/checks/ambient_bake_check.gd")

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SHADER_NEEDLES: Array[String] = ["ambient_light_disabled", "CUSTOM0", "baked_ambient", "ambient_light"]
const STEP_IDS: Array[String] = ["wall_depth", "portal_visibility"]


func _rules() -> Dictionary:
	return AmbientRules.parse(LevelLook.load_file()[AmbientRules.KEY])


## A narrow tunnel opening into a room at z = -18..-20.
func _tunnel_and_room() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-3, -3, -20), Vector3(3, 3, 0)),
		BoxBounds.new(Vector3(-10, -6, -40), Vector3(10, 6, -18))]
	return BoxUnion.new(boxes)


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _reactor(level: LevelDef) -> Vector3:
	return Vector3(level.reactor.position_mm) / float(RobotSpawn.SCALE)


func test_tunnels_are_cool_and_dim_rooms_warmer() -> String:
	var bake: AmbientBake = AmbientBake.make(_tunnel_and_room(), _rules(), null)
	var tunnel: Color = bake.ambients[0]
	var room: Color = bake.ambients[1]
	if tunnel.b <= tunnel.r:
		return "the tunnel's ambient %s is not cool" % tunnel
	if room.r <= room.b:
		return "the room's ambient %s is not warm" % room
	if tunnel.get_luminance() >= room.get_luminance():
		return "the tunnel (%s) is not dimmer than the room (%s)" % [tunnel, room]
	return ""


func test_the_reactor_casts_red_on_the_boxes_near_it() -> String:
	var level: LevelDef = _g2()
	var reactor: Vector3 = _reactor(level)
	var bake: AmbientBake = AmbientBake.make(level.union, _rules(), reactor)
	var plain: AmbientBake = AmbientBake.make(level.union, _rules(), null)
	var hot: int = -1
	var far: int = -1
	for index: int in level.union.boxes.size():
		var away: float = AmbientBake.distance(reactor, level.union.boxes[index])
		if away == 0.0:
			hot = index
		elif away > 60.0:
			far = index
	if hot < 0 or far < 0:
		return "G2 has no box at the reactor (%d) or far from it (%d)" % [hot, far]
	var cast: Color = bake.ambients[hot]
	if cast.r <= cast.g * 2.0 or cast.r <= plain.ambients[hot].r:
		return "the reactor's box bakes %s, not a red cast over %s" % [cast, plain.ambients[hot]]
	if not bake.ambients[far].is_equal_approx(plain.ambients[far]):
		return "a box %d far from the reactor took its cast" % far
	return ""


func test_the_two_boxes_blend_across_their_opening() -> String:
	var union: BoxUnion = _tunnel_and_room()
	var bake: AmbientBake = AmbientBake.make(union, _rules(), null)
	# A corner of the opening lies on both boxes' walls.
	var rim: Vector3 = Vector3(3, 3, -18)
	var from_tunnel: Color = bake.at(rim, 0)
	var from_room: Color = bake.at(rim, 1)
	if not from_tunnel.is_equal_approx(from_room):
		return "the opening's corner is %s from the tunnel and %s from the room" % [from_tunnel, from_room]
	var mid: Color = (bake.ambients[0] + bake.ambients[1]) * 0.5
	if not from_tunnel.is_equal_approx(mid):
		return "the opening is %s, not halfway between %s and %s" % [from_tunnel, bake.ambients[0], bake.ambients[1]]
	# Far down the tunnel, and across the room, each keeps its own.
	if not bake.at(Vector3(3, 0, -2), 0).is_equal_approx(bake.ambients[0]):
		return "the far end of the tunnel is blended"
	if not bake.at(Vector3(10, 0, -38), 1).is_equal_approx(bake.ambients[1]):
		return "the far wall of the room is blended"
	return ""


func test_no_seam_where_two_boxes_meet() -> String:
	var view: LevelView = LevelView.new()
	view.build(_tunnel_and_room())
	var seen: Dictionary = {}
	var shared: int = 0
	var result: String = ""
	for box: int in view.box_count():
		for part: MeshInstance3D in [view.walls_of(box), view.bevels_of(box)]:
			if part == null or part.mesh == null:
				continue
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var light: PackedFloat32Array = LevelViewMeshes.baked(part.mesh)
			if light.size() != vertices.size() * 3:
				result = "box %d %s carries %d floats for %d vertices" % [box, part.name, light.size(), vertices.size()]
			for index: int in vertices.size() if result == "" else 0:
				var key: Vector3i = Vector3i((vertices[index] * 1000.0).round())
				var here: Color = Color(light[index * 3], light[index * 3 + 1], light[index * 3 + 2])
				if seen.has(key) and int(seen[key][0]) != box:
					shared += 1
					if not (seen[key][1] as Color).is_equal_approx(here):
						result = "at %s box %d bakes %s, box %d %s" % [vertices[index], seen[key][0], seen[key][1], box, here]
				elif not seen.has(key):
					seen[key] = [box, here]
	view.free()
	if result == "" and shared == 0:
		result = "the two boxes share no vertex, so the seam went untested"
	return result


func test_walls_near_an_opening_are_cut_so_the_blend_shows() -> String:
	var union: BoxUnion = _tunnel_and_room()
	var bake: AmbientBake = AmbientBake.make(union, _rules(), null)
	var result: String = ""
	var cut: int = 0
	for quad: Dictionary in LevelFaces.quads(union):
		var pieces: Array[Dictionary] = bake.pieces(quad)
		var area: float = 0.0
		for piece: Dictionary in pieces:
			area += LevelFaces.area(piece)
			var size: Vector3 = (piece["max"] as Vector3) - (piece["min"] as Vector3)
			if pieces.size() > 1 and maxf(size.x, maxf(size.y, size.z)) > bake.piece_m + 1e-3 \
					and AmbientBake._rect_distance(piece["min"], piece["max"], union.boxes[1 - int(quad["box"])]) < bake.blend_m:
				result = "a piece %s by the opening is larger than %s m" % [size, bake.piece_m]
		if absf(area - LevelFaces.area(quad)) > 1e-3:
			result = "the pieces of a quad cover %s m², not %s" % [area, LevelFaces.area(quad)]
		if pieces.size() > 1:
			cut += 1
	# The room's far wall is 20 m from the tunnel: nothing to blend, left whole.
	var far: Dictionary = LevelFaces.make_quad(1, 2, Vector3(0, 0, 1), Vector3(-10, -6, -40), Vector3(10, 6, -40))
	if result == "" and bake.pieces(far).size() != 1:
		result = "the room's far wall was cut into %d pieces" % bake.pieces(far).size()
	if result == "" and cut == 0:
		result = "no wall by the opening was cut"
	return result


func test_the_same_level_bakes_the_same_every_time() -> String:
	var level: LevelDef = _g2()
	var first: LevelView = LevelView.new()
	var second: LevelView = LevelView.new()
	first.build(level.union, _reactor(level))
	second.build(_g2().union, _reactor(level))
	var result: String = ""
	for box: int in first.box_count():
		for part: String in ["walls", "bevels"]:
			var a: MeshInstance3D = first.walls_of(box) if part == "walls" else first.bevels_of(box)
			var b: MeshInstance3D = second.walls_of(box) if part == "walls" else second.bevels_of(box)
			if (a == null) != (b == null):
				result = "box %d's %s exist in one build only" % [box, part]
			elif a != null and LevelViewMeshes.baked(a.mesh) != LevelViewMeshes.baked(b.mesh):
				result = "box %d's %s bake differently" % [box, part]
	first.free()
	second.free()
	return result


func test_the_bake_adds_no_light_and_no_draw_call() -> String:
	var level: LevelDef = _g2()
	var view: LevelView = LevelView.new()
	view.build(level.union, _reactor(level))
	var measurements: Dictionary = {}
	var verdict: Array = AmbientBakeCheck.judge_view(view, measurements)
	var result: String = ""
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		result = "G2 fails the check: %s" % [verdict]
	elif int(measurements["ambient_tints"]) < 2:
		result = "G2 bakes %s tints" % measurements["ambient_tints"]
	for box: int in view.box_count():
		if result == "" and view.surfaces_of(box) > 2:
			result = "box %d costs %d draw calls" % [box, view.surfaces_of(box)]
	view.free()
	if result != "":
		return result
	var code: String = FileAccess.get_file_as_string(LevelLook.WALL_SHADER)
	for needle: String in SHADER_NEEDLES:
		if not code.contains(needle):
			return "the wall shader does not use %s" % needle
	return ""


func test_one_tint_fails_the_check() -> String:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	var view: LevelView = LevelView.new()
	view.build(BoxUnion.new(boxes))
	var verdict: Array = AmbientBakeCheck.judge_view(view, {})
	view.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not String(verdict[1]).contains("same ambient"):
		return "one box gave %s" % [verdict]
	if AmbientBakeCheck.judge_view(null, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "no level view passed"
	return ""


func test_the_g2_steps_check_the_bake() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return "the m6 suite did not load"
	for id: String in STEP_IDS:
		var step: AcceptanceStep = null
		for candidate: AcceptanceStep in found[0].steps:
			if candidate.id == id:
				step = candidate
		if step == null:
			return "m6 has no %s step" % id
		if not step.checks.has(AmbientBakeCheck.CHECK):
			return "the %s step does not check %s" % [id, AmbientBakeCheck.CHECK]
	if not AcceptanceCheckFiles.judges().has(AmbientBakeCheck.CHECK):
		return "the check files do not judge %s" % AmbientBakeCheck.CHECK
	return ""


func test_without_a_bake_the_walls_draw_the_global_ambient() -> String:
	var look: Dictionary = LevelLook.FALLBACK
	var material: ShaderMaterial = LevelLook.wall_material(look, look["wall_color"])
	var global: Color = AmbientBake.global(look)
	var expected: Color = Color(look["ambient_color"]).srgb_to_linear() * float(look["ambient_energy"])
	if not Vector3(global.r, global.g, global.b).is_equal_approx(Vector3(expected.r, expected.g, expected.b)):
		return "the global ambient is %s, expected %s" % [global, expected]
	if not (material.get_shader_parameter("ambient_light") as Vector3).is_equal_approx(Vector3(global.r, global.g, global.b)):
		return "a wall material's ambient is %s" % material.get_shader_parameter("ambient_light")
	if material.get_shader_parameter("baked_ambient") == true:
		return "a plain wall material reads a bake"
	return ""


## sRGB 0..255 of a wall in `tint` lit by `ambient` alone, as the shader adds it.
func _ambient_only(tint: Color, ambient: Color) -> Color:
	var albedo: Color = tint.srgb_to_linear()
	return Color(albedo.r * ambient.r, albedo.g * ambient.g, albedo.b * ambient.b).linear_to_srgb() * 255.0


func test_rooms_differ_visibly_and_stay_dark() -> String:
	# The shipped walls' albedo is dark: an ambient that changes them by less
	# than a step or two of 255 changes no mood (#1400); much more and the mine
	# is no longer dark until lit (LGT-1).
	var look: Dictionary = LevelLook.load_file()
	var level: LevelDef = _g2()
	var bake: AmbientBake = AmbientBake.make(level.union, _rules(), _reactor(level))
	var tint: Color = look["wall_color"]
	var tunnel: Color = _ambient_only(tint, AmbientBake.make(_tunnel_and_room(), _rules(), null).ambients[0])
	var room: Color = _ambient_only(tint, AmbientBake.make(_tunnel_and_room(), _rules(), null).ambients[1])
	var step: float = maxf(absf(tunnel.r - room.r), maxf(absf(tunnel.g - room.g), absf(tunnel.b - room.b)))
	if step < 3.0:
		return "a tunnel (%s) and a room (%s) differ by %.1f of 255 on a wall" % [tunnel, room, step]
	for index: int in bake.ambients.size():
		for kind: String in ["wall_color", "floor_color", "ceiling_color"]:
			var lit: Color = _ambient_only(look[kind], bake.ambients[index])
			if maxf(lit.r, maxf(lit.g, lit.b)) > 60.0:
				return "box %d's %s reads %s of 255 under ambient alone (LGT-1)" % [index, kind, lit]
		var grey: Color = _ambient_only(tint, bake.ambients[index])
		if bake.ambients[index].r < bake.ambients[index].g * 2.0 and grey.get_luminance() > 25.0:
			return "box %d away from the reactor reads %s of 255 under ambient alone" % [index, grey]
	return ""
