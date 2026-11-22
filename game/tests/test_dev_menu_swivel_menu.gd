extends RefCounted

## The dev menu's Swivel chair entry chosen in the menu (#853, CMF-7, CMF-1,
## CMF-6, ARC-3, MP-2): the custom file's value wins and is never written;
## choosing saves, applies and keeps the menu open; and the state hash is
## unchanged. The fixtures are `test_dev_menu_swivel.gd`'s.

const Swivel := preload("res://tests/test_dev_menu_swivel.gd")
const CUSTOM: int = Swivel.CUSTOM
const FRAME: float = Swivel.FRAME
const MAIN_FRAME: float = Swivel.MAIN_FRAME


## A menu wiring switching `comfort`, its choice saved at `path`.
static func _wiring(comfort: ComfortWiring, path: String) -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), comfort)
	wiring.swivel.store = SwivelChoice.new(path)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


## Opens the menu with a tap of the menu button and walks to the Swivel chair entry.
static func _open_on_swivel(wiring: DevMenuWiring, at: float = 10.0) -> float:
	wiring.read(Swivel.idle_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(Swivel.idle_values(), at + 0.2)
	var now: float = at + 0.4
	var down: Dictionary = Swivel.idle_values()
	down["right_stick"] = Vector2(0.0, -1.0)
	while wiring.menu.model.kind() != DevMenuSpec.KIND_SWIVEL:
		wiring.read(down, now)
		wiring.read(Swivel.idle_values(), now + FRAME)
		now += 0.1
	return now


## Pushes the stick right once and confirms with A; returns the clock after.
static func _step_and_apply(wiring: DevMenuWiring, at: float) -> float:
	var now: float = at
	var right: Dictionary = Swivel.idle_values()
	right["right_stick"] = Vector2(1.0, 0.0)
	for values: Dictionary in [right, Swivel.idle_values({"right_button_lower": true})]:
		wiring.read(values, now)
		wiring.read(Swivel.idle_values(), now + FRAME)
		now += 0.1
	return now


static func _swivel_line(menu: DevMenu) -> String:
	for line: String in menu.texts():
		if line.contains("Swivel chair"):
			return line
	return ""


func test_the_custom_file_wins_and_is_not_written() -> String:
	var custom_text: String = "{\"base\": 3, \"display_name\": \"Mine\", \"swivel_enabled\": true}"
	var comfort: ComfortWiring = Swivel.new_comfort(custom_text)
	var path: String = Swivel.scratch("custom_wins.json")
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
	var comfort: ComfortWiring = Swivel.new_comfort()
	comfort.set_preset(1)
	var path: String = Swivel.scratch("menu.json")
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
	dev_menu.swivel.store = SwivelChoice.new(Swivel.scratch("main.json"))
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
