class_name RunShip
extends RefCounted

## The ship each run level flies (#1057, CRF-4, CMB-1, CRW-1): the ship file,
## the pilot's fitting and the crew's benefits, combined by `RunStartShip.build`
## as the hub's launch combines them, so a crafted and fitted upgrade is felt in
## the next run. `RunWiring` holds one; `LevelStart` asks it for the tuning of
## the run's current level only, so a single level flown with `--level` or
## `--seed`, the test tunnel and the dev menu's levels keep the plain ship file
## and their replays never move.
##
## Nothing here stops a run: a fitting that no longer checks out, a part file or
## a crew role that cannot be read is left out with a note, and each note is
## logged once with `LOG_PREFIX`. A built ship that is still rejected flies the
## ship file instead.
##
## The tuning it returns goes into the session's replay as every tuning does:
## the replay's `tuning` line carries every feel value and its `weapon` lines
## every resolved weapon, so a run level's replay rebuilds the same ship
## (ARC-2) with no new replay line. Utility modules are not in the replay, and
## need not be: they change the view and aim assistance, never the sim (ARC-3).
##
## It sits beside `main.gd`, as `RunWiring` does, because it reads `meta/` data
## and hands a core `ShipTuning` to the `net/` session.

const LOG_PREFIX: String = "[meltdown run]"
const SHIP_FILE: String = "res://data/ships/default_ship.json"

## Where the pilot's fitting is read at each run level; null flies no fitting.
var fittings: FittingStore = null
## False flies the plain ship file on run levels too: acceptance run steps that
## name no scratch stores keep it off, so their pinned hashes stand.
var enabled: bool = true
## The ship file read; tests may point it elsewhere.
var ship_path: String = SHIP_FILE
## Where upgrade, weapon and part files are read; tests may point them elsewhere.
var upgrades_dir: String = UpgradeTree.UPGRADES_DIR
var weapon_dir: String = LocalSession.WEAPON_DIR
var parts_dir: String = ShipPartDef.PARTS_DIR
## Every note logged so far, in order; each is logged only the first time.
var notes: Array[String] = []


## The tuning a run level flies with `profile`'s crafted upgrades and crew and
## the `roles` they are read with. The plain ship file's tuning when `enabled`
## is off, and null, as `LocalSession.load_tuning` gives, when the ship file
## itself is rejected (the session then flies the built-in defaults).
func tuning_for(profile: Profile, roles: CrewRoles) -> ShipTuning:
	if not enabled:
		return LocalSession.load_tuning(ship_path, weapon_dir)
	var text: String = _read(ship_path)
	var json: JSON = JSON.new()
	if text == "" or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return LocalSession.load_tuning(ship_path, weapon_dir)
	var fitting: Fitting = fittings.load_fitting() if fittings != null else null
	var tree: UpgradeTree = UpgradeTree.parse(upgrade_texts(upgrades_dir))
	var found: Array[String] = []
	var ship: Dictionary = RunStartShip.build(json.data, fitting, tree, profile, roles, found, parts_dir)
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(ship, "", false, true))
	var problem: String = tuning.error
	if problem == "":
		problem = tuning.loadout.resolve(_weapon_texts(tuning.loadout.weapon_ids()))
	if problem != "":
		found.append("the built ship was rejected, the ship file flies: %s" % problem)
		tuning = LocalSession.load_tuning(ship_path, weapon_dir)
	for note: String in found:
		_note(note)
	return tuning


## The text of every `.json` file in `dir` by file name, as `UpgradeTree.parse`
## takes them; empty when the folder cannot be read.
static func upgrade_texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


func _weapon_texts(ids: Array[String]) -> Dictionary:
	var texts: Dictionary = {}
	for id: String in ids:
		var path: String = weapon_dir.path_join(id + ".json")
		if FileAccess.file_exists(path):
			texts[id] = FileAccess.get_file_as_string(path)
	return texts


func _note(note: String) -> void:
	if notes.has(note):
		return
	notes.append(note)
	print("%s %s" % [LOG_PREFIX, note])


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
