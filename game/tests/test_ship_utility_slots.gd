extends RefCounted

## Utility slots from the ship data file (#929, CRF-5, CMB-8, ARC-4, ARC-2);
## look-aim is the first known module (#1042).

const DEFAULT_SHIP: String = "res://data/ships/default_ship.json"
const WEAPON_DIR: String = "res://data/weapons/"


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_SHIP)) as Dictionary


static func _parse(data: Dictionary) -> ShipTuning:
	return ShipTuning.parse_json(JSON.stringify(data))


static func _with_utility(slots: Variant, modules: Variant) -> ShipTuning:
	var data: Dictionary = _ship_data()
	data["utility_slots"] = slots
	(data["loadout"] as Dictionary)["utility"] = modules
	return _parse(data)


static func _resolved(tuning: ShipTuning) -> ShipLoadout:
	var texts: Dictionary = {}
	for id: String in tuning.loadout.weapon_ids():
		texts[id] = FileAccess.get_file_as_string(WEAPON_DIR + id + ".json")
	tuning.loadout.resolve(texts)
	return tuning.loadout


func test_shipped_ship_has_two_empty_utility_slots() -> String:
	var tuning: ShipTuning = _parse(_ship_data())
	if tuning.error != "":
		return "default ship rejected: " + tuning.error
	if tuning.utility_slots != 2 or tuning.loadout.utility_slots != 2:
		return "utility slots %d, loadout %d" % [tuning.utility_slots, tuning.loadout.utility_slots]
	if not tuning.loadout.utility_ids.is_empty():
		return "shipped modules %s" % [tuning.loadout.utility_ids]
	return ""


func test_equip_gives_the_ship_its_empty_utility_slots() -> String:
	var ship: ShipState = ShipState.new()
	_resolved(_parse(_ship_data())).equip(ship)
	if ship.utility_slots != (["", ""] as Array[String]):
		return "ship utility slots %s" % [ship.utility_slots]
	if ship.primary_slots[0] == null:
		return "equipping utility slots dropped the weapon"
	return ""


func test_ship_file_without_utility_keys_has_none() -> String:
	var data: Dictionary = _ship_data()
	data.erase("utility_slots")
	(data["loadout"] as Dictionary).erase("utility")
	var tuning: ShipTuning = _parse(data)
	if tuning.error != "":
		return "rejected: " + tuning.error
	var ship: ShipState = ShipState.new()
	tuning.loadout.equip(ship)
	if tuning.utility_slots != 0 or not ship.utility_slots.is_empty():
		return "slots %d, ship %s" % [tuning.utility_slots, ship.utility_slots]
	return ""


func test_utility_slot_errors_name_the_key() -> String:
	var cases: Array = [
		["two", "utility_slots"], [1.5, "utility_slots"], [-1, "utility_slots"],
		[5, "utility_slots"], [true, "utility_slots"],
	]
	for case: Array in cases:
		var error: String = _with_utility(case[0], []).error
		if error.find("\"%s\"" % case[1]) < 0:
			return "utility_slots %s gave \"%s\"" % [case[0], error]
	return ""


func test_utility_module_errors_name_the_field() -> String:
	var cases: Array = [
		["look_aim", "loadout.utility"],
		[[3], "loadout.utility[0]"],
		[["Bad Id"], "loadout.utility[0]"],
		[[""], "loadout.utility[0]"],
	]
	for case: Array in cases:
		var error: String = _with_utility(2, case[0]).error
		if error.find("\"%s\"" % case[1]) < 0:
			return "utility %s gave \"%s\"" % [case[0], error]
	return ""


func test_look_aim_wide_radar_and_mine_scanner_are_the_only_known_modules() -> String:
	var known: Array[String] = [ShipLoadout.LOOK_AIM_MODULE, ShipLoadout.WIDE_RADAR_MODULE,
			ShipLoadout.MINE_SCANNER_MODULE]
	if ShipLoadout.UTILITY_MODULE_KINDS != known:
		return "module kinds are %s" % [ShipLoadout.UTILITY_MODULE_KINDS]
	for id: String in ["aim_assist", "deep_sonar", "x"]:
		var error: String = _with_utility(2, [id]).error
		if error.find("\"loadout.utility[0]\"") < 0 or error.find(id) < 0:
			return "module %s gave \"%s\"" % [id, error]
	return ""


func test_a_ship_file_with_the_look_aim_module_loads() -> String:
	var tuning: ShipTuning = _with_utility(2, ["look_aim"])
	if tuning.error != "":
		return "look_aim refused: " + tuning.error
	if tuning.loadout.utility_ids != ([ShipLoadout.LOOK_AIM_MODULE] as Array[String]):
		return "utility ids %s" % [tuning.loadout.utility_ids]
	var ship: ShipState = ShipState.new()
	_resolved(tuning).equip(ship)
	if ship.utility_slots != (["look_aim", ""] as Array[String]):
		return "equipped utility slots %s" % [ship.utility_slots]
	var second: String = _with_utility(2, ["look_aim", "deep_sonar"]).error
	if second.find("\"loadout.utility[1]\"") < 0:
		return "a second, unknown module gave \"%s\"" % second
	return ""


