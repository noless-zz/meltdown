extends RefCounted

## The dev menu's Foveation entry (#871, PRF-1, PRF-2, DEV-6, ARC-3): it sits
## after Pitch with its texts from the file, left / right step Off, 1, 2, 3,
## 1 dynamic, 2 dynamic, 3 dynamic and wrap, choosing applies the setting to
## the interface at once with a `menu` log line, nothing is saved, the flat
## build without an interface still steps and applies nothing, and changing it
## mid-flight leaves the state hash alone. The interface is a stand-in.

const FakeRuntime: GDScript = preload("res://tests/fake_foveation_runtime.gd")
const MAIN_FRAME: float = 1.0 / 72.0
const SHOWN: Array[String] = ["Off", "1", "2", "3", "1 dynamic", "2 dynamic", "3 dynamic"]
var NONE: PackedStringArray = PackedStringArray()


static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


static func _select(model: DevMenuModel, kind: String) -> void:
	DevMenuWalk.select(model, kind, func(action: String) -> void: _tap(model, action))


static func _line(menu: DevMenu) -> String:
	return DevMenuWalk.entry_line(menu.model, DevMenuSpec.KIND_FOVEATION)


## A wiring whose foveation switch runs on `runtime` (none for the flat build).
static func _wiring(chosen: FoveationSwitch, runtime: RefCounted) -> DevMenuWiring:
	if runtime != null:
		chosen.begin(runtime)
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), null, null, null, chosen)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


func test_the_entry_follows_pitch_and_its_texts_come_from_the_file() -> String:
	var shipped: DevMenuSpec = DevMenuSpec.load_file()
	var kinds: Array[String] = []
	for entry: Dictionary in shipped.entries:
		kinds.append(str(entry["kind"]))
	var at: int = kinds.find(DevMenuSpec.KIND_FOVEATION)
	if shipped.error != "" or at < 1 or kinds[at - 1] != DevMenuSpec.KIND_PITCH:
		return "the shipped file lists %s (%s)" % [kinds, shipped.error]
	if str(shipped.entries[at]["label"]) != "Foveation":
		return "the label is \"%s\"" % shipped.entries[at]["label"]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE))
	data["foveation_off_text"] = "none"
	data["foveation_dynamic_text"] = "dyn"
	data["foveation_note_text"] = "[now only]"
	var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	if spec.error != "":
		return "the edited file was rejected: %s" % spec.error
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.open("centre", "")
	var off_line: String = _line(menu)
	menu.model.foveation = Vector2i(2, 1)
	menu.open("centre", "")
	var dynamic_line: String = _line(menu)
	menu.free()
	if off_line != "Foveation: < none [now only] >" or dynamic_line != "Foveation: < 2 dyn [now only] >":
		return "the entry read \"%s\" and \"%s\"" % [off_line, dynamic_line]
	data["foveation_note_text"] = " "
	if not DevMenuSpec.parse(JSON.stringify(data)).error.contains("foveation_note_text"):
		return "a blank note was accepted"
	var fallback: DevMenuSpec = DevMenuSpec.fallback()
	return "" if fallback.entries.any(func(entry: Dictionary) -> bool: return entry["kind"] == "foveation") \
		else "the built-in menu has no Foveation entry"


func test_left_and_right_step_through_every_setting_and_wrap() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), [])
	model.open("centre", "")
	_select(model, DevMenuSpec.KIND_FOVEATION)
	var seen: Array[String] = []
	for i: int in SHOWN.size() + 1:
		seen.append(model.foveation_text().trim_suffix(" (this session)"))
		_tap(model, DevMenuModel.RIGHT)
	if seen != SHOWN + ["Off"]:
		return "stepping right showed %s" % [seen]
	_tap(model, DevMenuModel.LEFT)  # Back to Off, then left wraps to the last.
	_tap(model, DevMenuModel.LEFT)
	if model.foveation_text() != "3 dynamic (this session)":
		return "left from Off showed \"%s\"" % model.foveation_text()
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	if confirmed != "foveation:3:on":
		return "confirming 3 dynamic returned \"%s\"" % confirmed
	model.foveation = Vector2i(0, 1)  # Off with dynamic, from a launch switch: steps as Off.
	_tap(model, DevMenuModel.RIGHT)
	return "" if model.foveation == Vector2i(1, 0) else "Off dynamic stepped to %s" % model.foveation


func test_choosing_applies_at_once_through_the_switch_with_a_menu_line() -> String:
	var runtime: RefCounted = FakeRuntime.new(0, false)
	var chosen: FoveationSwitch = FoveationSwitch.parse(NONE, "", "")
	var wiring: DevMenuWiring = _wiring(chosen, runtime)
	runtime.writes.clear()
	wiring.apply("foveation:2:on")
	if runtime.get("foveation_level") != 2 or not runtime.get("foveation_dynamic"):
		wiring.menu.free()
		return "the interface holds level %s dynamic %s" % [
			runtime.get("foveation_level"), runtime.get("foveation_dynamic")]
	var expected: String = FoveationSwitch.format_line(2, true, FoveationSwitch.SOURCE_MENU)
	if chosen.lines.is_empty() or chosen.lines[-1] != expected:
		wiring.menu.free()
		return "the last line was %s, expected %s" % [chosen.lines, expected]
	if not expected.contains("\"source\":\"menu\""):
		wiring.menu.free()
		return "the menu line names no menu source: %s" % expected
	wiring.apply("foveation:0:off")
	if runtime.get("foveation_level") != 0 or runtime.get("foveation_dynamic"):
		wiring.menu.free()
		return "Off left level %s dynamic %s" % [runtime.get("foveation_level"), runtime.get("foveation_dynamic")]
	wiring.apply("foveation:7:on")  # Not a level: ignored.
	var lines: PackedStringArray = chosen.lines
	wiring.menu.free()
	if runtime.get("foveation_level") != 0 or lines.size() != 3:
		return "a bad result changed the interface or printed: %s" % [lines]
	return ""


