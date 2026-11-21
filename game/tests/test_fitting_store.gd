extends RefCounted

## The fitting on disk beside the profile (#1031, CRF-4, CMB-1, NAM-1): saved
## through a temporary file and a rename, a damaged or newer file empties the
## fitting without being touched, and a stale fitting is trimmed to what this
## profile and ship can fly.

const DIR: String = "user://test_fitting_store"
const SHIP_PATH: String = "res://data/ships/default_ship.json"


func _fresh_store() -> FittingStore:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: FittingStore = FittingStore.new(DIR + "/meltdown_fitting.json")
	_cleanup(store)
	return store


func _cleanup(store: FittingStore) -> void:
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())


func _write(file_path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _tree() -> UpgradeTree:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	return UpgradeTree.parse(texts)


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func _fitting(primary: Array[String], utility: Array[String] = []) -> Fitting:
	var fitting: Fitting = Fitting.new()
	fitting.primary = primary
	fitting.utility = utility
	return fitting


func test_the_default_file_uses_the_codename() -> String:
	var path: String = FittingStore.new().path
	return "" if path == "user://meltdown_fitting.json" else "default path %s" % path


func test_a_missing_file_gives_an_empty_fitting() -> String:
	var store: FittingStore = _fresh_store()
	var fitting: Fitting = store.load_fitting()
	_cleanup(store)
	if not fitting.is_empty() or store.locked:
		return "fitting %s, locked %s" % [fitting.to_json(), store.locked]
	return ""


func test_save_and_load_give_the_same_json() -> String:
	var store: FittingStore = _fresh_store()
	var fitting: Fitting = _fitting(["needle_gun", "slug_thrower"], ["", "mine_scanner"])
	if not store.save(fitting):
		_cleanup(store)
		return "save failed: %s" % store.message
	var read: Fitting = FittingStore.new(store.path).load_fitting()
	var temp_left: bool = FileAccess.file_exists(store.temp_path())
	_cleanup(store)
	if read.to_json() != fitting.to_json():
		return "read back %s, saved %s" % [read.to_json(), fitting.to_json()]
	return "the temporary file was left behind" if temp_left else ""


func test_the_file_carries_a_version() -> String:
	var data: Variant = JSON.parse_string(FittingStore.to_file_text(Fitting.new()))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != FittingStore.VERSION:
		return "file text %s" % FittingStore.to_file_text(Fitting.new())
	return ""


func test_a_kill_before_the_rename_keeps_the_old_fitting() -> String:
	var store: FittingStore = _fresh_store()
	var old: Fitting = _fitting(["needle_gun", ""])
	store.save(old)
	var killed: FittingStore = FittingStore.new(store.path)
	killed.stop_before_rename = true
	killed.save(_fitting(["slug_thrower", ""]))
	var temp_written: bool = FileAccess.file_exists(store.temp_path())
	var read: Fitting = FittingStore.new(store.path).load_fitting()
	_cleanup(store)
	if not temp_written:
		return "the simulated kill left no temporary file"
	if read.to_json() != old.to_json():
		return "read %s after the kill, expected the old fitting" % read.to_json()
	return ""


func test_a_temp_file_alone_is_ignored() -> String:
	var store: FittingStore = _fresh_store()
	_write(store.temp_path(), FittingStore.to_file_text(_fitting(["needle_gun", ""])))
	var read: Fitting = store.load_fitting()
	_cleanup(store)
	return "" if read.is_empty() else "read %s from a temporary file" % read.to_json()


func test_a_corrupt_file_loads_empty_and_is_not_deleted() -> String:
	var store: FittingStore = _fresh_store()
	for text: String in ["{ not json", "[]", "{\"version\": 1}", "{\"version\": 1, \"fitting\": {\"primary\": 3}}",
			"{\"version\": \"1\", \"fitting\": {}}", "{\"version\": 1, \"fitting\": {}, \"extra\": 0}"]:
		_write(store.path, text)
		var read: Fitting = store.load_fitting()
		var kept: String = FileAccess.get_file_as_string(store.path)
		if not read.is_empty() or store.message == "" or store.locked:
			_cleanup(store)
			return "%s: fitting %s, message '%s', locked %s" % [text, read.to_json(), store.message, store.locked]
		if kept != text:
			_cleanup(store)
			return "%s: the file changed to %s" % [text, kept]
	_cleanup(store)
	return ""


func test_a_too_new_file_loads_empty_and_is_never_saved_over() -> String:
	var store: FittingStore = _fresh_store()
	var text: String = "{\"version\": 99, \"fitting\": {\"primary\": [\"needle_gun\", \"\"], \"loadouts\": []}}"
	_write(store.path, text)
	var read: Fitting = store.load_fitting()
	var saved: bool = store.save(_fitting(["slug_thrower", ""]))
	var kept: String = FileAccess.get_file_as_string(store.path)
	_cleanup(store)
	if not read.is_empty() or not store.locked:
		return "fitting %s, locked %s" % [read.to_json(), store.locked]
	if saved or kept != text:
		return "saved over a newer file: %s" % kept
	return ""


func test_valid_for_drops_an_uncrafted_upgrade_and_keeps_the_rest() -> String:
	var fitting: Fitting = _fitting(["needle_gun", "arc_lance"])
	var notes: Array[String] = []
	var kept: Fitting = FittingStore.valid_for(fitting, _tree(), ["needle_gun"], _ship_data(), notes)
	if kept.primary != ["needle_gun", ""]:
		return "kept primary %s" % [kept.primary]
	if notes.size() != 1 or not notes[0].contains("arc_lance"):
		return "notes %s" % [notes]
	if fitting.primary != ["needle_gun", "arc_lance"]:
		return "the given fitting was changed"
	return ""


func test_valid_for_keeps_a_valid_fitting_unchanged() -> String:
	var fitting: Fitting = _fitting(["needle_gun", "slug_thrower"])
	var notes: Array[String] = []
	var kept: Fitting = FittingStore.valid_for(fitting, _tree(), ["needle_gun", "slug_thrower"], _ship_data(), notes)
	if kept.to_json() != fitting.to_json() or not notes.is_empty():
		return "kept %s, notes %s" % [kept.to_json(), notes]
	return ""


func test_valid_for_drops_each_refused_slot_with_its_own_line() -> String:
	# An unknown upgrade, a second copy of a fitted one and a utility slot
	# beyond the ship's: each goes, with one note each, and the passing slot stays.
	var data: Dictionary = _ship_data()
	var too_far: Array[String] = []
	too_far.resize(int(data.get(ShipTuning.UTILITY_SLOTS_KEY, 0)) + 1)
	too_far.fill("")
	too_far[too_far.size() - 1] = "mine_scanner"
	var fitting: Fitting = _fitting(["slug_thrower", "slug_thrower"], too_far)
	fitting.secondary = ["gone_upgrade", ""] as Array[String]
	var notes: Array[String] = []
	var kept: Fitting = FittingStore.valid_for(fitting, _tree(), ["slug_thrower", "mine_scanner"], data, notes)
	if kept.primary != ["slug_thrower", ""]:
		return "kept primary %s" % [kept.primary]
	if kept.secondary != ["", ""] or kept.utility.any(func(id: String) -> bool: return id != ""):
		return "kept %s" % kept.to_json()
	if notes.size() != 3:
		return "notes %s" % [notes]
	var reason: String = Fitting.check(kept, _tree(), ["slug_thrower", "mine_scanner"], data)
	return "" if reason == "" else "the trimmed fitting is still refused: %s" % reason
