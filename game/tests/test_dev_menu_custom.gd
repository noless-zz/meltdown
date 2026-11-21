extends RefCounted

## The dev menu's Comfort entry reaches the custom comfort mode (#837, CMF-1,
## CMF-4, CMF-6, ARC-3): with an accepted custom file it steps 1, 2, 3, 4,
## Custom and wraps, without one it stays 1 to 4; the custom choice reads the
## file's `custom_text` and returns `comfort:5`, applied through
## `ComfortWiring.set_preset` and saved like the preset button's change; it
## opens on Custom when that mode is active; and the state hash is unchanged.

const SCRATCH_DIR: String = "user://test_dev_menu_custom"
const CUSTOM: int = ComfortPresetFiles.CUSTOM_NUMBER
const GOOD_FILE: String = "{\"base\": 3, \"display_name\": \"Mine\"}"
const FRAME: float = 1.0 / 72.0
const MAIN_FRAME: float = 1.0 / 90.0


static func _scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


## A comfort wiring reading its custom file from `text` ("" for none).
static func _comfort(text: String, name: String) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.custom_path = _scratch(name)
	if text != "":
		var file: FileAccess = FileAccess.open(comfort.custom_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	return comfort


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


static func _wiring(comfort: ComfortWiring) -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), comfort)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


## Opens the wiring's menu with a tap of the menu button and highlights Comfort.
static func _open_on_comfort(wiring: DevMenuWiring) -> void:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), 10.0)
	wiring.read(_values(), 10.2)
	while wiring.menu.model.kind() != DevMenuSpec.KIND_COMFORT:
		_tap(wiring.menu.model, DevMenuModel.DOWN)


## The numbers the entry shows stepping right `steps` times from preset 1.
static func _stepped(custom_base: int, steps: int) -> Array[int]:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.open("centre", "", "", false, false, 1, true, custom_base)
	while model.kind() != DevMenuSpec.KIND_COMFORT:
		_tap(model, DevMenuModel.DOWN)
	var seen: Array[int] = [model.comfort_number()]
	for step: int in steps:
		_tap(model, DevMenuModel.RIGHT)
		seen.append(model.comfort_number())
	return seen


func test_with_a_custom_file_the_entry_steps_through_custom_and_wraps() -> String:
	var seen: Array[int] = _stepped(3, 6)
	if seen != [1, 2, 3, 4, CUSTOM, 1, 2]:
		return "with a custom file the entry showed %s" % str(seen)
	return ""


func test_without_a_custom_file_the_entry_stays_on_the_four_presets() -> String:
	var seen: Array[int] = _stepped(0, 5)
	if seen != [1, 2, 3, 4, 1, 2]:
		return "without a custom file the entry showed %s" % str(seen)
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.open("centre", "", "", false, false, CUSTOM, true, 0)
	return "" if model.comfort_number() == 1 else "custom without a file opened on %d" % model.comfort_number()


func test_left_from_preset_1_reaches_custom_and_a_confirms_it() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.open("centre", "", "", false, false, 1, true, 2)
	while model.kind() != DevMenuSpec.KIND_COMFORT:
		_tap(model, DevMenuModel.DOWN)
	_tap(model, DevMenuModel.LEFT)
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	return "" if confirmed == "comfort:%d" % CUSTOM else "confirming custom returned \"%s\"" % confirmed


func test_the_custom_label_comes_from_the_file() -> String:
	var shipped: DevMenuSpec = DevMenuSpec.load_file()
	if shipped.error != "" or shipped.custom_text != "Custom (base {base})":
		return "the shipped custom text is \"%s\" (%s)" % [shipped.custom_text, shipped.error]
	var text: String = FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE)
	var spec: DevMenuSpec = DevMenuSpec.parse(text.replace("Custom (base {base})", "Own, from {base}"))
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.open("centre", "", "", false, false, CUSTOM, true, 3)
	var line: String = ""
	for shown: String in menu.texts():
		if shown.contains("Comfort"):
			line = shown
	menu.free()
	if spec.error != "" or line != "Comfort: < Own, from 3 >":
		return "the entry reads \"%s\" (%s)" % [line, spec.error]
	var empty: DevMenuSpec = DevMenuSpec.parse(text.replace("Custom (base {base})", " "))
	return "" if empty.error.contains("custom_text") else "an empty custom text was accepted"


