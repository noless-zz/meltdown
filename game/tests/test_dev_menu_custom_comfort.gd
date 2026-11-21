extends RefCounted

## The dev menu's Comfort entry reaching the custom mode (#837, CMF-1, CMF-4,
## CMF-6, ARC-3): with an accepted custom file it steps 1, 2, 3, 4, Custom and
## wraps, without one 1 to 4 as before; the custom place shows the file's
## `custom_comfort_text` with its base; A applies it through
## `ComfortWiring.set_preset` and `FlightTestWiring` saves it; the entry opens
## on it while it is active; and the change leaves the state hash alone.

const SCRATCH_DIR: String = "user://test_dev_menu_custom_comfort"
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


static func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A comfort wiring reading its custom file from `custom_text` ("" for none).
static func _comfort(custom_text: String, name: String) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.custom_path = _scratch(name)
	if custom_text != "":
		_write(comfort.custom_path, custom_text)
	return comfort


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


static func _select(model: DevMenuModel, kind: String) -> void:
	while model.kind() != kind:
		_tap(model, DevMenuModel.DOWN)


## A wiring with no rig, update, level or end screens, flying `comfort`.
static func _wiring(comfort: ComfortWiring) -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), comfort)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


## Opens the wiring's menu with a tap of the menu button from `at`.
static func _open(wiring: DevMenuWiring, at: float) -> float:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)
	return at + 0.4


