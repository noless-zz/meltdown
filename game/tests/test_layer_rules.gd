extends RefCounted

## Guards the layer rules for `core/` and `gen/` by reading their source
## (ARC-1, ARC-3, MP-2). An instance check cannot do this: a script that
## extends RefCounted can still call the scene tree, a device or the clock.
##
## The scan is textual. It ignores comments but not strings, and it does not
## follow a string that continues over several lines.

const SCANNED_DIRS: Array[String] = ["res://core", "res://gen"]
const ALLOWED_BASE: String = "RefCounted"

## Node, rendering, input, audio and wall-clock APIs. An entry matches where
## it starts a name, so `Node` also catches `Node3D` and `NodePath`, while
## `ShipInput.` and `PathNode` are left alone.
const FORBIDDEN_APIS: Array[String] = [
	"Node", "get_tree", "Engine.get_main_loop",
	"Input.", "InputEvent", "XRServer",
	"DisplayServer", "RenderingServer",
	"AudioServer", "AudioStream",
	"Time.", "OS.get_ticks", "OS.get_unix_time",
]
## Unseeded only as a global call: `rng.randf()` on a seeded generator is fine.
const GLOBAL_RANDOM: Array[String] = ["randf", "randi", "randf_range", "randi_range", "randfn"]
## Unseeded on any receiver: arrays draw from the global generator, and
## `randomize()` seeds from the clock even on a RandomNumberGenerator.
const ANY_RANDOM: Array[String] = ["randomize", "pick_random", "shuffle"]

const NAME_CHARS: String = "A-Za-z0-9_"
const SCRATCH_DIR: String = "user://test_layer_rules"

var _extends: RegEx = RegEx.create_from_string(
	"(?:^|\\s)extends\\s+(\"[^\"]*\"|'[^']*'|[A-Za-z_][%s.]*)" % NAME_CHARS)
var _declares: RegEx = RegEx.create_from_string(
	"(?:^|\\s)class(?:_name)?\\s+([A-Za-z_][%s]*)" % NAME_CHARS)
var _apis: Dictionary[String, RegEx] = {}
var _random: Dictionary[String, RegEx] = {}


func _init() -> void:
	for api: String in FORBIDDEN_APIS:
		_apis[api] = RegEx.create_from_string(
			"(?<![%s])%s" % [NAME_CHARS, api.replace(".", "\\.")])
	for call: String in GLOBAL_RANDOM:
		_random[call] = RegEx.create_from_string("(?<![%s.])%s\\s*\\(" % [NAME_CHARS, call])
	for call: String in ANY_RANDOM:
		_random[call] = RegEx.create_from_string("(?<![%s])%s\\s*\\(" % [NAME_CHARS, call])


## Returns the part of `line` before its comment. A `#` inside a string is not
## a comment, so `begins_with("#")` keeps the code that follows it.
func strip_comment(line: String) -> String:
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if quote != "":
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line


## Names declared by `class_name` or an inner `class` in `source`.
func declared_classes(source: String) -> Array[String]:
	var names: Array[String] = []
	for raw_line: String in source.split("\n"):
		var found: RegExMatch = _declares.search(strip_comment(raw_line))
		if found != null:
			names.append(found.get_string(1))
	return names


## Scans one script. Returns one finding per broken rule, each starting with
## `<path>:<line>:`. `layer_classes` are the classes declared in core/ and gen/.
func scan_source(source: String, path: String, layer_classes: Array[String]) -> Array[String]:
	var findings: Array[String] = []
	var allowed: Array[String] = layer_classes + declared_classes(source)
	var line_number: int = 0
	for raw_line: String in source.split("\n"):
		line_number += 1
		var code: String = strip_comment(raw_line)
		if code.strip_edges() == "":
			continue
		var where: String = "%s:%d: " % [path, line_number]
		var base: RegExMatch = _extends.search(code)
		if base != null and not _base_is_allowed(base.get_string(1), allowed):
			findings.append(where + "extends %s, which is not %s or a class from core/ or gen/"
				% [base.get_string(1), ALLOWED_BASE])
		for api: String in _apis:
			if _apis[api].search(code) != null:
				findings.append(where + "forbidden API '%s'" % api)
		for call: String in _random:
			if _random[call].search(code) != null:
				findings.append(where + "unseeded randomness '%s'" % call)
	return findings


## Every `.gd` file under `root`, in all subfolders, sorted.
func collect_scripts(root: String) -> Array[String]:
	var scripts: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return scripts
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			scripts.append(root + "/" + file)
	for folder: String in dir.get_directories():
		scripts.append_array(collect_scripts(root + "/" + folder))
	scripts.sort()
	return scripts


func _base_is_allowed(base: String, allowed: Array[String]) -> bool:
	if base.begins_with("\"") or base.begins_with("'"):
		var script_path: String = base.substr(1, base.length() - 2)
		for root: String in SCANNED_DIRS:
			if script_path.begins_with(root + "/"):
				return true
		return false
	# `Outer.Inner` is as allowed as `Outer` is.
	var outer: String = base.get_slice(".", 0)
	return outer == ALLOWED_BASE or allowed.has(outer)


func _scan(source: String) -> Array[String]:
	return scan_source(source, "res://core/snippet.gd", ["ShipState"])


## "" if `source` gives exactly one finding, on `line`, containing `text`.
func _expect_one(source: String, line: int, text: String) -> String:
	var findings: Array[String] = _scan(source)
	if findings.size() != 1:
		return "expected 1 finding for %s, got %s" % [source.c_escape(), findings]
	if not findings[0].begins_with("res://core/snippet.gd:%d: " % line):
		return "wrong file or line in '%s'" % findings[0]
	if not findings[0].contains(text):
		return "'%s' does not mention %s" % [findings[0], text]
	return ""


