class_name DevMenuLevels
extends RefCounted

## The dev menu's Level entry (#753): the choices it steps through and the
## seed it shows. Split out of `DevMenuModel` (#821) so the model stays a
## readable size as entries are added; the model forwards the stick and the
## seed buttons here while the Level entry is highlighted.
##
## A choice is the test tunnel, a level file's path, a seed or a fresh random
## pick. `source()` gives it in the form `LevelStart.source` uses. No nodes,
## and nothing here reads or writes the simulation (MP-2, ARC-3).

## The largest seed `LevelSwitch` accepts: `SEED_MAX_DIGITS` nines.
const SEED_MAX: int = 999999999999999999
## Level choices besides the level files.
const CHOICE_TUNNEL: String = "tunnel"
const CHOICE_SEED: String = "seed"
const CHOICE_RANDOM: String = "random"
## What `source()` gives for the random choice: a fresh pick when confirmed.
const RANDOM: String = "random"

## The choices, in order: the tunnel, every level file, seed, random.
## A level file is its path; the others are the `CHOICE_` names.
var choices: Array[String] = []
var index: int = 0
var level_seed: int = 0


func _init(level_paths: Array[String]) -> void:
	choices = [CHOICE_TUNNEL]
	choices.append_array(level_paths)
	choices.append_array([CHOICE_SEED, CHOICE_RANDOM])


## Every level file in `LevelSwitch.LEVEL_DIR` that `LevelSwitch.path_for`
## accepts, sorted: the ones `--level=<name>` can fly.
static func files() -> Array[String]:
	var paths: Array[String] = []
	for file: String in DirAccess.get_files_at(LevelSwitch.LEVEL_DIR):
		if not file.ends_with(LevelSwitch.LEVEL_SUFFIX):
			continue
		var path: String = LevelSwitch.path_for(file.trim_suffix(LevelSwitch.LEVEL_SUFFIX))
		if path != "":
			paths.append(path)
	paths.sort()
	return paths


## Shows the level `source` in use, as `LevelStart.source` holds it.
func open(source: String) -> void:
	index = 0
	if source.begins_with(LevelSwitch.SEED_PREFIX):
		index = choices.find(CHOICE_SEED)
		level_seed = maxi(LevelSwitch.source_seed(source), 0)
	elif choices.has(source):
		index = choices.find(source)


## Steps the choice by `direction`, wrapping.
func step(direction: int) -> void:
	index = posmod(index + direction, choices.size())


func choice() -> String:
	return choices[index]


## The level source the entry would confirm: "" for the test tunnel, a level
## file path, `seed:<n>`, or `RANDOM` for a fresh pick.
func source() -> String:
	match choice():
		CHOICE_TUNNEL:
			return ""
		CHOICE_SEED:
			return LevelSwitch.SEED_PREFIX + str(level_seed)
		CHOICE_RANDOM:
			return RANDOM
	return choice()


## Steps the seed by `amount`, kept within 0..`SEED_MAX`.
func step_seed(amount: int) -> void:
	if amount < 0:
		level_seed = maxi(level_seed + amount, 0)
	else:
		level_seed = SEED_MAX if level_seed > SEED_MAX - amount else level_seed + amount


## The words the entry shows for its choice, from `spec`'s texts.
func text(spec: DevMenuSpec) -> String:
	match choice():
		CHOICE_TUNNEL:
			return spec.tunnel_text
		CHOICE_SEED:
			return spec.seed_text.replace("{seed}", str(level_seed))
		CHOICE_RANDOM:
			return spec.random_text
	return choice().get_file().trim_suffix(LevelSwitch.LEVEL_SUFFIX).to_upper()
