extends RefCounted

## The in-headset development menu, unwired (#753): entries from the data
## file, the level choices, seed stepping, what each confirm returns, presses
## counted once, and no effect on the simulation.

const FRAME: float = 1.0 / 72.0


static func _menu() -> DevMenuModel:
	return DevMenuModel.new(DevMenuSpec.fallback(), ["res://data/levels/g2_level.json"])


## Presses `action` once: down for a frame, then up.
static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


static func _select(model: DevMenuModel, kind: String) -> void:
	DevMenuWalk.select(model, kind, func(action: String) -> void: _tap(model, action))


func test_entries_and_their_order_come_from_the_data_file() -> String:
	var shipped: DevMenuSpec = DevMenuSpec.load_file()
	if shipped.error != "" or shipped.entries.size() != 20:
		return "the shipped file was not read: %s" % shipped.error
	var text: String = JSON.stringify({"entries": [{"kind": "close", "label": "Done"},
		{"kind": "level", "label": "Fly"}], "corners": ["top_left"]})
	var spec: DevMenuSpec = DevMenuSpec.parse(text)
	if spec.error != "" or spec.entries.size() != 2 or spec.entries[0]["kind"] != "close" \
			or spec.entries[1]["label"] != "Fly":
		return "the file's entries were not used in order: %s %s" % [spec.entries, spec.error]
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.open("top_left", "")
	var lines: Array[String] = menu.texts()
	menu.free()
	if lines != ["> Done", "Fly: Test tunnel"]:
		return "the menu shows %s" % [lines]
	var missing: DevMenuSpec = DevMenuSpec.load_file("res://tests/no_such_menu.json")
	var kinds: Array[String] = []
	for entry: Dictionary in missing.entries:
		kinds.append(str(entry["kind"]))
	if kinds != DevMenuSpec.KINDS or missing.error == "":
		return "a missing file gave %s" % [kinds]
	return ""


func test_a_bad_menu_file_is_named() -> String:
	var good_entry: Dictionary = {"kind": "close", "label": "Close"}
	var cases: Dictionary = {
		"unknown key": {"entries": [good_entry], "corners": ["a"], "colour": 1},
		"non-empty list": {"entries": [], "corners": ["a"]},
		"unknown entry kind \"pause\"": {"entries": [{"kind": "pause", "label": "P"}], "corners": ["a"]},
		"given twice": {"entries": [good_entry, good_entry], "corners": ["a"]},
		"needs a non-empty label": {"entries": [{"kind": "close", "label": " "}], "corners": ["a"]},
		"exactly": {"entries": [{"kind": "close"}], "corners": ["a"]},
		"\"corners\" must be": {"entries": [good_entry]},
		"is not a name": {"entries": [good_entry], "corners": ["Top Left"]},
		"\"seed_text\" must be": {"entries": [good_entry], "corners": ["a"], "seed_text": 3},
	}
	for expected: String in cases:
		var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(cases[expected]))
		if not spec.error.contains(expected):
			return "expected '%s', got '%s'" % [expected, spec.error]
	if DevMenuSpec.parse("not json").error == "":
		return "text that is not JSON was accepted"
	return ""


func test_the_seed_steps_by_one_and_ten_within_the_limits() -> String:
	var model: DevMenuModel = _menu()
	model.open("centre", "seed:31")
	_select(model, DevMenuSpec.KIND_LEVEL)
	var seen: Array[int] = []
	for action: String in [DevMenuModel.SEED_UP, DevMenuModel.SEED_UP_FAR, DevMenuModel.SEED_DOWN_FAR]:
		_tap(model, action)
		seen.append(model.levels.level_seed)
	if seen != [32, 42, 32]:
		return "31 stepped +1, +10, -10 gave %s" % [seen]
	model.open("centre", "seed:3")
	_select(model, DevMenuSpec.KIND_LEVEL)
	_tap(model, DevMenuModel.SEED_DOWN_FAR)
	_tap(model, DevMenuModel.SEED_DOWN)
	if model.levels.level_seed != 0:
		return "stepping down from 3 gave %d, not 0" % model.levels.level_seed
	model.open("centre", "seed:999999999999999995")
	_select(model, DevMenuSpec.KIND_LEVEL)
	_tap(model, DevMenuModel.SEED_UP_FAR)
	_tap(model, DevMenuModel.SEED_UP)
	if model.levels.level_seed != DevMenuLevels.SEED_MAX or str(model.levels.level_seed).length() != LevelSwitch.SEED_MAX_DIGITS:
		return "stepping up near the top gave %d" % model.levels.level_seed
	if LevelSwitch.seed_from(str(model.levels.level_seed)) != model.levels.level_seed:
		return "the largest seed is not one LevelSwitch accepts"
	# Away from the seed choice the seed buttons do nothing.
	model.open("centre", "")
	_select(model, DevMenuSpec.KIND_LEVEL)
	var kept: int = model.levels.level_seed
	_tap(model, DevMenuModel.SEED_UP)
	if model.levels.level_seed != kept or model.levels.source() != "":
		return "the seed stepped while the tunnel was chosen"
	return ""


