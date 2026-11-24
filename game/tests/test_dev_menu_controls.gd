extends RefCounted

## The dev menu's Controls entry (#778, PLT-5, ARC-3, ARC-4, MP-2): the entry
## and what confirming it returns; the saved choice and its file; an argument
## beats the saved file; a switch lets go of a held grip and prints the line
## again from the menu; a switch while the menu is open leaves the session's
## state hash equal to neutral input for the same ticks.

const SCRATCH_DIR: String = "user://test_dev_menu_controls"
const FRAME: float = 1.0 / 72.0

var NONE: PackedStringArray = PackedStringArray()


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


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


## Presses `action` once on `model`: down for a frame, then up.
static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


## Gripped-scheme values with both grips pulled and both hands tracked.
static func _gripping() -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_grip"] = 1.0
	values["right_grip"] = 1.0
	values[ControllerSampler.POSES] = {"left": Transform3D.IDENTITY, "right": Transform3D.IDENTITY}
	return values


func test_the_controls_entry_steps_through_the_schemes_and_returns_the_choice() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if spec.error != "" or spec.schemes != ControlSchemeSwitch.SCHEMES:
		return "the shipped file's schemes: %s %s" % [spec.schemes, spec.error]
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.open("centre", "", ControlSchemeSwitch.GRIPPED)
	var model: DevMenuModel = menu.model
	DevMenuWalk.select(model, DevMenuSpec.KIND_CONTROLS, func(action: String) -> void:
		menu.update({action: true})
		menu.update({}))
	var opened_on: String = model.scheme()
	menu.update({DevMenuModel.RIGHT: true})
	menu.update({})
	var shown: Array[String] = menu.texts()
	var result: String = menu.update({DevMenuModel.CONFIRM: true})
	menu.free()
	if opened_on != ControlSchemeSwitch.GRIPPED:
		return "the menu opened on %s, not the scheme in use" % opened_on
	if not shown.has("> Controls: < thumbsticks >"):
		return "the menu shows %s" % [shown]
	if result != "controls:thumbsticks":
		return "confirming returned \"%s\"" % result
	# Left wraps the other way, and an unknown scheme opens on the first.
	var plain: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	plain.open("centre", "", "joystick")
	DevMenuWalk.select(plain, DevMenuSpec.KIND_CONTROLS, func(action: String) -> void: _tap(plain, action))
	_tap(plain, DevMenuModel.LEFT)
	var left: String = _tap(plain, DevMenuModel.CONFIRM)
	return "" if left == "controls:gripped" else "left then confirm returned \"%s\"" % left


func test_a_bad_schemes_list_is_named() -> String:
	var good: Dictionary = {"entries": [{"kind": "controls", "label": "Controls"}], "corners": ["a"]}
	for bad: Variant in [[], ["joystick"], ["gripped", "gripped"], [3], "gripped"]:
		var data: Dictionary = good.duplicate()
		data["schemes"] = bad
		var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
		if spec.error == "" or not spec.error.contains("scheme"):
			return "schemes %s gave error \"%s\"" % [bad, spec.error]
	var without: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(good))
	if without.error != "" or without.schemes != ControlSchemeSwitch.SCHEMES:
		return "a file without schemes gave %s \"%s\"" % [without.schemes, without.error]
	return ""


func test_the_choice_is_saved_and_loaded() -> String:
	var path: String = _scratch("saved.json")
	var store: ControlsChoice = ControlsChoice.new(path)
	if store.load_saved() != "" or not store.warnings.is_empty():
		return "no file gave \"%s\", warnings %s" % [store.load_saved(), store.warnings]
	if not store.save(ControlSchemeSwitch.GRIPPED):
		return "saving gripped failed: %s" % store.warnings
	if ControlsChoice.new(path).load_saved() != ControlSchemeSwitch.GRIPPED:
		return "a new store read \"%s\"" % ControlsChoice.new(path).load_saved()
	if store.save("joystick") or ControlsChoice.new(path).load_saved() != ControlSchemeSwitch.GRIPPED:
		return "an unknown scheme was saved"
	for text: String in ["not json", '{"scheme":"joystick"}', '{"scheme":"gripped","x":1}']:
		_write(path, text)
		var broken: ControlsChoice = ControlsChoice.new(path)
		if broken.load_saved() != "" or broken.warnings.size() != 1:
			return "file %s gave a scheme or no warning: %s" % [text, broken.warnings]
	return ""


func test_an_argument_beats_the_saved_choice_and_no_file_means_thumbsticks() -> String:
	var path: String = _scratch("launch.json")
	var none: ControlSchemeSwitch = ControlSchemeSwitch.from_launch(path)
	if none.scheme != ControlSchemeSwitch.THUMBSTICKS:
		return "no file and no switch flew %s" % none.scheme
	ControlsChoice.new(path).save(ControlSchemeSwitch.GRIPPED)
	if ControlSchemeSwitch.from_launch(path).scheme != ControlSchemeSwitch.GRIPPED:
		return "the saved choice was not used without a switch"
	var cases: Array = [
		[PackedStringArray(["--controls=thumbsticks"]), "", ControlSchemeSwitch.THUMBSTICKS],
		[NONE, "thumbsticks", ControlSchemeSwitch.THUMBSTICKS],
		[NONE, "", ControlSchemeSwitch.GRIPPED],
		[PackedStringArray(["--controls=joystick"]), "", ControlSchemeSwitch.GRIPPED],
	]
	for case: Array in cases:
		var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(case[0], case[1])
		chosen.use_saved(ControlsChoice.new(path).load_saved())
		if chosen.scheme != case[2]:
			return "%s / \"%s\" with gripped saved flew %s" % [case[0], case[1], chosen.scheme]
	return ""