## Walks the open menu to the Comfort entry, pushes the stick right `steps`
## times and confirms with A. Returns the clock after the last frame.
static func _choose(wiring: DevMenuWiring, steps: int, at: float) -> float:
	var now: float = at
	var down: Dictionary = _values()
	down["right_stick"] = Vector2(0.0, -1.0)
	while wiring.menu.model.kind() != DevMenuSpec.KIND_COMFORT:
		wiring.read(down, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	var presses: Array[Dictionary] = []
	for step: int in steps:
		presses.append(right)
	presses.append(_values({"right_button_lower": true}))
	for values: Dictionary in presses:
		wiring.read(values, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	return now


static func _comfort_line(menu: DevMenu) -> String:
	for line: String in menu.texts():
		if line.contains("Comfort"):
			return line
	return ""


## The comfort numbers the model's entry visits stepping right `steps` times from preset 1.
static func _stepped(model: DevMenuModel, steps: int) -> Array[int]:
	model.open("centre", "", "", false, false, 1)
	_select(model, DevMenuSpec.KIND_COMFORT)
	var seen: Array[int] = [model.comfort_number()]
	for step: int in steps:
		_tap(model, DevMenuModel.RIGHT)
		seen.append(model.comfort_number())
	return seen


func test_steps_through_custom_only_with_an_accepted_file() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.set_custom_base(3)
	var with_file: Array[int] = _stepped(model, 6)
	if with_file != [1, 2, 3, 4, CUSTOM, 1, 2]:
		return "with a file the entry visits %s" % [with_file]
	_tap(model, DevMenuModel.LEFT)
	_tap(model, DevMenuModel.LEFT)
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	if confirmed != "comfort:%d" % CUSTOM:
		return "confirming the custom mode returned \"%s\"" % confirmed
	model.set_custom_base(0)
	var without: Array[int] = _stepped(model, 5)
	return "" if without == [1, 2, 3, 4, 1, 2] else "without a file the entry visits %s" % [without]


func test_the_custom_label_comes_from_the_file() -> String:
	var shipped: DevMenuSpec = DevMenuSpec.load_file()
	if shipped.error != "" or shipped.custom_comfort_text != "Custom (base {base})":
		return "the shipped text is \"%s\" (%s)" % [shipped.custom_comfort_text, shipped.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE))
	data["custom_comfort_text"] = "Mine on {base}"
	var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.model.set_custom_base(2)
	menu.open("centre", "", "", false, false, CUSTOM)
	var line: String = _comfort_line(menu)
	menu.free()
	if spec.error != "" or line != "Comfort: < Mine on 2 >":
		return "the entry reads \"%s\" (%s)" % [line, spec.error]
	data["custom_comfort_text"] = 3
	var bad: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	return "" if bad.error.contains("custom_comfort_text") else "a number as the text gave \"%s\"" % bad.error


func test_a_confirmed_custom_mode_is_applied_saved_and_keeps_the_menu_open() -> String:
	var path: String = _scratch("choice.json")
	var comfort: ComfortWiring = _comfort(GOOD_FILE, "good.json")
	var flight: FlightTestWiring = FlightTestWiring.new()
	flight.choice_path = path
	flight.begin(FlightTestWiring.Start.SAVED, comfort, Callable(comfort, "set_preset"))
	comfort.set_preset(4)
	var wiring: DevMenuWiring = _wiring(comfort)
	_choose(wiring, 1, _open(wiring, 10.0))
	flight.update(FRAME, false)
	var saved: ComfortChoice = ComfortChoice.new()
	saved.load_from(path)
	var line: String = _comfort_line(wiring.menu)
	var problem: String = ""
	if comfort.number != CUSTOM or comfort.preset != comfort.custom().preset:
		problem = "the menu left preset %d active, expected the custom mode" % comfort.number
	elif saved.preset() != CUSTOM:
		problem = "the saved preset is %d, expected the custom mode" % saved.preset()
	elif not wiring.is_open():
		problem = "the menu closed after choosing the custom mode"
	elif line != "> Comfort: < Custom (base 3) >":
		problem = "the entry reads \"%s\"" % line
	wiring.menu.free()
	return problem


func test_the_entry_opens_on_the_custom_mode_while_it_is_active() -> String:
	var comfort: ComfortWiring = _comfort(GOOD_FILE, "good.json")
	comfort.set_preset(CUSTOM)
	var wiring: DevMenuWiring = _wiring(comfort)
	_open(wiring, 10.0)
	var number: int = wiring.menu.model.comfort_number()
	var line: String = _comfort_line(wiring.menu)
	wiring.menu.free()
	if number != CUSTOM or line != "Comfort: < Custom (base 3) >":
		return "in the custom mode the menu opened on %d, reading \"%s\"" % [number, line]
	# Without an accepted file the custom mode cannot be active, and the entry
	# stays on 1 to 4 even when asked to open on it.
	var none: ComfortWiring = _comfort("{\"base\": 9}", "bad.json")
	wiring = _wiring(none)
	_open(wiring, 10.0)
	var model: DevMenuModel = wiring.menu.model
	model.open("centre", "", "", false, false, CUSTOM)
	var fallback: int = model.comfort_number()
	wiring.menu.free()
	if none.custom_available() or none.number == CUSTOM:
		return "a rejected custom file left the custom mode available"
	return "" if fallback == 1 else "a rejected file opened on %d" % fallback


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var comfort: ComfortWiring = main.get("comfort")
	comfort.custom_path = _scratch("main_custom.json")
	_write(comfort.custom_path, GOOD_FILE)
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, frames: int) -> void:
	var input: ShipInput = ShipInput.from_floats(Vector3(0.3, 0.1, -1.0), Vector3(0.0, 0.4, 0.1))
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", MAIN_FRAME)


func test_choosing_the_custom_mode_leaves_the_state_hash_unchanged() -> String:
	var plain: Node = _main()
	_fly(plain, 90)
	var plain_hash: int = (plain.get("session") as LocalSession).sim.state_hash()
	plain.free()
	var main: Node = _main()
	_fly(main, 30)
	(main.get("dev_menu") as DevMenuWiring).apply("comfort:%d" % CUSTOM)
	_fly(main, 60)
	var number: int = (main.get("comfort") as ComfortWiring).number
	var switched_hash: int = (main.get("session") as LocalSession).sim.state_hash()
	main.free()
	if number != CUSTOM:
		return "the menu's choice left preset %d active" % number
	return "" if switched_hash == plain_hash else "choosing the custom mode changed the state hash"
