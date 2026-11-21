extends RefCounted

## The dev menu's Swivel chair entry (#853, CMF-7, CMF-1, CMF-6, ARC-3, MP-2):
## the saved file is parsed and a bad one warned by path and treated as off;
## left / right step On and Off and wrap; the choice is applied to presets 1
## to 4 at once and remembered at start; the custom file's value wins and is
## never written; the status panel's tag follows; switching inside the menu
## adds no yaw; and the state hash is unchanged.

const SCRATCH_DIR: String = "user://test_dev_menu_swivel"
const CUSTOM: int = ComfortPresetFiles.CUSTOM_NUMBER
const FRAME: float = 1.0 / 72.0
const MAIN_FRAME: float = 1.0 / 90.0

var _now_s: float = 0.0


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


## A comfort wiring whose custom file holds `custom_text` ("" for none).
static func _comfort(custom_text: String = "") -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.custom_path = _scratch("custom.json")
	if custom_text != "":
		_write(comfort.custom_path, custom_text)
	return comfort


## A menu wiring switching `comfort`, its choice saved at `path`.
static func _wiring(comfort: ComfortWiring, path: String) -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), comfort)
	wiring.swivel.store = SwivelChoice.new(path)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


## Opens the menu with a tap of the menu button and walks to the Swivel chair entry.
static func _open_on_swivel(wiring: DevMenuWiring, at: float = 10.0) -> float:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)
	var now: float = at + 0.4
	var down: Dictionary = _values()
	down["right_stick"] = Vector2(0.0, -1.0)
	while wiring.menu.model.kind() != DevMenuSpec.KIND_SWIVEL:
		wiring.read(down, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	return now


## Pushes the stick right once and confirms with A; returns the clock after.
static func _step_and_apply(wiring: DevMenuWiring, at: float) -> float:
	var now: float = at
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	for values: Dictionary in [right, _values({"right_button_lower": true})]:
		wiring.read(values, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	return now


static func _swivel_line(menu: DevMenu) -> String:
	for line: String in menu.texts():
		if line.contains("Swivel chair"):
			return line
	return ""


func test_default_path_and_round_trip() -> String:
	if SwivelChoice.DEFAULT_PATH != "user://meltdown_swivel.json":
		return "default path is %s" % SwivelChoice.DEFAULT_PATH
	var path: String = _scratch("round_trip.json")
	if SwivelChoice.new(path).load_saved():
		return "no file did not read as off"
	for enabled: bool in [true, false]:
		if not SwivelChoice.new(path).save(enabled):
			return "could not save %s" % enabled
		if SwivelChoice.new(path).load_saved() != enabled:
			return "saved %s, read back the other" % enabled
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data != {"enabled": enabled}:
			return "the file holds %s, expected only enabled" % str(data)
	return ""


func test_a_bad_file_is_warned_by_path_and_off() -> String:
	var path: String = _scratch("bad.json")
	for text: String in ["not json", "[true]", "{\"enabled\": 1}", "{\"enabled\": true, \"gain\": 2}",
			"{\"on\": true}"]:
		_write(path, text)
		var choice: SwivelChoice = SwivelChoice.new(path)
		if choice.load_saved():
			return "%s read as on" % text
		if choice.warnings.size() != 1 or not choice.warnings[0].contains(path):
			return "%s warned %s, expected one warning naming %s" % [text, choice.warnings, path]
	return ""


func test_left_and_right_step_and_wrap_and_confirm_returns_the_choice() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.open("centre", "")
	model.set_swivel(false, false)
	while model.kind() != DevMenuSpec.KIND_SWIVEL:
		_tap(model, DevMenuModel.DOWN)
	var seen: Array[String] = [model.swivel_text()]
	for action: String in [DevMenuModel.RIGHT, DevMenuModel.RIGHT, DevMenuModel.LEFT]:
		_tap(model, action)
		seen.append(model.swivel_text())
	if seen != ["Off", "On", "Off", "On"]:
		return "right, right, left showed %s" % [seen]
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	if confirmed != "swivel:on":
		return "confirming On returned \"%s\"" % confirmed
	_tap(model, DevMenuModel.LEFT)
	confirmed = _tap(model, DevMenuModel.CONFIRM)
	if confirmed != "swivel:off":
		return "confirming Off returned \"%s\"" % confirmed
	model.set_swivel(true, true)
	_tap(model, DevMenuModel.RIGHT)
	if model.swivel_text() != "On (custom file)":
		return "a locked entry stepped to \"%s\"" % model.swivel_text()
	return ""


func test_the_shipped_file_lists_the_entry_and_its_texts() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var kinds: Array[String] = []
	for entry: Dictionary in spec.entries:
		kinds.append(str(entry["kind"]))
	if spec.error != "" or not kinds.has(DevMenuSpec.KIND_SWIVEL):
		return "the shipped entries are %s (%s)" % [kinds, spec.error]
	if [spec.swivel_on_text, spec.swivel_off_text, spec.swivel_custom_text] != ["On", "Off", "(custom file)"]:
		return "the shipped texts are %s / %s / %s" % [spec.swivel_on_text, spec.swivel_off_text,
			spec.swivel_custom_text]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE))
	data["swivel_on_text"] = "turning"
	var edited: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	if edited.error != "" or edited.swivel_on_text != "turning":
		return "an edited On text was not read (%s)" % edited.error
	return "" if DevMenuSpec.fallback().entries.any(
		func(entry: Dictionary) -> bool: return entry["kind"] == "swivel") \
		else "the built-in menu has no Swivel chair entry"


