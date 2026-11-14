extends RefCounted

## Guards the layer rules of `CLAUDE.md` for `core/` and `gen/` by reading their
## source (ARC-1, ARC-3, MP-2).
##
## A check on live objects cannot do this: a script that extends a node, reads
## a device or asks the clock still loads and runs in the headless test runner.
## Only its text shows the dependency, so the text is what is scanned.
##
## Comments are skipped, so documentation may name these APIs. String literals
## are scanned like code: a forbidden name inside a string is reported too.

const SCANNED_DIRS: Array[String] = ["res://core", "res://gen"]
## Paths a quoted `extends "res://..."` may point into.
const ALLOWED_BASE_PATHS: Array[String] = ["res://core/", "res://gen/"]
const ALLOWED_BASE: String = "RefCounted"

## Node, rendering, input, audio and wall-clock APIs. A name matches where it
## starts an identifier, so `Node` also reports `Node3D` and `NodePath`, while
## `Input.` leaves `ShipInput.new()` alone.
const FORBIDDEN_APIS: Array[String] = [
	"Node",
	"get_tree",
	"Engine.get_main_loop",
	"Input.",
	"InputEvent",
	"XRServer",
	"DisplayServer",
	"RenderingServer",
	"AudioServer",
	"AudioStream",
	"Time.",
	"OS.get_ticks",
	"OS.get_unix_time",
]

## Global functions that draw from the engine's shared, unseeded generator.
## The same names called on an object (`rng.randf()`) belong to a
## `RandomNumberGenerator` the simulation seeded itself, and are allowed.
const UNSEEDED_GLOBALS: Array[String] = [
	"randf", "randi", "randf_range", "randi_range", "randfn",
]
## Reported however they are called. `pick_random` and `shuffle` are array
## methods that use the shared generator; `randomize` reseeds from the clock
## both as a global and on a `RandomNumberGenerator`.
const UNSEEDED_ANYWHERE: Array[String] = ["randomize", "pick_random", "shuffle"]


func test_core_and_gen_sources_follow_the_layer_rules() -> String:
	var sources: Dictionary[String, String] = {}
	for dir_path: String in SCANNED_DIRS:
		var paths: Array[String] = []
		if not _collect_scripts(dir_path, paths):
			return "cannot open %s" % dir_path
		for path: String in paths:
			sources[path] = FileAccess.get_file_as_string(path)
	var core_count: int = 0
	for path: String in sources:
		if path.begins_with("res://core/"):
			core_count += 1
	# An empty scan would pass for the wrong reason, for example after the
	# folder was renamed.
	if core_count == 0:
		return "found no .gd file under res://core"
	var known: Array[String] = []
	for path: String in sources:
		known.append_array(_declared_classes(sources[path]))
	var problems: Array[String] = []
	for path: String in sources:
		problems.append_array(_scan_source(path, sources[path], known))
	return "\n".join(problems)


func test_scan_reports_a_base_class_outside_the_layers() -> String:
	for base: String in ["Node3D", "Resource", "Elsewhere", "\"res://view/thing.gd\""]:
		var text: String = "class_name Thing\nextends %s\n" % base
		var problems: Array[String] = _scan_source("res://core/thing.gd", text, ["Thing"])
		if not _has_problem(problems, "res://core/thing.gd:2:", "extends"):
			return "extends %s was not reported with file and line: %s" % [base, problems]
	var inner: Array[String] = _scan_source("a.gd", "class Part extends Sprite2D:\n\tpass\n", [])
	if not _has_problem(inner, "a.gd:1:", "Sprite2D"):
		return "an inner class extending Sprite2D was not reported: %s" % [inner]
	return ""


func test_scan_reports_every_forbidden_api() -> String:
	for api: String in FORBIDDEN_APIS:
		var text: String = "extends RefCounted\n\nfunc f() -> void:\n\tprint(%sx)\n" % api
		var problems: Array[String] = _scan_source("res://gen/bad.gd", text, [])
		if not _has_problem(problems, "res://gen/bad.gd:4:", api):
			return "%s was not reported with file and line: %s" % [api, problems]
	return ""


func test_scan_reports_unseeded_randomness() -> String:
	var calls: Array[String] = [
		"randf()", "randi()", "randf_range(0.0, 1.0)", "randi_range(1, 6)",
		"randfn(0.0, 1.0)", "randomize()", "rng.randomize()",
		"rooms.pick_random()", "rooms.shuffle()",
	]
	for call: String in calls:
		var text: String = "extends RefCounted\nfunc f() -> void:\n\tvar v: Variant = %s\n" % call
		var problems: Array[String] = _scan_source("res://core/dice.gd", text, [])
		if not _has_problem(problems, "res://core/dice.gd:3:", "unseeded"):
			return "%s was not reported with file and line: %s" % [call, problems]
	return ""


