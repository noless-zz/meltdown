class_name LevelSwitch
extends RefCounted

## The main scene's level switch (#291): `--level=<name>` on the command line,
## or the same name in the `meltdown_level` intent extra on the headset, the way
## `--acceptance` is read (#165). The name picks `res://data/levels/<name>_level.json`,
## so `--level=g2` flies the hand-built G2 level (GEN-5) and a new level is a
## new data file, not code (ARC-4). Without the switch the test tunnel stays.
##
## `--seed=<n>`, or the `meltdown_seed` intent extra, flies the level
## `MineGenerator` builds for seed `n` instead (#382, GEN-1, GEN-2, G3), with the
## reactor plan and loop bridges from `res://data/gen/`, after `LevelValidator`
## has passed it. `--level` wins when both are given. The choice travels to
## `main.gd` as one source string, a level file path or `seed:<n>`, and
## `load_level` turns either into the `LevelDef` (a seed through `SeedLevel`),
## so `main.gd` does not grow.
##
## `--seed=random`, or `random` in `meltdown_seed`, flies a fresh seed (#533,
## DEV-6, G3), so the owner can fly unseen levels without inventing numbers. The
## pick is printed so the flight can be repeated with `--seed=<n>`. It uses an
## unseeded generator here, never in `core/` or `gen/` (ARC-1): from the picked
## seed on, everything is as if `--seed=<n>` had been given.
##
## It sits beside `main.gd`, like `CombatWiring`, because it joins the `net/`
## session's level to the `view/` level drawing. It reads the level file and
## hands the drawing the level's walls; it never writes simulation state (MP-2).

const ARG_PREFIX: String = "--level="
const INTENT_EXTRA: String = "meltdown_level"
const LEVEL_DIR: String = "res://data/levels/"
const LEVEL_SUFFIX: String = "_level.json"
## What a level file may leave out, such as its exit radius (ARC-4, #311).
const DEFAULTS_FILE: String = "res://data/level_defaults.json"
## The drawn test tunnel, removed when a level replaces it.
const TUNNEL_NODE: String = "TestTunnel"
const SEED_ARG_PREFIX: String = "--seed="
const SEED_INTENT_EXTRA: String = "meltdown_seed"
## A source naming a generated level: `seed:<n>`.
const SEED_PREFIX: String = "seed:"
## Longest seed accepted: 18 digits always fit a 64-bit int.
const SEED_MAX_DIGITS: int = 18
## The seed value that asks for a fresh seed instead of a number.
const RANDOM_SEED: String = "random"
## Range of a picked seed: positive, and short enough to read off a log and type.
const RANDOM_SEED_MIN: int = 1
const RANDOM_SEED_MAX: int = 999999999


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


## What this launch asks to fly: a level file path, `seed:<n>`, or "" when
## neither switch is on. A name that cannot be a level file, or a seed that is
## not a non-negative whole number, is printed and gives "".
static func requested_path() -> String:
	var runtime: Object = InstallerProbe.android_runtime()
	var level_intent: String = InstallerProbe.intent_extra(runtime, INTENT_EXTRA) if runtime != null else ""
	var seed_intent: String = InstallerProbe.intent_extra(runtime, SEED_INTENT_EXTRA) if runtime != null else ""
	return requested_source(OS.get_cmdline_user_args(), level_intent, seed_intent)


## The source for these arguments and intent extras: `--level` (argument, then
## extra) wins; otherwise `--seed` (argument, then extra; the last one given
## counts). A bad value is printed and the tunnel stays, even when the other
## switch is on, so a typo is never covered up by another level. A seed of
## `random` is replaced by `pick_seed`'s result (`random_seed` when not given;
## tests inject one so they are not flaky), printed once.
static func requested_source(user_args: PackedStringArray, level_intent: String,
		seed_intent: String, pick_seed: Callable = Callable()) -> String:
	var level_name: String = requested(user_args, level_intent)
	if level_name != "":
		var path: String = path_for(level_name)
		if path == "":
			print("Meltdown: level \"%s\" is not a level name; flying the test tunnel" % level_name)
		return path
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(SEED_ARG_PREFIX):
			asked = arg.substr(SEED_ARG_PREFIX.length()).strip_edges()
	if asked == "":
		asked = seed_intent.strip_edges()
	if asked == "":
		return ""
	if asked == RANDOM_SEED:
		var picked: int = pick_seed.call() if pick_seed.is_valid() else random_seed()
		print("Meltdown: flying random seed %d" % picked)
		return SEED_PREFIX + str(picked)
	if seed_from(asked) < 0:
		print("Meltdown: seed \"%s\" is not a non-negative whole number; flying the test tunnel" % asked)
		return ""
	return SEED_PREFIX + str(seed_from(asked))


## A fresh seed from `RANDOM_SEED_MIN` to `RANDOM_SEED_MAX`. Deliberately
## unseeded: it only chooses which level to fly, before any simulation exists.
static func random_seed() -> int:
	var generator: RandomNumberGenerator = RandomNumberGenerator.new()
	generator.randomize()
	return generator.randi_range(RANDOM_SEED_MIN, RANDOM_SEED_MAX)


## `text` as a seed, or -1 unless it is only digits (at most `SEED_MAX_DIGITS`).
static func seed_from(text: String) -> int:
	if text == "" or text.length() > SEED_MAX_DIGITS:
		return -1
	for character: String in text:
		if not "0123456789".contains(character):
			return -1
	return text.to_int()


## The level `path` names, a level file or `seed:<n>` (`requested_path`), or
## null after printing why when it is missing or rejected, so the caller keeps
## the test tunnel. What the level leaves out comes from `defaults_path`.
static func load_level(path: String, defaults_path: String = DEFAULTS_FILE) -> LevelDef:
	if path.begins_with(SEED_PREFIX):
		var level_seed: int = seed_from(path.substr(SEED_PREFIX.length()))
		if level_seed < 0:
			print("Meltdown: %s is not a seed; flying the test tunnel" % path)
			return null
		return SeedLevel.load_level(level_seed, defaults_path)
	var problem: String = ""
	var level: LevelDef = null
	var defaults: LevelDefaults = load_defaults(defaults_path)
	if defaults == null:
		problem = "level defaults %s rejected" % defaults_path
	elif not FileAccess.file_exists(path):
		problem = "file not found"
	else:
		level = LevelDef.parse_json(FileAccess.get_file_as_string(path), defaults)
		problem = level.error
	if problem != "":
		print("Meltdown: level %s rejected (%s); flying the test tunnel" % [path, problem])
		return null
	return level


## The defaults in the file at `path`, or null after printing why when the
## file is missing or rejected. A level is not flown with a guessed default:
## the data file is where the default lives (ARC-4).
static func load_defaults(path: String = DEFAULTS_FILE) -> LevelDefaults:
	if not FileAccess.file_exists(path):
		print("Meltdown: level defaults %s rejected (file not found)" % path)
		return null
	var defaults: LevelDefaults = LevelDefaults.parse_json(FileAccess.get_file_as_string(path))
	if defaults.error != "":
		print("Meltdown: level defaults %s rejected (%s)" % [path, defaults.error])
		return null
	return defaults


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