func test_the_choice_applies_to_presets_one_to_four() -> String:
	var comfort: ComfortWiring = _comfort()
	for on: bool in [true, false]:
		comfort.set_swivel_choice(on)
		for number: int in [1, 2, 3, 4]:
			comfort.set_preset(number)
			var shipped: ComfortPreset = ComfortPresetFiles.load_number(number)
			if comfort.preset.swivel_enabled != on or comfort.swivel.yaw.enabled != on:
				return "preset %d with the choice %s has swivel %s" % [number, on, comfort.preset.swivel_enabled]
			if shipped.swivel_enabled:
				return "applying the choice changed the shipped preset %d file" % number
			var kept: bool = comfort.preset.swivel_dead_zone_deg == shipped.swivel_dead_zone_deg \
				and comfort.preset.swivel_gain_per_deg == shipped.swivel_gain_per_deg \
				and comfort.preset.swivel_max_input == shipped.swivel_max_input \
				and comfort.preset.swivel_follow_deg_per_s == shipped.swivel_follow_deg_per_s \
				and comfort.preset.display_name == shipped.display_name
			if not kept:
				return "preset %d lost its own swivel values or name" % number
	comfort.set_preset(2)
	comfort.set_swivel_choice(true)  # At once, on the active preset.
	return "" if comfort.preset.swivel_enabled and comfort.number == 2 \
		else "choosing On did not switch the active preset's swivel on"


func test_the_custom_file_wins_and_is_not_written() -> String:
	var custom_text: String = "{\"base\": 3, \"display_name\": \"Mine\", \"swivel_enabled\": true}"
	var comfort: ComfortWiring = _comfort(custom_text)
	var path: String = _scratch("custom_wins.json")
	var wiring: DevMenuWiring = _wiring(comfort, path)
	comfort.set_preset(CUSTOM)
	comfort.set_swivel_choice(false)
	if not comfort.preset.swivel_enabled:
		wiring.menu.free()
		return "the choice Off overrode the custom file's swivel_enabled"
	var now: float = _open_on_swivel(wiring)
	var line: String = _swivel_line(wiring.menu)
	_step_and_apply(wiring, now)
	var after: String = _swivel_line(wiring.menu)
	wiring.menu.free()
	if line != "> Swivel chair: < On (custom file) >" or after != line:
		return "in the custom mode the entry read \"%s\" then \"%s\"" % [line, after]
	if FileAccess.file_exists(path):
		return "a choice in the custom mode was saved"
	if FileAccess.get_file_as_string(comfort.custom_path) != custom_text:
		return "the menu wrote over the custom file"
	return "" if comfort.preset.swivel_enabled else "the custom file's swivel was switched off"