func test_scan_accepts_a_clean_script() -> String:
	var text: String = "\n".join([
		"class_name Drone",
		"extends Robot",
		"## No Node, no Input.is_action_pressed(), no Time.get_ticks_msec().",
		"# randf() and shuffle() are named here only as documentation.",
		"var rng: RandomNumberGenerator = RandomNumberGenerator.new()",
		"",
		"class Wing extends RefCounted:",
		"\tvar span: float = 1.0",
		"",
		"class Tail extends \"res://core/fin.gd\":",
		"\tpass",
		"",
		"func roll(input: ShipInput) -> float:",
		"\trng.seed = 7  # not randomize(), not Time.get_unix_time_from_system()",
		"\tvar label: String = \"# is not a comment here\"",
		"\tvar other: ShipInput = ShipInput.new()",
		"\tvar shuffled: int = rng.randi_range(1, 6)",
		"\treturn rng.randf() + rng.randfn(0.0, 1.0)",
		"",
	])
	var problems: Array[String] = _scan_source("res://core/drone.gd", text, ["Robot", "Drone"])
	if not problems.is_empty():
		return "a clean script was reported: %s" % [problems]
	return ""


func test_declared_classes_lists_named_and_inner_classes() -> String:
	var text: String = "class_name Robot extends RefCounted\n# class Ghost\nclass Arm:\n\tpass\n"
	var found: Array[String] = _declared_classes(text)
	if found != (["Robot", "Arm"] as Array[String]):
		return "expected Robot and Arm, got %s" % [found]
	return ""


## Returns one line per broken rule, each starting with `<path>:<line>:`.
## `known_classes` are the classes declared in `core/` and `gen/`, which the
## scanned script may extend.
func _scan_source(path: String, text: String, known_classes: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	var line_number: int = 0
	for raw_line: String in text.split("\n"):
		line_number += 1
		var code: String = _strip_comment(raw_line)
		if code.strip_edges() == "":
			continue
		var where: String = "%s:%d: " % [path, line_number]
		var base: String = _base_class(code)
		if base != "" and not _is_allowed_base(base, known_classes):
			problems.append(where + "extends %s, which is neither RefCounted nor a class from core/ or gen/" % base)
		for api: String in FORBIDDEN_APIS:
			if _mentions(code, api, false, false):
				problems.append(where + "uses %s, a node, rendering, input, audio or clock API" % api)
		for name: String in UNSEEDED_GLOBALS:
			if _mentions(code, name, true, true):
				problems.append(where + "calls %s, which is unseeded randomness" % name)
		for name: String in UNSEEDED_ANYWHERE:
			if _mentions(code, name, true, false):
				problems.append(where + "calls %s, which is unseeded randomness" % name)
	return problems


## Class names a script declares with `class_name` or as inner classes.
func _declared_classes(text: String) -> Array[String]:
	var names: Array[String] = []
	for raw_line: String in text.split("\n"):
		var words: PackedStringArray = _strip_comment(raw_line).split(" ", false)
		if words.size() >= 2 and (words[0] == "class_name" or words[0] == "class"):
			names.append(words[1].trim_suffix(":"))
	return names


## The line up to a `#` that is not inside a string literal.
func _strip_comment(line: String) -> String:
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote != "":
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "#":
			return line.substr(0, index)
		index += 1
	return line


## The base named by an `extends` on this line, or "" if there is none. Only
## lines that open with `extends`, `class_name` or `class` can carry one, so
## the word inside a string is not mistaken for it.
func _base_class(code: String) -> String:
	var words: PackedStringArray = code.replace("\t", " ").split(" ", false)
	if words.is_empty() or not words[0] in ["extends", "class_name", "class"]:
		return ""
	var at: int = words.find("extends")
	if at == -1 or at + 1 >= words.size():
		return ""
	return words[at + 1].trim_suffix(":")


func _is_allowed_base(base: String, known_classes: Array[String]) -> bool:
	if base.begins_with("\"") or base.begins_with("'"):
		var target: String = base.substr(1)
		for prefix: String in ALLOWED_BASE_PATHS:
			if target.begins_with(prefix):
				return true
		return false
	# `Outer.Inner` is allowed when `Outer` is.
	var outer: String = base.get_slice(".", 0)
	return outer == ALLOWED_BASE or outer in known_classes


## True if `name` appears in `code` where it starts an identifier.
## `whole_word`: it must also end the identifier (`randf` is not `randf_range`).
## `global_only`: a call on an object, written after a dot, does not count.
func _mentions(code: String, name: String, whole_word: bool, global_only: bool) -> bool:
	var from: int = 0
	while true:
		var at: int = code.find(name, from)
		if at == -1:
			return false
		from = at + 1
		var before: String = code[at - 1] if at > 0 else ""
		var end: int = at + name.length()
		var after: String = code[end] if end < code.length() else ""
		if _is_identifier_character(before):
			continue
		if whole_word and _is_identifier_character(after):
			continue
		if global_only and before == ".":
			continue
		return true
	return false


func _is_identifier_character(character: String) -> bool:
	if character == "":
		return false
	return character == "_" or character.is_valid_identifier() or character.is_valid_int()


func _has_problem(problems: Array[String], prefix: String, needle: String) -> bool:
	for problem: String in problems:
		if problem.begins_with(prefix) and problem.contains(needle):
			return true
	return false


## Appends every `.gd` path under `dir_path`, recursively, in a stable order.
## Returns false if a directory cannot be opened.
func _collect_scripts(dir_path: String, paths: Array[String]) -> bool:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return false
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file: String in files:
		if file.ends_with(".gd"):
			paths.append(dir_path + "/" + file)
	var subdirs: PackedStringArray = dir.get_directories()
	subdirs.sort()
	for subdir: String in subdirs:
		if not _collect_scripts(dir_path + "/" + subdir, paths):
			return false
	return true
