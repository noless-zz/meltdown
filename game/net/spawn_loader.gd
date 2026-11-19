class_name SpawnLoader
extends RefCounted

## Reads the data files a session starts from: a ship file and its weapons,
## for `LocalSession.load_tuning`, and a level's robot spawn file, the robot
## types it names and the weapon each type fires, for
## `LocalSession.load_spawns`, and the part catalogue every weapon file makes,
## for `LocalSession.load_parts`. Core opens no files (ARC-1), so the reading
## happens here and core gets resolved definitions. Kept out of
## `local_session.gd` so that file stays under its size limit.

## Where the weapons a ship file's loadout names are read from, by id (#189).
const WEAPON_DIR: String = "res://data/weapons/"
## Where the robot types a spawn file names are read from, by id (#228).
const ROBOT_DIR: String = "res://data/robots/"
## Where the weapons robot types fire are read from, by id (#612).
const ROBOT_WEAPON_DIR: String = "res://data/robot_weapons/"


## Reads a ship data file. Returns null, after printing why, when the file is
## missing or rejected, so the caller flies the built-in defaults.
## The weapons its loadout names are read from `weapon_dir` and resolved here,
## since core opens no files. If any of them is missing or rejected, the
## problem is printed and the ship flies unarmed with the file's other values:
## a half-armed ship would hide which weapon broke.
static func load_tuning(path: String, weapon_dir: String = WEAPON_DIR) -> ShipTuning:
	var problem: String = ""
	var tuning: ShipTuning = null
	if not FileAccess.file_exists(path):
		problem = "file not found"
	else:
		tuning = ShipTuning.parse_json(FileAccess.get_file_as_string(path))
		problem = tuning.error
	if problem != "":
		print("Meltdown: ship tuning %s rejected (%s); flying with the built-in defaults" % [path, problem])
		return null
	var texts: Dictionary = {}
	for id: String in tuning.loadout.weapon_ids():
		var weapon_path: String = weapon_dir.path_join(id + ".json")
		if FileAccess.file_exists(weapon_path):
			texts[id] = FileAccess.get_file_as_string(weapon_path)
	var weapon_problem: String = tuning.loadout.resolve(texts)
	if weapon_problem != "":
		print("Meltdown: ship loadout in %s rejected (%s); flying unarmed" % [path, weapon_problem])
	return tuning


## The spawns in the file at `path`, with their types read from `robot_dir`
## and their weapons from `weapon_dir`. Returns an empty list, after printing
## why, when the spawn file or any robot type is missing or rejected: a level
## with some robots silently missing would hide which file broke. A missing or
## rejected weapon file only disarms the robots that fire it, after printing
## why, since the level still makes sense with an unarmed robot (CMB-3, #269).
static func load_spawns(path: String, robot_dir: String, weapon_dir: String) -> Array[RobotSpawn]:
	var none: Array[RobotSpawn] = []
	if not FileAccess.file_exists(path):
		print("Meltdown: robot spawns %s rejected (file not found); no robots" % path)
		return none
	return resolve_list(RobotSpawnList.parse_json(FileAccess.get_file_as_string(path)),
		path, robot_dir, weapon_dir)


## The spawns of `list`, already parsed from the file at `source`, resolved
## and armed as `load_spawns` does. A level file carries its spawns inline, so
## the main scene's level switch (#291) resolves them here, the same way as the
## test tunnel's spawn file (#269). `source` only names the file in messages.
static func resolve_list(list: RobotSpawnList, source: String, robot_dir: String,
		weapon_dir: String) -> Array[RobotSpawn]:
	var none: Array[RobotSpawn] = []
	var problem: String = list.error
	if problem == "":
		var texts: Dictionary = {}
		for id: String in list.ids():
			var robot_path: String = robot_dir.path_join(id + ".json")
			if FileAccess.file_exists(robot_path):
				texts[id] = FileAccess.get_file_as_string(robot_path)
		problem = list.resolve(texts)
	if problem != "":
		print("Meltdown: robot spawns %s rejected (%s); no robots" % [source, problem])
		return none
	arm(list.spawns, weapon_dir)
	return list.spawns


## Gives each spawn the weapon its type names, read from `weapon_dir`. The
## file name comes from `RobotDef.weapon_path()`, so the data folder can be
## swapped in tests. Each file is read once; robots of one type share the
## parsed weapon, as they share their `RobotDef`, since neither is changed
## after it is read.
static func arm(spawns: Array[RobotSpawn], weapon_dir: String) -> void:
	var resolved: Dictionary[String, WeaponDef] = {}
	var reported: Dictionary[String, bool] = {}
	for spawn: RobotSpawn in spawns:
		var weapon_path: String = weapon_dir.path_join(spawn.def.weapon_path().get_file())
		if not resolved.has(weapon_path) and not reported.has(weapon_path):
			var problem: String = ""
			if not FileAccess.file_exists(weapon_path):
				problem = "file not found"
			else:
				var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(weapon_path))
				problem = weapon.error
				if problem == "":
					resolved[weapon_path] = weapon
			if problem != "":
				reported[weapon_path] = true
				print("Meltdown: weapon %s for robot type %s rejected (%s); it spawns unarmed"
					% [weapon_path, spawn.id, problem])
		spawn.weapon = resolved.get(weapon_path, null)


## The part catalogue: every weapon data file in `weapon_dir`, keyed by its
## file name without `.json`, the id robots drop it under (`RobotDef.salvage`)
## and a loadout names it by (SLV-1, ARC-4, #320). See `parts_from_files`.
static func load_parts(weapon_dir: String = WEAPON_DIR) -> Dictionary[String, WeaponDef]:
	return parts_from_files(weapon_dir, DirAccess.get_files_at(weapon_dir))


## The part catalogue from the files `names` in `weapon_dir`. The names are
## sorted first: directory listing order is not promised to match from one
## machine to the next, and the catalogue's order must not depend on it, or
## two machines would start the same session differently (ARC-1, MP-2, #381).
## A file that is rejected, or whose name is not a valid id, is left out after
## printing why: one broken weapon should not stop every other part from
## slotting.
static func parts_from_files(weapon_dir: String, names: PackedStringArray) -> Dictionary[String, WeaponDef]:
	var parts: Dictionary[String, WeaponDef] = {}
	var files: PackedStringArray = names.duplicate()
	files.sort()
	for file: String in files:
		if file.get_extension() != "json":
			continue
		var id: String = file.get_basename()
		var problem: String = ShipLoadout.check_id("part id", id)
		var weapon: WeaponDef = null
		if problem == "":
			weapon = WeaponDef.parse_json(FileAccess.get_file_as_string(weapon_dir.path_join(file)))
			problem = weapon.error
		if problem != "":
			print("Meltdown: part %s rejected (%s); it cannot be slotted"
				% [weapon_dir.path_join(file), problem])
			continue
		parts[id] = weapon
	return parts