func test_a_switch_lets_go_of_a_held_grip_and_prints_the_line_from_the_menu() -> String:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(NONE, "gripped")
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	chosen.map_values(mapping, _gripping())
	if not chosen.gripped.holds("right") or not chosen.gripped.holds("left"):
		return "the grips were not held before the switch"
	if not chosen.switch_to(ControlSchemeSwitch.THUMBSTICKS, true):
		return "the switch was refused: %s" % chosen.warnings
	if chosen.gripped.holds("right") or chosen.gripped.holds("left"):
		return "a grip was still held after the switch"
	var expected: String = 'MELTDOWN_CONTROLS {"scheme":"thumbsticks","left_handed":true,"invert_pitch":false,"source":"menu"}'
	if chosen.lines.is_empty() or chosen.lines[chosen.lines.size() - 1] != expected:
		return "lines %s, expected the last to be %s" % [chosen.lines, expected]
	if chosen.switch_to("joystick", false) or chosen.scheme != ControlSchemeSwitch.THUMBSTICKS:
		return "an unknown scheme changed the scheme to %s" % chosen.scheme
	return ""


func test_choosing_through_the_wiring_switches_saves_and_keeps_the_menu_open() -> String:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(NONE, "gripped")
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	chosen.map_values(mapping, _gripping())
	var wiring: DevMenuWiring = DevMenuWiring.new(chosen, mapping)
	var path: String = _scratch("wiring.json")
	wiring.controls_store = ControlsChoice.new(path)
	wiring.corner_store = PanelCorner.new(_scratch("panel.json"))
	wiring.attach(null, null, LevelStart.new(), Callable(), null, null,
		DevMenu.new(DevMenuSpec.load_file(), []))
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), 1.0)
	wiring.read(_values(), 1.2)
	var opened_on: String = wiring.menu.model.scheme()
	var now: float = 1.3
	now = DevMenuWalk.select_wired(wiring, DevMenuSpec.KIND_CONTROLS, now)
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	wiring.read(right, now)
	wiring.read(_values(), now + FRAME)
	wiring.read(_values({"right_button_lower": true}), now + 0.1)
	var result: String = ""
	if opened_on != ControlSchemeSwitch.GRIPPED:
		result = "the menu opened on %s" % opened_on
	elif chosen.scheme != ControlSchemeSwitch.THUMBSTICKS or chosen.gripped.holds("right"):
		result = "the scheme is %s, grip held %s" % [chosen.scheme, chosen.gripped.holds("right")]
	elif ControlsChoice.new(path).load_saved() != ControlSchemeSwitch.THUMBSTICKS:
		result = "the choice was not saved"
	elif not wiring.is_open():
		result = "the menu closed on a controls choice"
	wiring.menu.free()
	return result


func test_a_switch_with_the_menu_open_leaves_the_state_as_neutral_input() -> String:
	var hashes: Array[int] = []
	var saved: String = _scratch("main.json")
	for switching: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.get_node("XRRig").call("build")
		main.call("_ready")
		var wiring: DevMenuWiring = main.get("dev_menu")
		wiring.controls_store = ControlsChoice.new(saved)
		wiring.corner_store = PanelCorner.new(_scratch("main_panel.json"))
		var scheme: ControlSchemeSwitch = main.get("scheme")
		scheme.scheme = ControlSchemeSwitch.THUMBSTICKS
		# Both runs open the menu; one also walks to Controls and picks gripped.
		main.call("apply_controls", _values({ControllerSampler.MENU_BUTTON: true}))
		main.call("apply_controls", _values())
		var frames: Array[Dictionary] = []
		var walked: Array[int] = [0]
		if switching:
			DevMenuWalk.select(wiring.menu.model, DevMenuSpec.KIND_CONTROLS, func(action: String) -> void:
				var push: Dictionary = _gripping()
				var wanted: Dictionary = DevMenuWalk.controls(action)
				push["right_stick"] = wanted["right_stick"]
				push["buttons"] = wanted["buttons"]
				for values: Dictionary in [push, _gripping()]:
					main.call("apply_controls", values)
					main.call("advance_frame", FRAME)
				walked[0] += 2)
		for step: int in 24 - walked[0]:
			frames.append(_gripping() if switching else _values())
		var right: Dictionary = _gripping()
		right["right_stick"] = Vector2(1.0, 0.0)
		frames.append(right if switching else _values())
		frames.append(_values())
		var confirm: Dictionary = _gripping()
		confirm["buttons"] = {"right_button_lower": true}
		frames.append(confirm if switching else _values())
		for frame: int in 60:
			frames.append(_gripping() if switching else _values())
		for values: Dictionary in frames:
			main.call("apply_controls", values)
			main.call("advance_frame", FRAME)
		var open: bool = wiring.is_open()
		var in_use: String = scheme.scheme
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
		if not open:
			return "the menu closed (switching %s)" % switching
		if switching and in_use != ControlSchemeSwitch.GRIPPED:
			return "the menu did not switch to gripped: %s" % in_use
	if hashes[0] != hashes[1]:
		return "a switch with the menu open let input through: %s" % [hashes]
	return ""
