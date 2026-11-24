extends RefCounted

## The dev menu's Hands and Pitch entries (#790, PLT-5, ARC-3, ARC-4, MP-2):
## the entries and what confirming them returns; the choice saved beside the
## scheme and loaded at start; the labels swap and the line is printed again
## after `hands:left`; a switch while the menu is open leaves the session's
## state hash equal to neutral input for the same ticks.

const SCRATCH_DIR: String = "user://test_dev_menu_hands"
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


static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


static func _select(model: DevMenuModel, kind: String) -> void:
	DevMenuWalk.select(model, kind, func(action: String) -> void: _tap(model, action))


## Walks the wiring's open menu to `kind`, steps it right once and confirms.
static func _choose(wiring: DevMenuWiring, kind: String, at: float) -> float:
	var now: float = at
	now = DevMenuWalk.select_wired(wiring, kind, now)
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	wiring.read(right, now)
	wiring.read(_values(), now + FRAME)
	wiring.read(_values({"right_button_lower": true}), now + 0.1)
	wiring.read(_values(), now + 0.1 + FRAME)
	return now + 0.2


func test_the_shipped_menu_lists_hands_and_pitch_after_controls() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var kinds: Array[String] = []
	for entry: Dictionary in spec.entries:
		kinds.append(str(entry["kind"]))
	var at: int = kinds.find(DevMenuSpec.KIND_CONTROLS)
	if spec.error != "" or at < 0 or kinds.slice(at + 1, at + 3) != [DevMenuSpec.KIND_HANDS,
			DevMenuSpec.KIND_PITCH]:
		return "the shipped entries are %s %s" % [kinds, spec.error]
	var built_in: DevMenuSpec = DevMenuSpec.fallback()
	if not DevMenuSpec.KINDS.has(DevMenuSpec.KIND_HANDS) or built_in.entries.size() != DevMenuSpec.KINDS.size():
		return "the built-in menu lacks the entries"
	return ""


func test_the_hands_entry_steps_and_returns_the_choice() -> String:
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), [])
	menu.open("centre", "", ControlSchemeSwitch.THUMBSTICKS)
	var model: DevMenuModel = menu.model
	DevMenuWalk.select(model, DevMenuSpec.KIND_HANDS, func(action: String) -> void:
		menu.update({action: true})
		menu.update({}))
	var before: Array[String] = menu.texts()
	menu.update({DevMenuModel.RIGHT: true})
	menu.update({})
	var after: Array[String] = menu.texts()
	var result: String = menu.update({DevMenuModel.CONFIRM: true})
	menu.free()
	if not before.has("> Hands: < right-handed >"):
		return "the menu opened with %s" % [before]
	if not after.has("> Hands: < left-handed >"):
		return "after a step right the menu shows %s" % [after]
	if result != "hands:left":
		return "confirming returned \"%s\"" % result
	# Left wraps back; opening left-handed shows it.
	var plain: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	plain.open("centre", "", "", true)
	_select(plain, DevMenuSpec.KIND_HANDS)
	if plain.hands() != "left":
		return "opened left-handed, the entry shows %s" % plain.hands()
	_tap(plain, DevMenuModel.LEFT)
	var back: String = _tap(plain, DevMenuModel.CONFIRM)
	return "" if back == "hands:right" else "left then confirm returned \"%s\"" % back


func test_the_pitch_entry_steps_and_returns_the_choice() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), [])
	model.open("centre", "")
	_select(model, DevMenuSpec.KIND_PITCH)
	if model.pitch_text() != "normal":
		return "the entry opened on %s" % model.pitch_text()
	_tap(model, DevMenuModel.RIGHT)
	var inverted: String = _tap(model, DevMenuModel.CONFIRM)
	_tap(model, DevMenuModel.RIGHT)
	var normal: String = _tap(model, DevMenuModel.CONFIRM)
	if inverted != "pitch:inverted" or normal != "pitch:normal":
		return "confirming returned \"%s\" then \"%s\"" % [inverted, normal]
	var opened: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	opened.open("centre", "", "", false, true)
	return "" if opened.pitch() == "inverted" else "opened inverted, shows %s" % opened.pitch()