func test_core_and_gen_follow_the_layer_rules() -> String:
	var scripts: Array[String] = []
	for root: String in SCANNED_DIRS:
		scripts.append_array(collect_scripts(root))
	# A scan that finds no file would pass forever, whatever core/ contains.
	if not scripts.has("res://core/sim.gd"):
		return "the scan did not find res://core/sim.gd; found %s" % [scripts]
	var layer_classes: Array[String] = []
	for path: String in scripts:
		layer_classes.append_array(declared_classes(FileAccess.get_file_as_string(path)))
	var findings: Array[String] = []
	for path: String in scripts:
		findings.append_array(scan_source(FileAccess.get_file_as_string(path), path, layer_classes))
	return "\n".join(findings)


func test_collect_scripts_looks_into_subfolders() -> String:
	var nested: String = SCRATCH_DIR + "/a/b"
	DirAccess.make_dir_recursive_absolute(nested)
	for path: String in [SCRATCH_DIR + "/top.gd", nested + "/deep.gd", nested + "/notes.txt"]:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string("extends RefCounted\n")
		file.close()
	var found: Array[String] = collect_scripts(SCRATCH_DIR)
	for path: String in [nested + "/deep.gd", nested + "/notes.txt", SCRATCH_DIR + "/top.gd",
			nested, SCRATCH_DIR + "/a", SCRATCH_DIR]:
		DirAccess.remove_absolute(path)
	if found != [nested + "/deep.gd", SCRATCH_DIR + "/top.gd"]:
		return "found %s" % [found]
	return ""


func test_scan_reports_a_base_class_outside_the_layers() -> String:
	var cases: Dictionary[String, String] = {
		"extends Resource\n": "Resource",
		"class_name Thing extends Object\n": "Object",
		"class Inner extends Resource:\n\tpass\n": "Resource",
		"extends \"res://view/test_tunnel.gd\"\n": "\"res://view/test_tunnel.gd\"",
	}
	for source: String in cases:
		var problem: String = _expect_one(source, 1, "extends " + cases[source])
		if problem != "":
			return problem
	return ""


func test_scan_accepts_bases_from_core_and_gen() -> String:
	var source: String = "\n".join([
		"class_name Drone", "extends ShipState", "",
		"class Part extends RefCounted:", "\tpass", "",
		"class Gun extends Part:", "\tpass", "",
		"class Wing extends \"res://gen/wing.gd\":", "\tpass", ""])
	var findings: Array[String] = _scan(source)
	if not findings.is_empty():
		return "reported %s" % [findings]
	return ""


func test_scan_reports_every_forbidden_api() -> String:
	for api: String in FORBIDDEN_APIS:
		var problem: String = _expect_one("extends RefCounted\n\tfoo(%s)\n" % api, 2, "'%s'" % api)
		if problem != "":
			return problem
	return ""


func test_scan_reports_one_snippet_per_category() -> String:
	var cases: Dictionary[String, String] = {
		"\tvar parent: Node3D = null\n": "'Node'",
		"\tRenderingServer.force_draw()\n": "'RenderingServer'",
		"\tif Input.is_action_pressed(\"fire\"):\n": "'Input.'",
		"\tAudioServer.set_bus_mute(0, true)\n": "'AudioServer'",
		"\tvar now: int = Time.get_ticks_msec()\n": "'Time.'",
		"\tvar roll: int = randi() % 6\n": "'randi'",
	}
	for line: String in cases:
		var problem: String = _expect_one("extends RefCounted\n\n" + line, 3, cases[line])
		if problem != "":
			return problem
	return ""


func test_scan_reports_unseeded_randomness() -> String:
	for call: String in GLOBAL_RANDOM + ANY_RANDOM:
		var problem: String = _expect_one("\tvar x = %s()\n" % call, 1, "'%s'" % call)
		if problem != "":
			return problem
	for line: String in ["\tdeck.shuffle()\n", "\tvar card = deck.pick_random()\n", "\trng.randomize()\n"]:
		if _scan(line).size() != 1:
			return "expected 1 finding for %s, got %s" % [line.c_escape(), _scan(line)]
	return ""


func test_scan_allows_a_seeded_generator_and_lookalike_names() -> String:
	var source: String = "\n".join([
		"extends RefCounted",
		"var rng: RandomNumberGenerator = RandomNumberGenerator.new()",
		"func roll(input: ShipInput) -> float:",
		"\trng.seed = 7",
		"\tvar other: ShipInput = ShipInput.new()",
		"\tvar junction: PathNode = PathNode.new()",
		"\tseeded_shuffle(junction.exits, rng)",
		"\treturn rng.randf() + rng.randi_range(1, 6) + rng.randfn() + run_time.x",
		""])
	var findings: Array[String] = scan_source(source, "res://gen/snippet.gd", ["PathNode"])
	if not findings.is_empty():
		return "reported %s" % [findings]
	return ""


func test_scan_ignores_comments_but_not_code_after_a_hash_in_a_string() -> String:
	var source: String = "\n".join([
		"extends RefCounted",
		"## No Node, no Input.get_vector(), no Time.get_ticks_msec(), no randf().",
		"\t# extends Node3D",
		"var tick: int = 0  # not from Time.get_ticks_msec() or get_tree()",
		""])
	var findings: Array[String] = _scan(source)
	if not findings.is_empty():
		return "comments were reported: %s" % [findings]
	return _expect_one("\tif line.begins_with(\"#\") or 'it\\'s #' == line: get_tree()\n", 1, "'get_tree'")
