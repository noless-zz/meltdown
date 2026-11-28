extends RefCounted

## No full-screen passes (#1522, GFX-6, PRF-2, ARC-4): every shader, material
## and scene file under `view/` and `xr/` is read as text, and the live-tree
## check of `suites/m6/effects.json` is driven with small trees made here.
## A screen read, a depth read or `blend_mul` fails, naming where, unless its
## file is in the allow list, and an allow entry that is no longer needed fails.

const CHECK_SCRIPT: String = "res://acceptance/checks/no_screen_pass_check.gd"
const SCRATCH: String = "user://meltdown_test_no_screen_pass"
const PASS_CODE: String = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { ALBEDO = vec3(1.0); }\n"
const MUL_CODE: String = "shader_type spatial;\nrender_mode blend_mul, unshaded;\nvoid fragment() { ALBEDO = vec3(0.9); }\n"
const SCREEN_CODE: String = "shader_type spatial;\nuniform sampler2D s : hint_screen_texture;\nvoid fragment() { ALBEDO = texture(s, SCREEN_UV).rgb; }\n"
const GLASS: String = "xr/cockpit_glass.gdshader"


static func _check() -> GDScript:
	return load(CHECK_SCRIPT) as GDScript


static func _no_allow() -> Dictionary:
	return {"files": {}, "error": ""}


static func _mesh(node_name: String, code: String) -> MeshInstance3D:
	var shader: Shader = Shader.new()
	shader.code = code
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = BoxMesh.new()
	mesh.material_override = material
	return mesh


static func _step(id: String) -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == id:
			return found
	return null


static func _clear_scratch() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH):
		return
	for file: String in DirAccess.get_files_at(SCRATCH):
		DirAccess.remove_absolute(SCRATCH.path_join(file))
	DirAccess.remove_absolute(SCRATCH)


func test_view_and_xr_files_have_no_screen_pass_outside_the_allow_list() -> String:
	var check: GDScript = _check()
	var scanned: Array[String] = check.files_under(check.SCANNED_ROOTS)
	if scanned.size() < 5 or not scanned.has("res://" + GLASS):
		return "scanned only %s" % [scanned]
	var problems: Array[String] = check.scan_files(check.SCANNED_ROOTS, check.load_allow(check.ALLOW_FILE))
	return "" if problems.is_empty() else "\n".join(problems)


func test_the_allow_list_holds_only_the_cockpit_glass_until_1512() -> String:
	var check: GDScript = _check()
	var allow: Dictionary = check.load_allow(check.ALLOW_FILE)
	if str(allow["error"]) != "":
		return "the allow list was rejected: %s" % allow["error"]
	var files: Dictionary = allow["files"]
	if files.size() != 1 or int(files.get(GLASS, 0)) != 1512:
		return "the allow list holds %s" % files
	return ""


func test_each_pattern_is_found_on_its_line() -> String:
	var check: GDScript = _check()
	var text: String = "shader_type spatial;\nrender_mode blend_mul;\nuniform sampler2D a : hint_screen_texture;\n" \
		+ "uniform sampler2D b : hint_depth_texture;\nvoid fragment() {\n\tvec4 c = texture(SCREEN_TEXTURE, SCREEN_UV);\n" \
		+ "\tfloat d = texture(DEPTH_TEXTURE, SCREEN_UV).r;\n}\n"
	var hits: Array[Dictionary] = check.scan_text(text)
	var expected: Array = [[2, "blend_mul"], [3, "hint_screen_texture"], [4, "hint_depth_texture"],
		[6, "SCREEN_TEXTURE"], [7, "DEPTH_TEXTURE"]]
	var got: Array = []
	for hit: Dictionary in hits:
		got.append([hit["line"], hit["pattern"]])
	return "" if str(got) == str(expected) else "found %s, not %s" % [got, expected]


func test_comments_paths_and_longer_names_are_not_passes() -> String:
	var check: GDScript = _check()
	var text: String = "// render_mode blend_mul;\n/* SCREEN_TEXTURE\n DEPTH_TEXTURE */\n" \
		+ "[ext_resource path=\"res://view/x.gdshader\"]\nuniform float blend_mul_amount;\n" \
		+ "render_mode unshaded; // not blend_mul\n"
	var hits: Array[Dictionary] = check.scan_text(text)
	if not hits.is_empty():
		return "found %s in comments, a path or a longer name" % [hits]
	var kept: String = check.without_comments("a // b\n/* c\nd */ e\nres://f")
	return "" if kept == "a \n  \n   e\nres://f" else "comments blanked to %s" % kept.c_escape()


