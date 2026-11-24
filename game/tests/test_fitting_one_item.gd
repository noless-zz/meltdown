extends RefCounted

## One crafted upgrade is one item (CRF-3, CRF-4, #1336): a fitting never names
## it in two slots, a move takes it from one slot to another in one step, a
## fitting saved before the rule loads with the later slot empty and a warning,
## and the run starts with exactly the fitted loadout.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const DIR: String = "user://test_fitting_one_item"


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _tree() -> UpgradeTree:
	return UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR))


static func _model(crafted: Array[String], fitting: Fitting = Fitting.new()) -> HubModel:
	var profile: Profile = Profile.new()
	profile.crafted = crafted
	return HubModel.create(HubConfig.load_shipped(), profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string("res://data/crew/roles.json")),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)), _tree(), fitting, _ship_data())


func test_check_refuses_one_upgrade_in_two_primary_slots() -> String:
	var fitting: Fitting = Fitting.new()
	fitting.primary = ["needle_gun", "needle_gun"]
	var reason: String = Fitting.check(fitting, _tree(), ["needle_gun"] as Array[String], _ship_data())
	if not reason.contains("already fitted in primary[0]"):
		return "a doubled fitting checked as \"%s\"" % reason
	return ""


func test_check_refuses_one_module_in_two_utility_slots() -> String:
	var fitting: Fitting = Fitting.new()
	fitting.utility = ["look_aim", "look_aim"]
	var reason: String = Fitting.check(fitting, _tree(), ["look_aim"] as Array[String], _ship_data())
	return "" if reason.begins_with("utility[1]") else "a doubled utility checked as \"%s\"" % reason


func test_the_model_refuses_mounting_a_fitted_upgrade_a_second_time() -> String:
	var model: HubModel = _model(["needle_gun"] as Array[String])
	if model.fit("primary[0]", "needle_gun") != "":
		return "the first mount was refused"
	var before: String = model.fitting.to_json()
	var reason: String = model.fit("primary[1]", "needle_gun")
	if reason == "" or model.fitting.to_json() != before:
		return "a second mount gave \"%s\" and left %s" % [reason, model.fitting.to_json()]
	return ""


func test_a_move_takes_the_upgrade_from_its_old_slot_in_one_step() -> String:
	var fitting: Fitting = Fitting.new()
	fitting.primary = ["needle_gun", ""]
	if fitting.slot_of("needle_gun") != "primary[0]":
		return "slot_of gave %s" % fitting.slot_of("needle_gun")
	var reason: String = fitting.move("needle_gun", "primary[1]")
	if reason != "" or fitting.primary != (["", "needle_gun"] as Array[String]):
		return "move gave \"%s\", primary %s" % [reason, fitting.primary]
	return "" if fitting.slot_of("needle_gun") == "primary[1]" else "slot_of after the move is %s" % fitting.slot_of("needle_gun")


func test_a_move_of_an_unfitted_upgrade_or_to_no_slot_changes_nothing() -> String:
	var fitting: Fitting = Fitting.new()
	fitting.primary = ["needle_gun", ""]
	var before: String = fitting.to_json()
	if fitting.move("arc_lance", "primary[1]") == "" or fitting.to_json() != before:
		return "moving an unfitted upgrade passed or changed %s" % fitting.to_json()
	if fitting.move("needle_gun", "primary[7]") == "" or fitting.to_json() != before:
		return "moving to primary[7] passed or changed %s" % fitting.to_json()
	if fitting.move("needle_gun", "primary[0]") != "" or fitting.to_json() != before:
		return "moving to its own slot was refused or changed %s" % fitting.to_json()
	return ""


func test_a_utility_move_keeps_the_list_as_long_as_its_last_used_slot() -> String:
	var fitting: Fitting = Fitting.new()
	fitting.utility = ["", "look_aim"]
	if fitting.move("look_aim", "utility[0]") != "" or fitting.utility != (["look_aim"] as Array[String]):
		return "utility after the move is %s" % [fitting.utility]
	return ""


