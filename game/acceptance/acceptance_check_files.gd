class_name AcceptanceCheckFiles
extends RefCounted

## Checks registered without editing a shared file (#1297, DEV-6, ARC-4). Every
## script in CHECKS_DIR adds its own checks, so lanes working at the same time
## each own a file instead of all adding lines to `AcceptanceChecks._judges`
## and `AcceptanceStep.KNOWN_CHECKS` (decision record 0003). The checks there
## stay where they are.
##
## A check script extends RefCounted and has
##
##     static func judges() -> Dictionary[String, Callable]
##
## mapping each new check name to a static function called as
## `judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array`
## that returns [result, message] like the judges in `AcceptanceChecks`. A step's
## check names are validated against `known_checks()`: the built-in ones and these.
##
## A script that cannot be read, a judge that is not callable, or a name that
## is already a check fails every suite with the file named, as a broken suite
## file does: a check that silently went missing would let its steps pass.

const CHECKS_DIR: String = "res://acceptance/checks"
const SCRIPT_EXTENSION: String = ".gd"
const JUDGES_METHOD: StringName = &"judges"

static var _dir: String = CHECKS_DIR
static var _loaded: bool = false
static var _judges: Dictionary[String, Callable] = {}
static var _problem: String = ""


## Reads checks from `dir` from now on; tests point it at a scratch folder and back.
static func use_dir(dir: String) -> void:
	_dir = dir
	_loaded = false


## The checks from the check files, by name; empty when one could not be read.
static func judges() -> Dictionary[String, Callable]:
	_load()
	return _judges


## Why the check files could not be read, naming the file, or "".
static func problem() -> String:
	_load()
	return _problem


## Every check name a suite step may list.
static func known_checks() -> Array[String]:
	var names: Array[String] = AcceptanceStep.KNOWN_CHECKS.duplicate()
	for check: String in judges():
		names.append(check)
	return names


## Reads every script in `dir`, in file name order, into `table`. Why one could
## not be read, naming its file, or "".
static func read_dir(dir: String, table: Dictionary[String, Callable]) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var files: Array[String] = []
	# Lists exported scripts by their source name, where DirAccess would see remaps.
	for file: String in ResourceLoader.list_directory(dir):
		if file.ends_with(SCRIPT_EXTENSION):
			files.append(file)
	files.sort()
	for file: String in files:
		var path: String = dir.path_join(file)
		var problem_found: String = _read_script(path, table)
		if problem_found != "":
			return "%s: %s" % [path, problem_found]
	return ""


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var table: Dictionary[String, Callable] = {}
	_problem = read_dir(_dir, table)
	if _problem != "":
		table.clear()
	_judges = table


static func _read_script(path: String, table: Dictionary[String, Callable]) -> String:
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		return "cannot load the script"
	if not ClassDB.is_parent_class(script.get_instance_base_type(), &"RefCounted"):
		return "must extend RefCounted"
	if not _has_static_judges(script):
		return "needs static func judges() -> Dictionary[String, Callable]"
	var raw: Variant = script.call(JUDGES_METHOD)
	if typeof(raw) != TYPE_DICTIONARY:
		return "judges() must return a Dictionary"
	var found: Dictionary = raw
	for check: Variant in found:
		if typeof(check) != TYPE_STRING or not AcceptanceSuite.is_plain_name(check):
			return "judges(): '%s' is not a check name (a-z, 0-9, '_' and '-')" % str(check)
		if AcceptanceStep.KNOWN_CHECKS.has(check) or table.has(check):
			return "judges(): '%s' is already a check" % check
		var judge: Variant = found[check]
		if typeof(judge) != TYPE_CALLABLE or not (judge as Callable).is_valid():
			return "judges(): '%s' has no callable judge" % check
		table[check] = judge
	return ""


static func _has_static_judges(script: GDScript) -> bool:
	for method: Dictionary in script.get_script_method_list():
		if StringName(method["name"]) == JUDGES_METHOD and int(method["flags"]) & METHOD_FLAG_STATIC:
			return true
	return false