func test_an_unallowed_file_fails_naming_file_and_line_and_a_stale_entry_fails() -> String:
	_clear_scratch()
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var bad: String = SCRATCH.path_join("bad.gdshader")
	var clean: String = SCRATCH.path_join("clean.tres")
	var skipped: String = SCRATCH.path_join("notes.txt")
	FileAccess.open(bad, FileAccess.WRITE).store_string(MUL_CODE)
	FileAccess.open(clean, FileAccess.WRITE).store_string(PASS_CODE)
	FileAccess.open(skipped, FileAccess.WRITE).store_string(MUL_CODE)
	var check: GDScript = _check()
	var roots: Array[String] = [SCRATCH]
	var problems: Array[String] = check.scan_files(roots, _no_allow())
	var allowed_bad: Array[String] = check.scan_files(roots, {"files": {bad: 7}, "error": ""})
	var stale: Array[String] = check.scan_files(roots, {"files": {bad: 7, clean: 9}, "error": ""})
	_clear_scratch()
	if problems.size() != 1 or problems[0] != "%s:2: blend_mul" % bad:
		return "an unallowed blend_mul reported %s" % [problems]
	if not allowed_bad.is_empty():
		return "an allowed file reported %s" % [allowed_bad]
	if stale.size() != 1 or not stale[0].contains(clean) or not stale[0].contains("#9"):
		return "a stale entry reported %s" % [stale]
	return ""


func test_an_allow_entry_needs_a_file_and_an_issue() -> String:
	var check: GDScript = _check()
	var good: Dictionary = check.parse_allow("{\"allowed\": [{\"file\": \"xr/a.gdshader\", \"issue\": 12}]}")
	if good["error"] != "" or int((good["files"] as Dictionary).get("xr/a.gdshader", 0)) != 12:
		return "a good list read %s" % good
	for text: String in ["", "{}", "{\"allowed\": [{\"file\": \"xr/a.gdshader\"}]}",
			"{\"allowed\": [{\"file\": \"xr/a.gdshader\", \"issue\": 0}]}",
			"{\"allowed\": [{\"issue\": 4}]}", "{\"allowed\": [3]}"]:
		if str(check.parse_allow(text)["error"]) == "":
			return "%s was accepted" % text
	return ""


func test_the_tree_check_fails_on_a_visible_pass_and_names_its_node() -> String:
	var check: GDScript = _check()
	var root: Node3D = Node3D.new()
	root.name = "Main"
	var room: Node3D = Node3D.new()
	room.name = "Room"
	root.add_child(room)
	room.add_child(_mesh("Plain", PASS_CODE))
	room.add_child(_mesh("Filter", MUL_CODE))
	var label: ColorRect = ColorRect.new()
	label.name = "Overlay"
	var overlay_material: ShaderMaterial = ShaderMaterial.new()
	overlay_material.shader = Shader.new()
	overlay_material.shader.code = "shader_type canvas_item;\nuniform sampler2D s : hint_screen_texture;\n"
	label.material = overlay_material
	root.add_child(label)
	var measurements: Dictionary = {}
	var verdict: Array = check.judge_tree(root, _no_allow(), measurements)
	root.free()
	var found: String = str(measurements.get("screen_pass_found", ""))
	if verdict[0] != AcceptanceReport.RESULT_FAIL:
		return "a visible blend_mul and screen read judged %s" % [verdict]
	if not found.contains("Room/Filter: (built in code) blend_mul") or not found.contains("Overlay: (built in code) hint_screen_texture"):
		return "the passes were reported as %s" % found
	return "" if int(measurements["screen_pass_materials"]) == 3 else "counted %s materials" % measurements