func test_the_entry_opens_on_the_setting_in_use() -> String:
	var switched: FoveationSwitch = FoveationSwitch.parse(
		PackedStringArray(["--foveation=3", "--foveation-dynamic=on"]), "", "")
	var on_headset: DevMenuWiring = _wiring(switched, FakeRuntime.new(0, false))
	var model: DevMenuModel = on_headset.menu.model
	on_headset.entry_for(DevMenuSpec.KIND_FOVEATION).show_on(model)
	if model.foveation != Vector2i(3, 1):
		on_headset.menu.free()
		return "with --foveation=3 dynamic the entry opened on %s" % model.foveation
	on_headset.apply("foveation:1:off")
	on_headset.entry_for(DevMenuSpec.KIND_FOVEATION).show_on(model)
	on_headset.menu.free()
	return "" if model.foveation == Vector2i(1, 0) else "after choosing 1 it opened on %s" % model.foveation


func test_nothing_is_saved_so_the_next_launch_starts_off_or_with_its_switch() -> String:
	var before: PackedStringArray = DirAccess.get_files_at("user://")
	var runtime: RefCounted = FakeRuntime.new(0, false)
	var wiring: DevMenuWiring = _wiring(FoveationSwitch.parse(NONE, "", ""), runtime)
	wiring.apply("foveation:3:on")
	wiring.menu.free()
	if DirAccess.get_files_at("user://") != before:
		return "choosing wrote a file: %s -> %s" % [before, DirAccess.get_files_at("user://")]
	var next_launch: FoveationSwitch = FoveationSwitch.parse(NONE, "", "")
	var next_runtime: RefCounted = FakeRuntime.new(0, false)
	next_launch.begin(next_runtime)
	if next_launch.is_switched() or next_runtime.writes.size() != 0 \
			or not next_launch.lines[0].contains("\"source\":\"default\""):
		return "the next launch applied %s and printed %s" % [next_runtime.writes, next_launch.lines]
	var with_switch: FoveationSwitch = FoveationSwitch.parse(PackedStringArray(["--foveation=1"]), "", "")
	var switch_runtime: RefCounted = FakeRuntime.new(0, false)
	with_switch.begin(switch_runtime)
	return "" if switch_runtime.get("foveation_level") == 1 \
		else "the launch switch gave level %s" % switch_runtime.get("foveation_level")


func test_without_an_interface_the_entry_steps_and_applying_does_nothing() -> String:
	var flat: FoveationSwitch = FoveationSwitch.parse(NONE, "", "")
	var wiring: DevMenuWiring = _wiring(flat, null)
	var model: DevMenuModel = wiring.menu.model
	wiring.entry_for(DevMenuSpec.KIND_FOVEATION).show_on(model)
	model.open("centre", "")
	_select(model, DevMenuSpec.KIND_FOVEATION)
	_tap(model, DevMenuModel.RIGHT)
	_tap(model, DevMenuModel.RIGHT)
	if model.foveation_text() != "2 (this session)":
		wiring.menu.free()
		return "the flat entry showed \"%s\"" % model.foveation_text()
	wiring.apply(_tap(model, DevMenuModel.CONFIRM))
	if not flat.lines.is_empty():
		wiring.menu.free()
		return "applying without an interface printed %s" % [flat.lines]
	wiring.entry_for(DevMenuSpec.KIND_FOVEATION).show_on(model)
	var reopened: Vector2i = model.foveation
	var none: DevMenuWiring = DevMenuWiring.new()  # No switch at all, as in older tests.
	none.attach(null, null, null, Callable(), null, null)
	none.apply("foveation:2:on")
	none.entry_for(DevMenuSpec.KIND_FOVEATION).show_on(none.menu.model)
	var none_shown: Vector2i = none.menu.model.foveation
	wiring.menu.free()
	none.menu.free()
	if reopened != Vector2i(2, 0):
		return "the flat entry reopened on %s, not the setting chosen" % reopened
	return "" if none_shown == Vector2i.ZERO else "without a switch the entry opened on %s" % none_shown


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


func test_changing_foveation_mid_flight_leaves_the_state_hash_unchanged() -> String:
	var plain: Node = _main()
	_fly(plain, 90)
	var plain_hash: int = (plain.get("session") as LocalSession).sim.state_hash()
	plain.free()
	var main: Node = _main()
	var chosen: FoveationSwitch = main.get("foveation")
	chosen.begin(FakeRuntime.new(0, false))
	var dev_menu: DevMenuWiring = main.get("dev_menu")
	var wired: bool = (dev_menu.entry_for(DevMenuSpec.KIND_FOVEATION) as DevMenuFoveation).switch == chosen
	_fly(main, 30)
	dev_menu.apply("foveation:3:on")
	_fly(main, 30)
	dev_menu.apply("foveation:0:off")
	_fly(main, 30)
	var switched_hash: int = (main.get("session") as LocalSession).sim.state_hash()
	var applied: int = chosen.lines.size()
	main.free()
	if not wired:
		return "main.gd's dev menu does not change main.gd's foveation switch"
	if applied != 3:
		return "expected a start line and two menu lines, got %d" % applied
	return "" if switched_hash == plain_hash else "changing foveation changed the state hash"
