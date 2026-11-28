extends RefCounted

## The `no_screen_pass` and `no_screen_pass_at_base` checks (#1522, GFX-6, PRF-2,
## ARC-4, DEV-6, decision record 0005), lane-a's file under `acceptance/checks/`.
##
## On the Quest 3 a pass over the whole view costs the GPU time PRF-2 needs, as
## the cockpit glass of #1478 showed (#1503). A shader that reads the screen
## (`hint_screen_texture`, `SCREEN_TEXTURE`) or depth (`hint_depth_texture`,
## `DEPTH_TEXTURE`), or multiplies what is behind it (`blend_mul`), is one.
##
## `tests/test_no_screen_pass.gd` scans every shader, material and scene file
## under `view/` and `xr/` as text. The checks here walk the live tree:
## `no_screen_pass` as the flight left it (the stress scene, meltdown running,
## PRF-8), `no_screen_pass_at_base` once losing the ship opens the home base as
## the `hub_room` check does. A visible `ShaderMaterial` doing one of these fails,
## naming the node, unless its file is in `ALLOW_FILE` (data, ARC-4) with the
## issue that will remove it. That file sits here, not under `tests/`, because
## the exports leave `tests/` out and the headset must read it. A stale entry
## fails the unit test. The checks only read the scene; the hash holds the sim.

const CHECK: String = "no_screen_pass"
const CHECK_AT_BASE: String = "no_screen_pass_at_base"
const ALLOW_FILE: String = "res://acceptance/checks/screen_pass_allow.json"
const PATTERNS: Array[String] = [
	"hint_screen_texture", "SCREEN_TEXTURE", "hint_depth_texture", "DEPTH_TEXTURE", "blend_mul",
]
const SCANNED_ROOTS: Array[String] = ["res://view", "res://xr"]
const SCANNED_EXTENSIONS: Array[String] = ["gdshader", "tres", "tscn"]
const HUB_ROOM_CHECK: String = "res://acceptance/checks/hub_room_check.gd"
const PROFILE_FILE: String = "user://meltdown_acceptance_no_screen_pass_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_no_screen_pass_fitting.json"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge, CHECK_AT_BASE: _judge_at_base}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if runner == null or runner.main == null:
		return [AcceptanceReport.RESULT_FAIL, "no main scene"]
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "the step's replay was not flown"]
	return judge_tree(_scene_root(runner.main), load_allow(ALLOW_FILE), measurements)


static func _judge_at_base(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if runner == null or runner.main == null or not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or hub == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var hub_room: GDScript = load(HUB_ROOM_CHECK) as GDScript
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var opened: Array = hub_room.judge_open_room(main, hub, {})
	var verdict: Array = opened
	if opened[0] == AcceptanceReport.RESULT_PASS:
		var arrival: String = hub_room.wait_for_arrival(main, hub)
		verdict = [AcceptanceReport.RESULT_FAIL, arrival] if arrival != "" \
			else judge_tree(_scene_root(main), load_allow(ALLOW_FILE), measurements)
	else:
		verdict = [AcceptanceReport.RESULT_FAIL, "the home base did not open: %s" % opened[1]]
	hub.close()
	_remove_scratch()
	return verdict


## [result, message] for the visible materials under `root`, adding what was
## found to `measurements`. `allow` is what `load_allow` returned.
static func judge_tree(root: Node, allow: Dictionary, measurements: Dictionary) -> Array:
	if str(allow["error"]) != "":
		return [AcceptanceReport.RESULT_FAIL, "%s: %s" % [ALLOW_FILE, allow["error"]]]
	if root == null:
		return [AcceptanceReport.RESULT_FAIL, "no scene to walk"]
	var found: Dictionary = find_in_tree(root, allow["files"])
	var problems: Array[String] = found["problems"]
	var allowed: Array[String] = found["allowed"]
	measurements["screen_pass_materials"] = found["materials"]
	measurements["screen_pass_allowed"] = ", ".join(allowed)
	measurements["screen_pass_found"] = ", ".join(problems)
	if int(found["materials"]) == 0:
		return [AcceptanceReport.RESULT_FAIL, "no visible material was found to judge"]
	if not problems.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "full-screen passes: " + "; ".join(problems)]
	return [AcceptanceReport.RESULT_PASS, "%d visible materials, none reads the screen or depth or multiplies the view%s" % [
		found["materials"], "" if allowed.is_empty() else " (allowed: %s)" % ", ".join(allowed)]]


## {"materials": count, "problems": [...], "allowed": [...]} for the visible
## `ShaderMaterial`s under `root`; each line names the node path, the shader's
## file and what it does. `allowed` maps a file under `res://` to its issue.
static func find_in_tree(root: Node, allowed_files: Dictionary) -> Dictionary:
	var result: Dictionary = {"materials": 0, "problems": [] as Array[String], "allowed": [] as Array[String]}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if not is_shown(node):
			continue  # A hidden branch draws nothing, whatever its children are.
		for material: Material in materials_of(node):
			result["materials"] = int(result["materials"]) + 1
			var shader_material: ShaderMaterial = material as ShaderMaterial
			if shader_material == null or shader_material.shader == null:
				continue
			var file: String = shader_file(shader_material.shader)
			var does: Array[String] = []
			for hit: Dictionary in scan_text(shader_material.shader.code):
				if not does.has(str(hit["pattern"])):
					does.append(str(hit["pattern"]))
			if does.is_empty():
				continue
			var where: String = str(root.get_path_to(node)) if root.is_ancestor_of(node) else str(node.name)
			var line: String = "%s: %s %s" % [where, file if file != "" else "(built in code)", "/".join(does)]
			var list: Array[String] = result["allowed"] if allowed_files.has(file) else result["problems"]
			if not list.has(line):
				list.append(line)
		for child: Node in node.get_children():
			pending.append(child)
	return result