func test_hidden_branches_pass_and_next_passes_are_read() -> String:
	var check: GDScript = _check()
	var root: Node3D = Node3D.new()
	var hidden: Node3D = Node3D.new()
	hidden.visible = false
	root.add_child(hidden)
	hidden.add_child(_mesh("Filter", MUL_CODE))
	var shown: MeshInstance3D = _mesh("Shown", PASS_CODE)
	root.add_child(shown)
	var hidden_verdict: Array = check.judge_tree(root, _no_allow(), {})
	var second: ShaderMaterial = ShaderMaterial.new()
	second.shader = Shader.new()
	second.shader.code = SCREEN_CODE
	shown.material_override.next_pass = second
	var measurements: Dictionary = {}
	var next_verdict: Array = check.judge_tree(root, _no_allow(), measurements)
	root.free()
	if hidden_verdict[0] != AcceptanceReport.RESULT_PASS:
		return "a hidden pass judged %s" % [hidden_verdict]
	if next_verdict[0] != AcceptanceReport.RESULT_FAIL or not str(measurements["screen_pass_found"]).contains("Shown"):
		return "a next pass reading the screen judged %s, %s" % [next_verdict, measurements]
	return ""


func test_an_allowed_shader_file_passes_and_is_reported() -> String:
	var check: GDScript = _check()
	var root: Node3D = Node3D.new()
	var glass: MeshInstance3D = _mesh("Glass", PASS_CODE)
	(glass.material_override as ShaderMaterial).shader = load("res://" + GLASS) as Shader
	root.add_child(glass)
	var measurements: Dictionary = {}
	var allowed: Array = check.judge_tree(root, check.load_allow(check.ALLOW_FILE), measurements)
	var unallowed: Array = check.judge_tree(root, _no_allow(), {})
	var bare: Node3D = Node3D.new()
	var empty: Array = check.judge_tree(bare, _no_allow(), {})
	bare.free()
	root.free()
	if allowed[0] != AcceptanceReport.RESULT_PASS or not str(measurements["screen_pass_allowed"]).contains(GLASS):
		return "the allowed glass judged %s, %s" % [allowed, measurements]
	if unallowed[0] != AcceptanceReport.RESULT_FAIL:
		return "the glass without its entry judged %s" % [unallowed]
	return "" if empty[0] == AcceptanceReport.RESULT_FAIL else "a tree with nothing drawn judged %s" % [empty]


func test_the_main_scene_draws_no_pass_outside_the_allow_list() -> String:
	var check: GDScript = _check()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var measurements: Dictionary = {}
	var verdict: Array = check.judge_tree(main, check.load_allow(check.ALLOW_FILE), measurements)
	main.free()
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else "the main scene judged %s" % [verdict]


func test_the_m6_steps_judge_the_stress_scene_and_the_home_base() -> String:
	var known: Array[String] = AcceptanceCheckFiles.known_checks()
	for name: String in ["no_screen_pass", "no_screen_pass_at_base"]:
		if not known.has(name):
			return "%s is not a known check: %s" % [name, AcceptanceCheckFiles.problem()]
	var stress: AcceptanceStep = _step("no_screen_pass")
	var walls: AcceptanceStep = _step("meltdown_walls")
	var base: AcceptanceStep = _step("no_screen_pass_base")
	var hub_room: AcceptanceStep = _step("hub_room")
	if stress == null or walls == null or base == null or hub_room == null:
		return "steps: no_screen_pass %s, meltdown_walls %s, no_screen_pass_base %s, hub_room %s" % [
			stress, walls, base, hub_room]
	if stress.level != "stress" or stress.replay_path != walls.replay_path or stress.expected_hash != walls.expected_hash:
		return "the stress step flies %s %s to %d" % [stress.level, stress.replay_path, stress.expected_hash]
	for needed: String in ["final_hash", "stress_scene", "no_screen_pass", "no_script_errors"]:
		if not stress.has_check(needed):
			return "the stress step does not check %s" % needed
	if base.run_seed != hub_room.run_seed or base.replay_path != hub_room.replay_path:
		return "the base step flies run %d %s, not hub_room's" % [base.run_seed, base.replay_path]
	# The base check opens the hub through the hub_room check's functions (lane-c's file).
	var opener: Array[String] = []
	for method: Dictionary in (load(_check().HUB_ROOM_CHECK) as GDScript).get_script_method_list():
		opener.append(str(method["name"]))
	for needed: String in ["judge_open_room", "wait_for_arrival"]:
		if not opener.has(needed):
			return "the hub_room check has no %s" % needed
	return "" if base.has_check("no_screen_pass_at_base") else "the base step checks %s" % [base.checks]