func test_the_wiring_opens_on_custom_when_it_is_active() -> String:
	var comfort: ComfortWiring = _comfort(GOOD_FILE, "active.json")
	comfort.set_preset(CUSTOM)
	var wiring: DevMenuWiring = _wiring(comfort)
	_open_on_comfort(wiring)
	var number: int = wiring.menu.model.comfort_number()
	var text: String = wiring.menu.model.comfort_text()
	wiring.menu.free()
	if number != CUSTOM or text != "Custom (base 3)":
		return "in the custom mode the entry opened on %d \"%s\"" % [number, text]
	return ""


func test_the_wiring_offers_custom_only_with_an_accepted_file() -> String:
	var problem: String = ""
	for case: Array in [["", "none.json", 0], ["{\"base\": 9}", "bad.json", 0],
			[GOOD_FILE, "good.json", 3]]:
		var wiring: DevMenuWiring = _wiring(_comfort(case[0], case[1]))
		_open_on_comfort(wiring)
		if wiring.menu.model.custom_base != case[2] and problem == "":
			problem = "%s offered custom base %d" % [case[1], wiring.menu.model.custom_base]
		wiring.menu.free()
	return problem


func test_a_confirmed_custom_choice_is_applied_and_saved_like_the_button_s() -> String:
	var path: String = _scratch("choice.json")
	var comfort: ComfortWiring = _comfort(GOOD_FILE, "saved.json")
	var flight: FlightTestWiring = FlightTestWiring.new()
	flight.choice_path = path
	flight.begin(FlightTestWiring.Start.SAVED, comfort, Callable(comfort, "set_preset"))
	comfort.set_preset(1)
	var wiring: DevMenuWiring = _wiring(comfort)
	_open_on_comfort(wiring)
	_tap(wiring.menu.model, DevMenuModel.LEFT)
	wiring.apply(_tap(wiring.menu.model, DevMenuModel.CONFIRM))
	flight.update(FRAME, false)
	var saved: ComfortChoice = ComfortChoice.new()
	saved.load_from(path)
	var problem: String = ""
	if comfort.number != CUSTOM or comfort.preset != comfort.custom().preset:
		problem = "the menu left preset %d active, expected custom" % comfort.number
	elif saved.preset() != CUSTOM:
		problem = "the saved preset is %d, expected custom" % saved.preset()
	elif not wiring.is_open():
		problem = "the menu closed after the custom choice"
	wiring.menu.free()
	return problem


func _main_hash(choose_custom: bool) -> int:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var comfort: ComfortWiring = main.get("comfort")
	var input: ShipInput = ShipInput.from_floats(Vector3(0.3, 0.1, -1.0), Vector3(0.0, 0.4, 0.1))
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in 90:
		if i == 30 and choose_custom:
			comfort.custom_path = _scratch("main.json")
			var file: FileAccess = FileAccess.open(comfort.custom_path, FileAccess.WRITE)
			file.store_string(GOOD_FILE)
			file.close()
			comfort.set("_custom", null)
			(main.get("dev_menu") as DevMenuWiring).apply("comfort:%d" % CUSTOM)
		main.call("advance_frame", MAIN_FRAME)
	var state_hash: int = (main.get("session") as LocalSession).sim.state_hash()
	var custom_on: bool = comfort.number == CUSTOM
	main.free()
	return state_hash if custom_on == choose_custom else -1


func test_choosing_custom_leaves_the_simulation_alone() -> String:
	var plain: int = _main_hash(false)
	var custom: int = _main_hash(true)
	if custom == -1:
		return "the menu did not switch the main scene to the custom mode"
	return "" if custom == plain else "the custom choice changed the state hash"
