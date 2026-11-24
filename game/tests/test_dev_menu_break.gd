extends RefCounted

## The dev menu's Break reminder entry (#821, CMF-10, PLT-5, ARC-3, CMF-6):
## left / right toggle On and Off with the file's texts, A applies through
## `BreakPromptWiring.set_enabled` and saves it, the menu stays open, the
## entry opens on the reminder's state (also one a launch switch set), the
## shipped file lists it after "Comfort", and switching it leaves the state
## hash alone.

const SCRATCH_DIR: String = "user://test_dev_menu_break"
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
	DevMenuWalk.select(model, kind, func(action: String) -> void: _tap(model, action))


## A break prompt wiring on preset 1 whose choice is saved to a scratch file.
static func _break_prompt(path: String) -> BreakPromptWiring:
	var break_prompt: BreakPromptWiring = BreakPromptWiring.new()
	break_prompt.choice = BreakChoice.new(path)
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.set_preset(1)
	break_prompt.attach(null, comfort)
	return break_prompt


## A menu wiring with no rig, update, level or end screens, switching `break_prompt`.
static func _wiring(break_prompt: BreakPromptWiring) -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), null, break_prompt)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


## Opens the wiring's menu with a tap of the menu button from `at`.
static func _open(wiring: DevMenuWiring, at: float) -> float:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)
	return at + 0.4


## Walks the open menu to the Break reminder entry, pushes the stick right
## once and confirms with A. Returns the clock after the last frame.
static func _toggle_and_apply(wiring: DevMenuWiring, at: float) -> float:
	var now: float = at
	now = DevMenuWalk.select_wired(wiring, DevMenuSpec.KIND_BREAK, now)
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	for values: Dictionary in [right, _values({"right_button_lower": true})]:
		wiring.read(values, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	return now


static func _break_line(menu: DevMenu) -> String:
	return DevMenuWalk.entry_line(menu.model, DevMenuSpec.KIND_BREAK)


static func _done(wiring: DevMenuWiring, break_prompt: BreakPromptWiring) -> void:
	wiring.menu.free()
	if break_prompt != null and break_prompt.prompt != null:
		break_prompt.prompt.free()


func test_left_and_right_toggle_and_confirm_returns_the_choice() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.fallback(), [])
	model.open("centre", "", "", false, false, 1, true)
	_select(model, DevMenuSpec.KIND_BREAK)
	var seen: Array[String] = [model.break_text()]
	_tap(model, DevMenuModel.RIGHT)
	seen.append(model.break_text())
	_tap(model, DevMenuModel.RIGHT)
	seen.append(model.break_text())
	_tap(model, DevMenuModel.LEFT)
	seen.append(model.break_text())
	if seen != ["On", "Off", "On", "Off"]:
		return "right, right, left showed %s" % [seen]
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	if confirmed != "break:off":
		return "confirming Off returned \"%s\"" % confirmed
	_tap(model, DevMenuModel.LEFT)
	confirmed = _tap(model, DevMenuModel.CONFIRM)
	return "" if confirmed == "break:on" else "confirming On returned \"%s\"" % confirmed


func test_the_texts_come_from_the_file() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE))
	data["break_on_text"] = "yes"
	data["break_off_text"] = "no"
	var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	if spec.error != "":
		return "the edited file was rejected: %s" % spec.error
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.open("centre", "", "", false, false, 1, false)
	var off: String = _break_line(menu)
	menu.model.break_on = true
	menu.update({})
	var on: String = _break_line(menu)
	menu.free()
	if off != "Break reminder: < no >" or on != "Break reminder: < yes >":
		return "the entry read \"%s\" and \"%s\"" % [off, on]
	data["break_off_text"] = " "
	var blank: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	return "" if blank.error.contains("break_off_text") else "a blank Off text gave \"%s\"" % blank.error