func test_the_model_move_passes_and_a_refused_move_leaves_the_fitting() -> String:
	var model: HubModel = _model(["needle_gun", "look_aim"] as Array[String])
	if model.fit("primary[0]", "needle_gun") != "" or model.fit("utility[0]", "look_aim") != "":
		return "mounting failed"
	if model.move("primary[1]", "needle_gun") != "" or model.fitting.primary != (["", "needle_gun"] as Array[String]):
		return "the move left primary %s" % [model.fitting.primary]
	var before: String = model.fitting.to_json()
	var reason: String = model.move("primary[0]", "look_aim")  # A module in a weapon slot.
	if reason == "" or model.fitting.to_json() != before:
		return "a wrong-kind move gave \"%s\" and left %s" % [reason, model.fitting.to_json()]
	if model.move("primary[0]", "arc_lance") == "" or model.fitting.to_json() != before:
		return "moving an unfitted upgrade passed"
	return ""


func test_without_doubles_empties_the_later_slot_and_says_which() -> String:
	var fitting: Fitting = Fitting.new()
	fitting.primary = ["needle_gun", "needle_gun"]
	fitting.utility = ["look_aim", "look_aim"]
	var notes: Array[String] = []
	var kept: Fitting = FittingSlots.without_doubles(fitting, notes)
	if kept.primary != (["needle_gun", ""] as Array[String]) or kept.utility != (["look_aim"] as Array[String]):
		return "kept primary %s utility %s" % [kept.primary, kept.utility]
	if notes.size() != 2 or not notes[0].begins_with("primary[1]") or not notes[1].begins_with("utility[1]"):
		return "notes are %s" % [notes]
	if fitting.primary != (["needle_gun", "needle_gun"] as Array[String]):
		return "the original was changed"
	return ""


func test_a_saved_doubled_fitting_loads_with_the_later_slot_empty_and_a_warning() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: FittingStore = FittingStore.new(DIR + "/meltdown_fitting.json")
	var file: FileAccess = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 2, "fitting": {
		"primary": ["needle_gun", "needle_gun"], "secondary": ["", ""], "utility": []}}))
	file.close()
	var loaded: Fitting = store.load_fitting()
	DirAccess.remove_absolute(store.path)
	if loaded.primary != (["needle_gun", ""] as Array[String]):
		return "loaded primary %s" % [loaded.primary]
	if not store.message.contains("primary[1]") or store.locked:
		return "the warning is \"%s\", locked %s" % [store.message, store.locked]
	return ""


func test_a_clean_saved_fitting_loads_without_a_warning() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: FittingStore = FittingStore.new(DIR + "/meltdown_fitting.json")
	var fitting: Fitting = Fitting.new()
	fitting.primary = ["needle_gun", "arc_lance"]
	if not store.save(fitting):
		return store.message
	var loaded: Fitting = store.load_fitting()
	DirAccess.remove_absolute(store.path)
	return "" if loaded.to_json() == fitting.to_json() and store.message == "" else "loaded %s, \"%s\"" % [loaded.to_json(), store.message]


func test_the_run_starts_with_exactly_the_moved_loadout() -> String:
	var model: HubModel = _model(["needle_gun"] as Array[String])
	if model.fit("primary[0]", "needle_gun") != "" or model.move("primary[1]", "needle_gun") != "":
		return "mount or move refused"
	var grants: String = model.tree.get_upgrade("needle_gun").grants
	var stock: Array = _ship_data()[ShipTuning.LOADOUT_KEY]["primary"]
	var loadout: Dictionary = model.launch()
	if loadout.get("primary") != [stock[0], grants]:
		return "launch gave primary %s, expected [%s, %s]" % [loadout.get("primary"), stock[0], grants]
	if loadout != Fitting.loadout(model.fitting, model.tree, model.ship_data):
		return "launch differs from Fitting.loadout"
	return ""