func test_choosing_saves_applies_and_keeps_the_menu_open() -> String:
	var comfort: ComfortWiring = _comfort()
	comfort.set_preset(1)
	var path: String = _scratch("menu.json")
	var wiring: DevMenuWiring = _wiring(comfort, path)
	var now: float = _open_on_swivel(wiring)
	var before: String = _swivel_line(wiring.menu)
	now = _step_and_apply(wiring, now)
	var problem: String = ""
	if before != "> Swivel chair: < Off >":
		problem = "the entry opened as \"%s\"" % before
	elif not comfort.preset.swivel_enabled or not SwivelChoice.new(path).load_saved():
		problem = "choosing On did not switch preset 1's swivel on and save it"
	elif not wiring.is_open():
		problem = "the menu closed after a swivel choice"
	if problem == "":
		_step_and_apply(wiring, now)
		if comfort.preset.swivel_enabled or SwivelChoice.new(path).load_saved():
			problem = "choosing Off again did not switch it off and save it"
	wiring.menu.free()
	return problem


func test_the_choice_is_remembered_at_start() -> String:
	var path: String = _scratch("start.json")
	SwivelChoice.new(path).save(true)
	var comfort: ComfortWiring = _comfort()
	var entry: DevMenuSwivel = DevMenuSwivel.new(comfort)
	entry.store = SwivelChoice.new(path)
	entry.start()
	if not comfort.preset.swivel_enabled:
		return "On saved, but the start preset's swivel is off"
	comfort.set_preset(4)  # A saved comfort choice applied after start.
	if not comfort.preset.swivel_enabled:
		return "the saved choice was lost by a later preset change"
	_write(path, "{broken")
	var broken: ComfortWiring = _comfort()
	entry = DevMenuSwivel.new(broken)
	entry.store = SwivelChoice.new(path)
	entry.start()
	return "" if not broken.preset.swivel_enabled else "a broken file switched the swivel on"


func test_the_status_panel_tag_follows_the_choice() -> String:
	var comfort: ComfortWiring = _comfort()
	comfort.set_preset(2)
	var panel: StatusPanel = StatusPanel.new()
	comfort.set_swivel_choice(true)
	RigViews.show_swivel(panel, comfort)
	var on: bool = panel.preset_row.swivel
	comfort.set_swivel_choice(false)
	RigViews.show_swivel(panel, comfort)
	var off: bool = panel.preset_row.swivel
	panel.free()
	return "" if on and not off else "the panel's swivel tag read %s then %s" % [on, off]


func test_switching_on_in_the_menu_adds_no_yaw_and_recentres_on_close() -> String:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	var comfort: ComfortWiring = _comfort()
	comfort.swivel.attach(rig, HeadRecentre.new())
	comfort.swivel.clock = func() -> float: return _now_s
	comfort.swivel.head_trusted = func() -> bool: return true
	_now_s += MAIN_FRAME
	comfort.swivel.added(ShipInput.new(), true)  # The menu is open.
	comfort.set_swivel_choice(true)
	camera.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3.ZERO)
	_now_s += MAIN_FRAME
	var held: ShipInput = comfort.swivel.added(ShipInput.new(), true)
	_now_s += MAIN_FRAME
	var closed: ShipInput = comfort.swivel.added(ShipInput.new(), false)
	camera.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-150.0)), Vector3.ZERO)
	_now_s += MAIN_FRAME
	var turned: ShipInput = comfort.swivel.added(ShipInput.new(), false)
	rig.free()
	if held.turn_q != Vector3i.ZERO or closed.turn_q != Vector3i.ZERO:
		return "switched on in the menu it turned %s held, %s on close" % [held.turn_q, closed.turn_q]
	return "" if turned.turn_q.y != 0 else "after closing, turning the chair 60 degrees did not turn the ship"


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


func test_switching_leaves_the_state_hash_unchanged() -> String:
	var plain: Node = _main()
	_fly(plain, 90)
	var plain_hash: int = (plain.get("session") as LocalSession).sim.state_hash()
	plain.free()
	var main: Node = _main()
	var dev_menu: DevMenuWiring = main.get("dev_menu")
	var wired: bool = dev_menu.swivel.comfort == main.get("comfort")
	dev_menu.swivel.store = SwivelChoice.new(_scratch("main.json"))
	_fly(main, 30)
	dev_menu.apply("swivel:on")
	_fly(main, 30)
	dev_menu.apply("swivel:off")
	_fly(main, 30)
	var switched_hash: int = (main.get("session") as LocalSession).sim.state_hash()
	main.free()
	if not wired:
		return "main.gd's dev menu does not switch main.gd's comfort presets"
	return "" if switched_hash == plain_hash else "switching the swivel changed the state hash"