func test_more_modules_than_slots_is_an_error() -> String:
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.utility_ids.assign(["a", "b", "c"])
	loadout.utility_slots = 2
	var error: String = loadout.check_utility_count()
	if error.find("\"loadout.utility\"") < 0 or error.find("\"utility_slots\"") < 0:
		return "three modules in two slots gave \"%s\"" % error
	loadout.utility_slots = 3
	if loadout.check_utility_count() != "":
		return "three modules in three slots rejected"
	# Through the file: no slots and one module, before the module is even judged.
	var data: Dictionary = _ship_data()
	data["utility_slots"] = 0
	var tuning: ShipTuning = _parse(data)
	if tuning.error != "":
		return "zero slots and no modules rejected: " + tuning.error
	return ""


func test_failed_utility_parse_keeps_defaults() -> String:
	var tuning: ShipTuning = _with_utility(9, [])
	if tuning.error == "":
		return "nine slots accepted"
	if tuning.utility_slots != 0 or tuning.loadout.utility_slots != 0:
		return "a rejected file left %d slots" % tuning.utility_slots
	return ""


func test_empty_utility_slots_keep_the_ship_hash() -> String:
	var bare: ShipState = ShipState.new()
	var fitted: ShipState = ShipState.new()
	_resolved(_parse(_ship_data())).equip(fitted)
	var armed: ShipState = ShipState.new()
	var no_utility: Dictionary = _ship_data()
	no_utility.erase("utility_slots")
	(no_utility["loadout"] as Dictionary).erase("utility")
	_resolved(_parse(no_utility)).equip(armed)
	if fitted.state_hash() != armed.state_hash():
		return "two empty utility slots changed an armed ship's hash"
	var empty: ShipState = ShipState.new()
	empty.utility_slots.assign(["", ""])
	if empty.state_hash() != bare.state_hash():
		return "empty utility slots changed a bare ship's hash"
	return ""


func test_a_fitted_module_joins_the_hash() -> String:
	# The hash must see a fitted module, or a desync would hide (MP-2).
	var empty: ShipState = ShipState.new()
	empty.utility_slots.assign(["", ""])
	var fitted: ShipState = ShipState.new()
	fitted.utility_slots.assign(["look_aim", ""])
	var other_slot: ShipState = ShipState.new()
	other_slot.utility_slots.assign(["", "look_aim"])
	if fitted.state_hash() == empty.state_hash():
		return "a fitted module left the hash unchanged"
	if fitted.state_hash() == other_slot.state_hash():
		return "the same module in another slot hashed alike"
	return ""


func test_sim_equip_with_the_shipped_file_keeps_the_sim_hash() -> String:
	var with_slots: Sim = Sim.new(929, 2)
	with_slots.equip(_resolved(_parse(_ship_data())))
	var data: Dictionary = _ship_data()
	data.erase("utility_slots")
	(data["loadout"] as Dictionary).erase("utility")
	var without: Sim = Sim.new(929, 2)
	without.equip(_resolved(_parse(data)))
	if with_slots.ships[0].utility_slots.size() != 2:
		return "sim ships got %s" % [with_slots.ships[0].utility_slots]
	for i: int in 60:
		var inputs: Array[ShipInput] = [
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 60, 0), false, false, i % 3 == 0),
			ShipInput.new(Vector3i(200, 0, -500), Vector3i.ZERO, i % 20 < 10, false, false)]
		with_slots.step(inputs)
		without.step(inputs)
	if with_slots.state_hash() != without.state_hash():
		return "hash %d with empty utility slots, %d without" % [with_slots.state_hash(), without.state_hash()]
	return ""


func test_shipped_replays_keep_their_pinned_hashes() -> String:
	# None of them carries a utility module, so knowing look_aim changes no run
	# (#1042). Replays a suite flies on a generated level pin the hash of that
	# level's session, which their m3 and m4 steps check; here every replay is
	# read, and the box-world ones are flown.
	var dir: String = "res://acceptance/replays"
	var on_levels: Array[String] = _replays_flown_on_levels()
	var checked: int = 0
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".replay"):
			continue
		var path: String = dir.path_join(file)
		var replay: Replay = Replay.load_file(path)
		if replay.error != "":
			return "%s: %s" % [file, replay.error]
		if replay.loadout != null and not replay.loadout.utility_ids.is_empty():
			return "%s carries utility modules %s" % [file, replay.loadout.utility_ids]
		if replay.expected_hash == Replay.NO_HASH or on_levels.has(path):
			continue
		var sim: Sim = replay.run()
		if sim == null:
			return "%s: %s" % [file, replay.run_error]
		if sim.state_hash() != replay.expected_hash:
			return "%s ends at hash %d, pinned %d" % [file, sim.state_hash(), replay.expected_hash]
		checked += 1
	if checked == 0:
		return "no shipped replay was flown"
	return ""


## Replay paths of suite steps that fly a generated level (a `seed` or `run` key, or `next_replay`).
static func _replays_flown_on_levels() -> Array[String]:
	var paths: Array[String] = []
	var suites: String = "res://acceptance/suites"
	for file: String in DirAccess.get_files_at(suites):
		if not file.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(suites.path_join(file)))
		var steps: Variant = data.get("steps", []) if data is Dictionary else data
		if not steps is Array:
			continue
		for step: Variant in steps:
			if step is Dictionary and (step.has("seed") or step.has("run")) and step.has("replay"):
				paths.append(str(step["replay"]))
			if step is Dictionary and step.has("next_replay"):  # A run's next level (#1065).
				paths.append(str(step["next_replay"]))
	return paths
