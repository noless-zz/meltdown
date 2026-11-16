class_name LevelSwitch
extends RefCounted

## The main scene's level switch (#291): `--level=<name>` on the command line,
## or the same name in the `meltdown_level` intent extra on the headset, the way
## `--acceptance` is read (#165). The name picks `res://data/levels/<name>_level.json`,
## so `--level=g2` flies the hand-built G2 level (GEN-5) and a new level is a
## new data file, not code (ARC-4). Without the switch the test tunnel stays.
##
## It sits beside `main.gd`, like `CombatWiring`, because it joins the `net/`
## session's level to the `view/` level drawing. It reads the level file and
## hands the drawing the level's walls; it never writes simulation state (MP-2).

const ARG_PREFIX: String = "--level="
const INTENT_EXTRA: String = "meltdown_level"
const LEVEL_DIR: String = "res://data/levels/"
const LEVEL_SUFFIX: String = "_level.json"
## The drawn test tunnel, removed when a level replaces it.
const TUNNEL_NODE: String = "TestTunnel"


## The level name asked for, or "" when the switch is off. A command-line
## argument wins over the intent extra; the last `--level=` given counts.
static func requested(user_args: PackedStringArray, intent_value: String) -> String:
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	return asked if asked != "" else intent_value.strip_edges()


## The level file for `level_name`, or "" for a name that is not lower-case
## letters, digits and underscores, so a switch value cannot reach outside the
## levels folder.
static func path_for(level_name: String) -> String:
	if level_name == "":
		return ""
	for character: String in level_name:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(character):
			return ""
	return LEVEL_DIR + level_name + LEVEL_SUFFIX


## The level file this launch asks for, or "" when the switch is off. A name
## that cannot be a level file is printed and gives "".
static func requested_path() -> String:
	var runtime: Object = InstallerProbe.android_runtime()
	var intent_value: String = InstallerProbe.intent_extra(runtime, INTENT_EXTRA) if runtime != null else ""
	var level_name: String = requested(OS.get_cmdline_user_args(), intent_value)
	var path: String = path_for(level_name)
	if level_name != "" and path == "":
		print("Meltdown: level \"%s\" is not a level name; flying the test tunnel" % level_name)
	return path


## The level in the file at `path`, or null after printing why when the file
## is missing or rejected, so the caller keeps the test tunnel.
static func load_level(path: String) -> LevelDef:
	var problem: String = ""
	var level: LevelDef = null
	if not FileAccess.file_exists(path):
		problem = "file not found"
	else:
		level = LevelDef.parse_json(FileAccess.get_file_as_string(path))
		problem = level.error
	if problem != "":
		print("Meltdown: level %s rejected (%s); flying the test tunnel" % [path, problem])
		return null
	return level


## Takes the test tunnel out of `world` and draws `level`'s walls there in its
## place. `world`'s space is the simulation's, so the level is drawn where the
## session's walls are, with no offset. Returns the drawing.
static func show_level(world: Node3D, level: LevelDef) -> LevelView:
	var tunnel: Node = world.get_node_or_null(TUNNEL_NODE)
	if tunnel != null:
		world.remove_child(tunnel)
		tunnel.free()
	var view: LevelView = world.get_node_or_null(LevelView.NODE_NAME) as LevelView
	if view == null:
		view = LevelView.new()
		world.add_child(view)
	view.build(level.union)
	return view
