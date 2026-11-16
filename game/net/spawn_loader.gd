class_name SpawnLoader
extends RefCounted

## Reads the data files a session starts from: a ship file and its weapons,
## for `LocalSession.load_tuning`, and a level's robot spawn file, the robot
## types it names and the weapon each type fires, for
## `LocalSession.load_spawns`. Core opens no files (ARC-1), so the reading
## happens here and core gets resolved definitions. Kept out of
## `local_session.gd` so that file stays under its size limit.

## Where the weapons a ship file's loadout names are read from, by id (#189).
const WEAPON_DIR: String = "res://data/weapons/"
## Where the robot types a spawn file names are read from, by id (#228).
const ROBOT_DIR: String = "res://data/robots/"


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
	var list: RobotSpawnList = RobotSpawnList.parse_json(FileAccess.get_file_as_string(path))
	var problem: String = list.error
	if problem == "":
		var texts: Dictionary = {}
		for id: String in list.ids():
			var robot_path: String = robot_dir.path_join(id + ".json")
			if FileAccess.file_exists(robot_path):
				texts[id] = FileAccess.get_file_as_string(robot_path)
		problem = list.resolve(texts)
	if problem != "":
		print("Meltdown: robot spawns %s rejected (%s); no robots" % [path, problem])
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