func test_the_shipped_file_puts_the_entry_after_comfort() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var kinds: Array[String] = []
	for entry: Dictionary in spec.entries:
		kinds.append(str(entry["kind"]))
	var comfort: int = kinds.find(DevMenuSpec.KIND_COMFORT)
	if spec.error != "" or comfort < 0 or kinds.find(DevMenuSpec.KIND_BREAK) != comfort + 1:
		return "the shipped entries are %s (%s)" % [kinds, spec.error]
	if spec.break_on_text != "On" or spec.break_off_text != "Off":
		return "the shipped texts are %s / %s" % [spec.break_on_text, spec.break_off_text]
	var fallback: DevMenuSpec = DevMenuSpec.fallback()
	return "" if fallback.entries.any(func(entry: Dictionary) -> bool: return entry["kind"] == "break") \
		else "the built-in menu has no Break reminder entry"


func test_applying_switches_and_saves_and_keeps_the_menu_open() -> String:
	var path: String = _scratch("choice.json")
	var break_prompt: BreakPromptWiring = _break_prompt(path)
	var wiring: DevMenuWiring = _wiring(break_prompt)
	var now: float = _toggle_and_apply(wiring, _open(wiring, 10.0))
	var problem: String = ""
	if break_prompt.reminder.is_enabled():
		problem = "the reminder is still on after choosing Off"
	elif BreakChoice.new(path).load_saved(true):
		problem = "Off was not saved"
	elif not wiring.is_open():
		problem = "the menu closed after a break reminder choice"
	if problem == "":
		_toggle_and_apply(wiring, now)
		if not break_prompt.reminder.is_enabled() or not BreakChoice.new(path).load_saved(false):
			problem = "choosing On again did not switch it on and save it"
	_done(wiring, break_prompt)
	return problem


func test_the_entry_follows_the_current_choice() -> String:
	var path: String = _scratch("choice.json")
	BreakChoice.new(path).save(false)
	var saved_off: BreakPromptWiring = _break_prompt(path)
	var wiring: DevMenuWiring = _wiring(saved_off)
	_open(wiring, 10.0)
	var line: String = _break_line(wiring.menu)
	_done(wiring, saved_off)
	if line != "Break reminder: < Off >":
		return "with Off saved the entry reads \"%s\"" % line
	# The launch switch: `attach` reads it through `for_launch`; the same call
	# with the argument given decides the reminder here.
	path = _scratch("launch.json")
	var launched: BreakPromptWiring = _break_prompt(path)
	launched.reminder.set_enabled(launched.choice.for_launch(true,
		PackedStringArray(["--break-reminder=off"]), ""))
	wiring = _wiring(launched)
	_open(wiring, 10.0)
	line = _break_line(wiring.menu)
	_done(wiring, launched)
	if line != "Break reminder: < Off >":
		return "after --break-reminder=off the entry reads \"%s\"" % line
	wiring = _wiring(null)
	var none: bool = wiring._break_shown()
	_done(wiring, null)
	return "" if none else "a wiring without a break prompt opened on Off"


func _main(path: String) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	(main.get("break_prompt") as BreakPromptWiring).choice = BreakChoice.new(path)
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, frames: int) -> void:
	var input: ShipInput = ShipInput.from_floats(Vector3(0.3, 0.1, -1.0), Vector3(0.0, 0.4, 0.1))
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", MAIN_FRAME)


func test_switching_leaves_the_state_hash_unchanged() -> String:
	var plain: Node = _main(_scratch("plain.json"))
	_fly(plain, 90)
	var plain_hash: int = (plain.get("session") as LocalSession).sim.state_hash()
	plain.free()
	var path: String = _scratch("main.json")
	var main: Node = _main(path)
	var dev_menu: DevMenuWiring = main.get("dev_menu")
	var wired: bool = dev_menu.break_prompt == main.get("break_prompt")
	_fly(main, 30)
	dev_menu.apply("break:off")
	_fly(main, 30)
	dev_menu.apply("break:on")
	_fly(main, 30)
	var switched_hash: int = (main.get("session") as LocalSession).sim.state_hash()
	main.free()
	if not wired:
		return "main.gd's dev menu does not switch main.gd's break prompt"
	return "" if switched_hash == plain_hash else "switching the reminder changed the state hash"
