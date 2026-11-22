extends RefCounted

## The dev menu's Comfort entry (#805, CMF-4, CMF-1, CMF-6, CMF-8, ARC-3):
## it steps and wraps through presets 1 to 4 by name, sits after "Panel
## corner" in the shipped file, applies through `ComfortWiring.set_preset` and
## is saved in `ComfortChoice` like the preset button's change, opens on the
## active preset (also after the button changed it), and leaves the state hash
## and the view exactly as the preset button would.

const SCRATCH_DIR: String = "user://test_dev_menu_comfort"
const FRAME: float = 1.0 / 72.0
const MAIN_FRAME: float = 1.0 / 90.0


static func _scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


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


static func _name(number: int) -> String:
	return ComfortPresetFiles.load_number(number).display_name


static func _comfort() -> ComfortWiring:
	return ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())


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
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	var presses: Array[Dictionary] = []
	while wiring.menu.model.kind() != DevMenuSpec.KIND_COMFORT:
		wiring.read(down, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
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


func test_the_entry_steps_and_wraps_through_the_four_presets_by_name() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.open("centre", "", "", false, false, 1)
	_select(model, DevMenuSpec.KIND_COMFORT)
	var seen: Array[String] = [model.comfort_text()]
	for step: int in 4:
		_tap(model, DevMenuModel.RIGHT)
		seen.append(model.comfort_text())
	var expected: Array[String] = [_name(1), _name(2), _name(3), _name(4), _name(1)]
	if seen != expected:
		return "stepping right showed %s, expected %s" % [seen, expected]
	_tap(model, DevMenuModel.LEFT)
	if model.comfort_number() != 4:
		return "left from preset 1 gave preset %d, expected 4" % model.comfort_number()
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	return "" if confirmed == "comfort:4" else "confirming preset 4 returned \"%s\"" % confirmed


func test_the_shipped_file_puts_comfort_after_the_panel_corner() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var kinds: Array[String] = []
	for entry: Dictionary in spec.entries:
		kinds.append(str(entry["kind"]))
	var corner: int = kinds.find(DevMenuSpec.KIND_CORNER)
	if spec.error != "" or corner < 0 or kinds.find(DevMenuSpec.KIND_COMFORT) != corner + 1:
		return "the shipped entries are %s (%s)" % [kinds, spec.error]
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.open("centre", "", "", false, false, 3)
	var line: String = _comfort_line(menu)
	menu.free()
	return "" if line == "Comfort: < %s >" % _name(3) else "the entry reads \"%s\"" % line


func test_a_confirmed_preset_is_applied_and_saved_like_the_button_s() -> String:
	var path: String = _scratch("choice.json")
	var comfort: ComfortWiring = _comfort()
	var flight: FlightTestWiring = FlightTestWiring.new()
	flight.choice_path = path
	flight.begin(FlightTestWiring.Start.SAVED, comfort, Callable(comfort, "set_preset"))
	var wiring: DevMenuWiring = _wiring(comfort)
	var before: int = comfort.number
	_choose(wiring, 2, _open(wiring, 10.0))
	flight.update(FRAME, false)
	var saved: ComfortChoice = ComfortChoice.new()
	saved.load_from(path)
	var expected: int = posmod(before - 1 + 2, 4) + 1
	var problem: String = ""
	if comfort.number != expected or comfort.preset.display_name != _name(expected):
		problem = "the menu left preset %d active, expected %d" % [comfort.number, expected]
	elif saved.preset() != expected:
		problem = "the saved preset is %d, expected %d" % [saved.preset(), expected]
	elif not wiring.is_open():
		problem = "the menu closed after a comfort choice"
	wiring.menu.free()
	return problem


## Changed straight through the comfort switch, as the X button did until
## decision record 0011 (#1260).
func test_the_entry_opens_on_the_preset_chosen_elsewhere() -> String:
	var comfort: ComfortWiring = _comfort()
	comfort.set_preset(1)
	var wiring: DevMenuWiring = _wiring(comfort)
	comfort.set_preset(comfort.next_number())
	_open(wiring, 10.0)
	var line: String = _comfort_line(wiring.menu)
	var number: int = wiring.menu.model.comfort_number()
	wiring.menu.free()
	if comfort.number != 2 or number != 2:
		return "after the switch chose preset %d the menu opened on %d" % [comfort.number, number]
	return "" if line == "Comfort: < %s >" % _name(2) else "the entry reads \"%s\"" % line


func test_a_wiring_without_comfort_opens_on_the_start_preset() -> String:
	var wiring: DevMenuWiring = _wiring(null)
	var none: int = wiring._comfort_shown()
	wiring.menu.free()
	return "" if none == ComfortPresetFiles.START_NUMBER else "no comfort wiring opened on %d" % none


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, frames: int) -> void:
	var input: ShipInput = ShipInput.from_floats(Vector3(0.3, 0.1, -1.0), Vector3(0.0, 0.4, 0.1))
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", MAIN_FRAME)


## Flies a main scene, changes the preset to the next one mid-flight through
## the menu (`by_menu`) or the comfort switch directly, flies on, and returns its state
## hash and rig transform.
func _flown(by_menu: bool) -> Array:
	var main: Node = _main()
	var comfort: ComfortWiring = main.get("comfort")
	_fly(main, 30)
	if by_menu:
		(main.get("dev_menu") as DevMenuWiring).apply("comfort:%d" % comfort.next_number())
	else:
		comfort.set_preset(comfort.next_number())
	_fly(main, 60)
	var result: Array = [(main.get("session") as LocalSession).sim.state_hash(),
		(main.get_node("XRRig") as Node3D).transform, comfort.number]
	main.free()
	return result


func test_a_menu_change_matches_the_switch_and_leaves_the_simulation_alone() -> String:
	var plain: Node = _main()
	_fly(plain, 90)
	var plain_hash: int = (plain.get("session") as LocalSession).sim.state_hash()
	plain.free()
	var menu: Array = _flown(true)
	var button: Array = _flown(false)
	if menu[2] != button[2]:
		return "the menu chose preset %d, the switch %d" % [menu[2], button[2]]
	if menu[0] != plain_hash or button[0] != plain_hash:
		return "a preset change changed the state hash"
	if not (menu[1] as Transform3D).is_equal_approx(button[1]):
		return "the view after a menu change differs from the switch's"
	return ""
