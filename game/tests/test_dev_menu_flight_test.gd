extends RefCounted

## The dev menu's Flight test entry (#839, CMF-4, CMF-8, MP-2, DEV-6): the
## shipped menu lists it with the file's label; choosing it closes the menu,
## restarts the test tunnel behind the fade and runs the first-launch test
## again; finishing applies and saves the recommendation; a skip keeps the
## old preset and the saved choice; the menu does not open while a test runs;
## and the simulation after a rerun equals a first launch with the same answers.

const SCRATCH_DIR: String = "user://test_dev_menu_flight_test"
const FRAME: float = 1.0 / 72.0
const MAIN_FRAME: float = 1.0 / 30.0
const A: String = "right_button_lower"
const B: String = "right_button_upper"
## A saved choice from an earlier first launch: preset 3, test done.
const DONE_FILE: String = "{\"preset\": 3, \"flight_test_done\": true}"


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


## A flight test begun from the tunnel with the choice at `path` (already done)
## and a dev menu wired to it, whose restart counts its sources in `restarts`.
static func _wired(path: String, comfort: ComfortWiring, restarts: Array[String]) -> Array:
	var flight_test: FlightTestWiring = FlightTestWiring.new()
	flight_test.choice_path = path
	flight_test.begin(FlightTestWiring.Start.TUNNEL, comfort, comfort.set_preset)
	var level_start: LevelStart = LevelStart.new()
	level_start.source = "res://data/levels/g2_level.json"
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), comfort)
	var restart: Callable = func() -> void: restarts.append(level_start.source)
	wiring.attach(null, null, level_start, restart, flight_test, null,
		DevMenu.new(DevMenuSpec.load_file(), ["res://data/levels/g2_level.json"]))
	return [wiring, flight_test]


## Opens the menu, chooses Flight test and waits out the fade.
static func _choose(wiring: DevMenuWiring, at: float) -> float:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)
	var now: float = at + 0.3
	while wiring.menu.model.kind() != DevMenuSpec.KIND_FLIGHT_TEST:
		var down: Dictionary = _values()
		down["right_stick"] = Vector2(0.0, -1.0)
		wiring.read(down, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	wiring.read(_values({A: true}), now)
	wiring.read(_values(), now + FRAME)
	var end: float = now + DevMenuWiring.FADE_SECONDS * 3.0
	while now < end:
		now += FRAME
		wiring.read(_values(), now)
	return now


## One frame of the flight test as `main.gd` runs it.
static func _frame(flight_test: FlightTestWiring, buttons: Dictionary = {}, menu: bool = false,
		delta: float = FRAME) -> void:
	flight_test.read_buttons(buttons, menu)
	flight_test.update(delta, false)


static func _answer(flight_test: FlightTestWiring, button: String) -> void:
	_frame(flight_test, {}, false, 60.0)
	_frame(flight_test, {button: true})
	_frame(flight_test)


static func _free(wiring: DevMenuWiring, flight_test: FlightTestWiring) -> void:
	wiring.menu.free()
	if flight_test.panel != null:
		flight_test.panel.free()


func test_the_shipped_menu_lists_the_entry_with_its_label() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	for entry: Dictionary in spec.entries:
		if entry["kind"] == DevMenuSpec.KIND_FLIGHT_TEST:
			if entry["label"] != "Flight test":
				return "the entry is labelled '%s'" % entry["label"]
			var model: DevMenuModel = DevMenuModel.new(spec, [])
			model.open("centre", "")
			while model.kind() != DevMenuSpec.KIND_FLIGHT_TEST:
				model.press({DevMenuModel.DOWN: true})
				model.press({})
			var result: String = model.press({DevMenuModel.CONFIRM: true})
			return "" if result == DevMenuModel.FLIGHT_TEST else "confirming it gave '%s'" % result
	return "the shipped menu has no flight test entry"


func test_the_entry_restarts_the_tunnel_behind_a_fade_and_starts_the_test() -> String:
	var path: String = _scratch("start.json")
	_write(path, DONE_FILE)
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var restarts: Array[String] = []
	var pair: Array = _wired(path, comfort, restarts)
	var wiring: DevMenuWiring = pair[0]
	var flight_test: FlightTestWiring = pair[1]
	var before: bool = flight_test.running()
	_choose(wiring, 1.0)
	var message: String = ""
	if before:
		message = "the test ran although it was done"
	elif restarts != [""]:
		message = "the entry restarted %s, expected the test tunnel" % [restarts]
	elif wiring.is_open():
		message = "the menu stayed open"
	elif wiring.alpha != 0.0:
		message = "the fade did not clear"
	elif not flight_test.running() or flight_test.test.segment_index() != 0:
		message = "the test did not start from its first segment"
	elif comfort.number != flight_test.test.current_segment().preset:
		message = "preset %d, the first segment flies %d" % [comfort.number, flight_test.test.current_segment().preset]
	elif not flight_test.takes_menu_hold():
		message = "the menu hold would not skip the rerun"
	_free(wiring, flight_test)
	return message


func test_finishing_the_rerun_applies_and_saves_the_recommendation() -> String:
	var path: String = _scratch("finish.json")
	_write(path, DONE_FILE)
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var restarts: Array[String] = []
	var pair: Array = _wired(path, comfort, restarts)
	var wiring: DevMenuWiring = pair[0]
	var flight_test: FlightTestWiring = pair[1]
	_choose(wiring, 1.0)
	_answer(flight_test, A)
	_answer(flight_test, A)
	_answer(flight_test, B)
	var back: ComfortChoice = ComfortChoice.new()
	back.load_from(path)
	var message: String = ""
	if flight_test.running():
		message = "uneasy did not end the rerun"
	elif comfort.number != 2 or flight_test.test.recommended() != 2:
		message = "applied %d, recommended %d, expected 2" % [comfort.number, flight_test.test.recommended()]
	elif back.preset() != 2 or back.first_launch():
		message = "saved preset %d, first launch %s" % [back.preset(), back.first_launch()]
	elif flight_test.panel == null or not str(flight_test.panel.shown()["main"]).contains("2"):
		message = "the recommendation is not shown"
	_free(wiring, flight_test)
	return message


func test_skipping_the_rerun_keeps_the_old_preset_and_saved_choice() -> String:
	var path: String = _scratch("skip.json")
	_write(path, DONE_FILE)
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var restarts: Array[String] = []
	var pair: Array = _wired(path, comfort, restarts)
	var wiring: DevMenuWiring = pair[0]
	var flight_test: FlightTestWiring = pair[1]
	var saved_before: String = FileAccess.get_file_as_string(path)
	_choose(wiring, 1.0)
	_answer(flight_test, A)  # Now on segment 2's preset.
	for i: int in 100:
		_frame(flight_test, {}, true)
	for i: int in 10:
		_frame(flight_test)
	var message: String = ""
	if flight_test.running() or not flight_test.test.skipped():
		message = "the menu hold did not skip the rerun"
	elif comfort.number != 3:
		message = "preset %d after the skip, expected the old 3" % comfort.number
	elif FileAccess.get_file_as_string(path) != saved_before:
		message = "the saved choice changed: %s" % FileAccess.get_file_as_string(path)
	elif flight_test.panel != null:
		message = "the panel still shows after the skip"
	_free(wiring, flight_test)
	return message


func test_the_menu_does_not_open_while_the_rerun_runs() -> String:
	var path: String = _scratch("blocked.json")
	_write(path, DONE_FILE)
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var restarts: Array[String] = []
	var pair: Array = _wired(path, comfort, restarts)
	var wiring: DevMenuWiring = pair[0]
	var flight_test: FlightTestWiring = pair[1]
	var now: float = _choose(wiring, 1.0)
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), now + 1.0)
	wiring.read(_values(), now + 1.2)
	var opened: bool = wiring.is_open()
	var again: bool = flight_test.run_again()
	_free(wiring, flight_test)
	if opened:
		return "the menu opened during the rerun"
	return "a second run started over the running one" if again else ""


