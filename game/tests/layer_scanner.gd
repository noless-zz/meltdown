extends RefCounted

## The source scan behind `test_layer_rules.gd`, kept apart so the tests stay
## short. It guards the layer rules for `core/`, `gen/` and `net/` (ARC-1,
## ARC-2, ARC-3, MP-2, MP-3). An instance check cannot do this: a script that
## extends RefCounted can still call the scene tree, a device or the clock.
##
## The scan is textual. It ignores comments but not strings, and it does not
## follow a string that continues over several lines.

const SCANNED_DIRS: Array[String] = ["res://core", "res://gen", "res://net"]
## Layers the scanned ones may not depend on (the table in `CLAUDE.md`). `net/`
## may use `core/` and `gen/`; that direction is not checked here.
const OUTSIDE_DIRS: Array[String] = ["res://view", "res://xr", "res://meta"]
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
var _global_class: RegEx = RegEx.create_from_string(
	"(?:^|\\s)class_name\\s+([A-Za-z_][%s]*)" % NAME_CHARS)
var _outside_path: RegEx = null
var _apis: Dictionary[String, RegEx] = {}
var _random: Dictionary[String, RegEx] = {}


func _init() -> void:
	var outside: PackedStringArray = []
	for dir: String in OUTSIDE_DIRS:
		outside.append(dir.trim_prefix("res://"))
	_outside_path = RegEx.create_from_string(
		"res://(?:%s)(?![%s])" % ["|".join(outside), NAME_CHARS])
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


## Names declared by `class_name` in `source`. Inner classes are left out:
## other scripts reach them only through their outer class.
func global_classes(source: String) -> Array[String]:
	var names: Array[String] = []
	for raw_line: String in source.split("\n"):
		var found: RegExMatch = _global_class.search(strip_comment(raw_line))
		if found != null:
			names.append(found.get_string(1))
	return names


## Scans one script. Returns one finding per broken rule, each starting with
## `<path>:<line>:`. `layer_classes` are the classes declared in the scanned
## layers; `outside_classes` are the global classes of `OUTSIDE_DIRS`.
func scan_source(source: String, path: String, layer_classes: Array[String],
		outside_classes: Array[String] = []) -> Array[String]:
	var findings: Array[String] = []
	var allowed: Array[String] = layer_classes + declared_classes(source)
	var forbidden_classes: Dictionary[String, RegEx] = {}
	for name: String in outside_classes:
		if not allowed.has(name):
			forbidden_classes[name] = RegEx.create_from_string(
				"(?<![%s.])%s(?![%s])" % [NAME_CHARS, name, NAME_CHARS])
	var line_number: int = 0
	for raw_line: String in source.split("\n"):
		line_number += 1
		var code: String = strip_comment(raw_line)
		if code.strip_edges() == "":
			continue
		var where: String = "%s:%d: " % [path, line_number]
		var base: RegExMatch = _extends.search(code)
		if base != null and not _base_is_allowed(base.get_string(1), allowed):
			findings.append(where + "extends %s, which is not %s or a class from core/, gen/ or net/"
				% [base.get_string(1), ALLOWED_BASE])
		else:
			# A bad base is reported once, not again as a dependency.
			findings.append_array(_dependencies(code, where, forbidden_classes))
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


func _dependencies(code: String, where: String,
		forbidden_classes: Dictionary[String, RegEx]) -> Array[String]:
	var findings: Array[String] = []
	var found: RegExMatch = _outside_path.search(code)
	if found != null:
		findings.append(where + "depends on %s, outside the layers it may use" % found.get_string())
	for name: String in forbidden_classes:
		if forbidden_classes[name].search(code) != null:
			findings.append(where + "uses class '%s' from view/, xr/ or meta/" % name)
	return findings


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