func test_the_level_entry_lists_every_level_file_plus_tunnel_seed_and_random() -> String:
	var files: Array[String] = DevMenuLevels.files()
	var expected: Array[String] = []
	for file: String in DirAccess.get_files_at(LevelSwitch.LEVEL_DIR):
		var path: String = LevelSwitch.path_for(file.trim_suffix(LevelSwitch.LEVEL_SUFFIX))
		if file.ends_with(LevelSwitch.LEVEL_SUFFIX) and path != "":
			expected.append(path)
	expected.sort()
	if files != expected or not files.has("res://data/levels/g2_level.json"):
		return "level files %s, expected %s" % [files, expected]
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), files)
	var choices: Array[String] = [DevMenuLevels.CHOICE_TUNNEL]
	choices.append_array(files)
	choices.append_array([DevMenuLevels.CHOICE_SEED, DevMenuLevels.CHOICE_RANDOM])
	if model.levels.choices != choices:
		return "the choices are %s" % [model.levels.choices]
	return ""


func test_confirming_each_entry_returns_its_result_on_the_press_only() -> String:
	var model: DevMenuModel = _menu()
	model.open("top_left", "")
	_select(model, DevMenuSpec.KIND_CORNER)
	_tap(model, DevMenuModel.RIGHT)
	var corner: String = model.press({DevMenuModel.CONFIRM: true})
	var held: String = model.press({DevMenuModel.CONFIRM: true})
	model.press({})
	if corner != "corner:top_right" or held != "":
		return "corner confirm gave '%s', then held '%s'" % [corner, held]
	_select(model, DevMenuSpec.KIND_LEVEL)
	var sources: Array[String] = []
	for step: int in 4:
		sources.append(_tap(model, DevMenuModel.CONFIRM))
		_tap(model, DevMenuModel.RIGHT)
	if sources != ["level:", "level:res://data/levels/g2_level.json", "level:seed:0", "level:random"]:
		return "level confirms gave %s" % [sources]
	model.open("centre", "seed:31")
	_select(model, DevMenuSpec.KIND_LEVEL)
	if _tap(model, DevMenuModel.CONFIRM) != "level:seed:31":
		return "an open on seed 31 did not confirm seed 31"
	_select(model, DevMenuSpec.KIND_RESTART)
	var restart: String = _tap(model, DevMenuModel.CONFIRM)
	_select(model, DevMenuSpec.KIND_CLOSE)
	var close: String = _tap(model, DevMenuModel.CONFIRM)
	if restart != "restart" or close != "close":
		return "restart gave '%s', close gave '%s'" % [restart, close]
	# Holding down moves one entry, not one per frame.
	model.open("centre", "")
	for frame: int in 5:
		model.press({DevMenuModel.DOWN: true})
	if model.selected != 1:
		return "holding down moved to entry %d" % model.selected
	return ""


func test_a_closed_menu_ignores_input() -> String:
	var menu: DevMenu = DevMenu.new(DevMenuSpec.fallback(), [])
	var result: String = menu.update({DevMenuModel.CONFIRM: true})
	menu.open("centre", "")
	menu.update({})
	var open_result: String = menu.update({DevMenuModel.CONFIRM: true})
	menu.free()
	if result != "" or open_result != "corner:centre":
		return "closed gave '%s', open gave '%s'" % [result, open_result]
	return ""


func test_an_open_menu_leaves_the_simulation_alone() -> String:
	var hashes: Array[int] = []
	for with_menu: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		var menu: DevMenu = DevMenu.new()
		main.add_child(menu)
		if with_menu:
			menu.open("centre", "")
		for frame: int in 60:
			var values: Dictionary = ControllerSampler.idle_values()
			values["buttons"] = {"right_button_lower": frame < 30}
			main.call("apply_controls", values)
			# Every menu action pressed and released in turn, confirms included.
			var action: String = DevMenuModel.ACTIONS[frame % DevMenuModel.ACTIONS.size()]
			menu.update({action: frame % 2 == 0})
			main.call("advance_frame", FRAME)
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
	if hashes[0] != hashes[1]:
		return "the open menu changed the simulation: %s" % [hashes]
	return ""