## The main scene's state hash after flying the flight test answered A, A, B:
## on first launch when `rerun` is false, else chosen from the dev menu after
## flying a while with the test already done.
func _main_hash(rerun: bool) -> int:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var comfort: ComfortWiring = main.get("comfort")
	var flight_test: FlightTestWiring = main.get("flight_test")
	var dev_menu: DevMenuWiring = main.get("dev_menu")
	var path: String = _scratch("main_%s.json" % rerun)
	if rerun:
		_write(path, DONE_FILE)
	flight_test.choice_path = path
	flight_test.begin(FlightTestWiring.Start.TUNNEL, comfort, Callable(main, "set_comfort_preset"),
		main.get_node("XRRig") as Node3D)
	if rerun:
		var input: LatestInputSource = main.get("input_source")
		input.set_input(ShipInput.from_floats(Vector3(0.3, 0.1, -1.0), Vector3(0.0, 0.4, 0.1)))
		for i: int in 40:
			main.call("advance_frame", MAIN_FRAME)
		dev_menu.apply(DevMenuModel.FLIGHT_TEST)
		var now: float = 100.0
		# The fade on a clock of its own; the restart and the test start on the black frame.
		while not flight_test.running() and now < 105.0:
			dev_menu.read(_values(), now)
			now += MAIN_FRAME
	var answers: Array[String] = [A, A, B]
	var frames: int = 0
	while flight_test.running() and frames < 5000:
		var buttons: Dictionary = {}
		if flight_test.test.awaiting_answer() and flight_test.holding() and not answers.is_empty():
			buttons = {answers.pop_front(): true}
		main.call("apply_controls", _values(buttons))
		main.call("advance_frame", MAIN_FRAME)
		frames += 1
	for i: int in 30:
		main.call("apply_controls", _values())
		main.call("advance_frame", MAIN_FRAME)
	var state_hash: int = (main.get("session") as LocalSession).sim.state_hash()
	var ok: bool = not flight_test.running() and comfort.number == 2
	main.free()
	return state_hash if ok else -1


func test_a_rerun_leaves_the_simulation_as_a_first_launch_does() -> String:
	var first: int = _main_hash(false)
	var again: int = _main_hash(true)
	if first == -1 or again == -1:
		return "the test did not end on preset 2 (first launch %d, rerun %d)" % [first, again]
	return "" if first == again else "the rerun's state hash differs from a first launch's"