## True unless `node` itself is hidden; parents are judged on the way down.
static func is_shown(node: Node) -> bool:
	if node is Node3D:
		return (node as Node3D).visible
	if node is CanvasItem:
		return (node as CanvasItem).visible
	if node is CanvasLayer:
		return (node as CanvasLayer).visible
	return true


## Every material `node` draws with, next passes included.
static func materials_of(node: Node) -> Array[Material]:
	var direct: Array[Material] = []
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		direct.append(geometry.material_override)
		direct.append(geometry.material_overlay)
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface: int in mesh_instance.mesh.get_surface_count():
				direct.append(mesh_instance.get_active_material(surface))
	elif node is MultiMeshInstance3D:
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if multi != null and multi.mesh != null:
			for surface: int in multi.mesh.get_surface_count():
				direct.append(multi.mesh.surface_get_material(surface))
	if node is CanvasItem:
		direct.append((node as CanvasItem).material)
	var all: Array[Material] = []
	for material: Material in direct:
		var each: Material = material
		while each != null and not all.has(each):
			all.append(each)
			each = each.next_pass
	return all


## The file a shader came from, relative to `res://`, or "" for one built in code.
static func shader_file(shader: Shader) -> String:
	return shader.resource_path.get_slice("::", 0).trim_prefix("res://")


## Each place in `text` that reads the screen or depth or multiplies the view:
## [{"line": 1-based, "pattern": ...}], comments left out.
static func scan_text(text: String) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var lines: PackedStringArray = without_comments(text).split("\n")
	for index: int in lines.size():
		for pattern: String in PATTERNS:
			if _has_word(lines[index], pattern):
				hits.append({"line": index + 1, "pattern": pattern})
	return hits


## `text` with `//` and `/* */` comments blanked and its lines kept, so line
## numbers still match. `res://` is a path, not a comment.
static func without_comments(text: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	var in_block: bool = false
	var index: int = 0
	while index < text.length():
		var two: String = text.substr(index, 2)
		if in_block:
			if two == "*/":
				in_block = false
				index += 2
				continue
			out.append("\n" if text[index] == "\n" else " ")
		elif two == "/*":
			in_block = true
			index += 2
			continue
		elif two == "//" and (index == 0 or text[index - 1] != ":"):
			var end: int = text.find("\n", index)
			index = text.length() if end < 0 else end
			continue
		else:
			out.append(text[index])
		index += 1
	return "".join(out)


## Every problem in the files under `roots`: "file:line: pattern" for each place
## not allowed, and a line for each allowed file that no longer does any.
static func scan_files(roots: Array[String], allow: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if str(allow["error"]) != "":
		return ["%s: %s" % [ALLOW_FILE, allow["error"]]]
	var allowed_files: Dictionary = allow["files"]
	var still_needed: Dictionary = {}
	for path: String in files_under(roots):
		var file: String = path.trim_prefix("res://")
		var hits: Array[Dictionary] = scan_text(FileAccess.get_file_as_string(path))
		if hits.is_empty():
			continue
		if allowed_files.has(file):
			still_needed[file] = true
			continue
		for hit: Dictionary in hits:
			problems.append("%s:%d: %s" % [file, hit["line"], hit["pattern"]])
	for file: String in allowed_files:
		if not still_needed.has(file):
			problems.append("%s is allowed for #%d but no longer reads the screen or depth or uses blend_mul; remove its entry" % [
				file, allowed_files[file]])
	return problems


## The shader, material and scene files under `roots`, sorted.
static func files_under(roots: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = roots.duplicate()
	while not pending.is_empty():
		var dir: String = pending.pop_back()
		for sub: String in DirAccess.get_directories_at(dir):
			pending.append(dir.path_join(sub))
		for file: String in DirAccess.get_files_at(dir):
			if SCANNED_EXTENSIONS.has(file.get_extension()):
				found.append(dir.path_join(file))
	found.sort()
	return found


## {"files": {file under res:// -> issue}, "error": ""} from an allow list file.
static func load_allow(path: String) -> Dictionary:
	return parse_allow(FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "")


## As `load_allow`, from the file's text; an entry needs a file and the issue
## that will remove it.
static func parse_allow(text: String) -> Dictionary:
	var files: Dictionary = {}
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary or not (parsed as Dictionary).get("allowed") is Array:
		return {"files": files, "error": "needs an \"allowed\" list"}
	for entry: Variant in (parsed as Dictionary)["allowed"]:
		if not entry is Dictionary:
			return {"files": {}, "error": "an entry is not an object"}
		var file: Variant = (entry as Dictionary).get("file")
		var issue: Variant = (entry as Dictionary).get("issue")
		if not file is String or (file as String).is_empty():
			return {"files": {}, "error": "an entry has no file"}
		if not (issue is float or issue is int) or int(issue) <= 0 or float(issue) != floorf(float(issue)):
			return {"files": {}, "error": "%s names no issue that will remove it" % file}
		files[file] = int(issue)
	return {"files": files, "error": ""}


static func _has_word(line: String, word: String) -> bool:
	var at: int = line.find(word)
	while at >= 0:
		var before: bool = at == 0 or not _is_word_char(line[at - 1])
		var end: int = at + word.length()
		var after: bool = end >= line.length() or not _is_word_char(line[end])
		if before and after:
			return true
		at = line.find(word, at + 1)
	return false


static func _is_word_char(character: String) -> bool:
	return character == "_" or (character >= "a" and character <= "z") \
		or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9")


static func _scene_root(main: Node) -> Node:
	return main.get_tree().root if main.is_inside_tree() else main


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