func test_hands_and_pitch_are_saved_beside_the_scheme_and_loaded() -> String:
	var path: String = _scratch("saved.json")
	var none: ThumbstickMapping = ControlsChoice.new(path).apply_hands(ThumbstickMapping.new())
	if none.left_handed or none.invert_pitch:
		return "no file gave left-handed %s, inverted %s" % [none.left_handed, none.invert_pitch]
	var store: ControlsChoice = ControlsChoice.new(path)
	store.save(ControlSchemeSwitch.GRIPPED)
	if not store.save_hands(true, true):
		return "saving failed: %s" % store.warnings
	var loaded: ThumbstickMapping = ControlsChoice.new(path).apply_hands(ThumbstickMapping.new())
	if not loaded.left_handed or not loaded.invert_pitch:
		return "loaded left-handed %s, inverted %s" % [loaded.left_handed, loaded.invert_pitch]
	if ControlsChoice.new(path).load_saved() != ControlSchemeSwitch.GRIPPED:
		return "saving the hands lost the scheme"
	store.save(ControlSchemeSwitch.THUMBSTICKS)
	if not ControlsChoice.new(path).apply_hands(ThumbstickMapping.new()).left_handed:
		return "saving the scheme lost the hands"
	_write(path, '{"left_handed":true}')
	var only_hands: ControlsChoice = ControlsChoice.new(path)
	if only_hands.load_saved() != "" or not only_hands.warnings.is_empty():
		return "a file without a scheme gave \"%s\", warnings %s" % [
			only_hands.load_saved(), only_hands.warnings]
	for text: String in ['{"left_handed":"yes"}', '{"invert_pitch":1}', "{}"]:
		_write(path, text)
		var broken: ControlsChoice = ControlsChoice.new(path)
		var mapping: ThumbstickMapping = broken.apply_hands(ThumbstickMapping.new())
		if mapping.left_handed or mapping.invert_pitch or broken.warnings.size() != 1:
			return "file %s set the mapping or gave no warning: %s" % [text, broken.warnings]
	return ""


func test_choosing_left_handed_swaps_the_labels_saves_and_prints_the_line() -> String:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(NONE, "gripped")
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var right_labels: Dictionary = ControlLabels.for_mapping(mapping)
	var wiring: DevMenuWiring = DevMenuWiring.new(chosen, mapping)
	var path: String = _scratch("wiring.json")
	wiring.controls_store = ControlsChoice.new(path)
	wiring.corner_store = PanelCorner.new(_scratch("panel.json"))
	wiring.attach(null, null, LevelStart.new(), Callable(), null, null,
		DevMenu.new(DevMenuSpec.load_file(), []))
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), 1.0)
	wiring.read(_values(), 1.2)
	var now: float = _choose(wiring, DevMenuSpec.KIND_HANDS, 1.3)
	var after_hands: Dictionary = ControlLabels.for_mapping(mapping)
	var hands_line: String = chosen.lines[chosen.lines.size() - 1] if not chosen.lines.is_empty() else ""
	_choose(wiring, DevMenuSpec.KIND_PITCH, now)
	var open: bool = wiring.is_open()
	var pitch_line: String = chosen.lines[chosen.lines.size() - 1] if not chosen.lines.is_empty() else ""
	wiring.menu.free()
	if not mapping.left_handed or not mapping.invert_pitch:
		return "the mapping is left-handed %s, inverted %s" % [mapping.left_handed, mapping.invert_pitch]
	if after_hands == right_labels:
		return "the labels did not change after hands:left"
	if after_hands != ControlLabels.for_layout(mapping.layout, true, false):
		return "the labels are not the left-handed ones"
	var expected: String = 'MELTDOWN_CONTROLS {"scheme":"gripped","left_handed":true,"invert_pitch":false,"source":"menu"}'
	if hands_line != expected:
		return "after Hands the line was %s, expected %s" % [hands_line, expected]
	if not pitch_line.contains('"left_handed":true,"invert_pitch":true,"source":"menu"'):
		return "after Pitch the line was %s" % pitch_line
	var loaded: ThumbstickMapping = ControlsChoice.new(path).apply_hands(ThumbstickMapping.new())
	if not loaded.left_handed or not loaded.invert_pitch:
		return "the choice was not saved"
	if not open:
		return "the menu closed on a hands or pitch choice"
	return ""


func test_a_hands_switch_with_the_menu_open_leaves_the_state_as_neutral_input() -> String:
	var hashes: Array[int] = []
	for switching: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.get_node("XRRig").call("build")
		main.call("_ready")
		var wiring: DevMenuWiring = main.get("dev_menu")
		wiring.controls_store = ControlsChoice.new(_scratch("main.json"))
		wiring.corner_store = PanelCorner.new(_scratch("main_panel.json"))
		var mapping: ThumbstickMapping = main.get("mapping")
		mapping.left_handed = false
		mapping.invert_pitch = false
		main.call("apply_controls", _values({ControllerSampler.MENU_BUTTON: true}))
		main.call("apply_controls", _values())
		var frames: Array[Dictionary] = []
		if switching:
			DevMenuWalk.select(wiring.menu.model, DevMenuSpec.KIND_HANDS)
		var right: Dictionary = _values()
		right["right_stick"] = Vector2(1.0, 0.0)
		frames.append(right if switching else _values())
		frames.append(_values())
		frames.append(_values({"right_button_lower": true}) if switching else _values())
		frames.append(_values())
		for frame: int in 60:
			var push: Dictionary = _values()
			push["left_stick"] = Vector2(0.0, 1.0)
			push["right_stick"] = Vector2(0.0, 1.0)
			frames.append(push)
		for values: Dictionary in frames:
			main.call("apply_controls", values)
			main.call("advance_frame", FRAME)
		var open: bool = wiring.is_open()
		var left: bool = mapping.left_handed
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
		if not open:
			return "the menu closed (switching %s)" % switching
		if switching and not left:
			return "the menu did not switch to left-handed"
	if hashes[0] != hashes[1]:
		return "a switch with the menu open let input through: %s" % [hashes]
	return ""
