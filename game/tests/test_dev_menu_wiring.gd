extends RefCounted

## The dev menu wired to the left menu button's tap (#763, PLT-5, DEV-6,
## ARC-3, CMF-8, MP-2): the tap opens and closes it and a hold still resets;
## open, the ship gets neutral input; its choices save the corner, restart on
## a seed or the same source behind a fade, and take a waiting update; the
## tap is ignored during the flight test and the end screens; `main.gd` stays
## at its length.

const SCRATCH_DIR: String = "user://test_dev_menu_wiring"
const FRAME: float = 1.0 / 72.0
const FIXTURE: String = "res://tests/fixtures/main_latest_release.json"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
## `main.gd`'s length before #763; the issue says it must not grow.
const MAIN_LINES_BEFORE: int = 300


static func _scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


## A wiring with no rig, a level start flying `source` and a restart that
## counts its calls in `restarts`.
static func _wired(source: String, restarts: Array[String], update: UpdateWiring = null,
		flight_test: FlightTestWiring = null, destroyed: DestroyedWiring = null) -> DevMenuWiring:
	var level_start: LevelStart = LevelStart.new()
	level_start.source = source
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.corner_store = PanelCorner.new(_scratch("panel.json"))
	var restart: Callable = func() -> void: restarts.append(level_start.source)
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var levels: Array[String] = ["res://data/levels/g2_level.json"]
	wiring.attach(null, update, level_start, restart, flight_test, destroyed, DevMenu.new(spec, levels))
	return wiring


static func _done(wiring: DevMenuWiring) -> void:
	if wiring.menu != null:
		wiring.menu.free()


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


## A tap of the menu button at `at` on the wiring's clock: two frames.
static func _tap(wiring: DevMenuWiring, at: float) -> void:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)


## One press of `button` (or a stick push) inside the open menu: two frames.
static func _press(wiring: DevMenuWiring, values: Dictionary, at: float) -> void:
	wiring.read(values, at)
	wiring.read(_values(), at + FRAME)


static func _down(wiring: DevMenuWiring, at: float) -> void:
	var values: Dictionary = _values()
	values["right_stick"] = Vector2(0.0, -1.0)
	_press(wiring, values, at)


static func _confirm(wiring: DevMenuWiring, at: float) -> void:
	_press(wiring, _values({"right_button_lower": true}), at)


## Moves the highlight down to the entry of `kind`.
static func _select(wiring: DevMenuWiring, kind: String, at: float) -> float:
	var now: float = at
	while wiring.menu.model.kind() != kind:
		_down(wiring, now)
		now += 0.1
	return now


## Frames with nothing pressed from `at` for `seconds`; returns the highest fade seen.
static func _wait(wiring: DevMenuWiring, at: float, seconds: float) -> float:
	var darkest: float = 0.0
	for frame: int in ceili(seconds / FRAME):
		wiring.read(_values(), at + frame * FRAME)
		darkest = maxf(darkest, wiring.alpha)
	return darkest


func test_a_tap_opens_and_closes_the_menu_and_a_hold_resets_with_it_closed() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired("", restarts)
	_tap(wiring, 1.0)
	var opened: bool = wiring.is_open()
	_tap(wiring, 2.0)
	var closed: bool = not wiring.is_open()
	# A hold as long as the reset, with the reset timed on the same frames.
	var hold: ResetHold = ResetHold.new()
	var held: Dictionary = _values({ControllerSampler.MENU_BUTTON: true})
	var now: float = 3.0
	var reset: bool = false
	while now < 3.0 + ResetHold.RESET_HOLD_SECONDS + 0.2:
		var values: Dictionary = wiring.read(held, now)
		hold.press(ResetHold.is_held(values))
		hold.advance(FRAME)
		reset = reset or hold.phase != ResetHold.Phase.IDLE
		now += FRAME
	wiring.read(_values(), now)
	var result: String = ""
	if not opened or not closed:
		result = "a tap opened: %s, a second tap closed: %s" % [opened, closed]
	elif not reset or wiring.is_open():
		result = "a 1 s hold reset: %s, and left the menu open: %s" % [reset, wiring.is_open()]
	_done(wiring)
	return result


func test_with_the_menu_open_the_ship_flies_neutral_input() -> String:
	var hashes: Array[int] = []
	for with_menu: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.get_node("XRRig").call("build")
		main.call("_ready")
		var wiring: DevMenuWiring = main.get("dev_menu")
		if with_menu:
			main.call("apply_controls", _values({ControllerSampler.MENU_BUTTON: true}))
			main.call("apply_controls", _values())
			if not wiring.is_open():
				main.free()
				return "a tap through main.gd did not open the menu"
		for frame: int in 120:
			# Stick, triggers and face buttons, as a pilot flying would hold them,
			# but never A on a confirm-able frame: confirming would close the menu.
			var values: Dictionary = _values({"right_button_upper": true, "left_button_upper": frame % 3 == 0})
			values["left_stick"] = Vector2(0.4, 1.0)
			values["right_stick"] = Vector2(0.3, 0.2)
			values["right_trigger"] = 0.3
			values["right_grip"] = 1.0
			main.call("apply_controls", values if with_menu else _values())
			main.call("advance_frame", FRAME)
		if with_menu and not wiring.is_open():
			main.free()
			return "the menu closed while flying"
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
	if hashes[0] != hashes[1]:
		return "the open menu let input through: %s" % [hashes]
	return ""


func test_choices_save_the_corner_and_restart_on_a_seed_or_the_same_source() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired("res://data/levels/g2_level.json", restarts)
	var now: float = 1.0
	_tap(wiring, now)
	# Corner: right from the opened corner until top_left, then confirm.
	now = _select(wiring, DevMenuSpec.KIND_CORNER, now + 0.5)
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	while wiring.menu.model.corner() != "top_left":
		_press(wiring, right, now)
		now += 0.1
	_confirm(wiring, now)
	var saved: PanelCorner = PanelCorner.new(SCRATCH_DIR + "/panel.json")
	saved.load_saved()
	if saved.corner() != "top_left" or PanelCorner.current != "top_left" or not wiring.is_open():
		_done(wiring)
		return "corner saved as %s, current %s, menu open %s" % [saved.corner(), PanelCorner.current, wiring.is_open()]
	PanelCorner.current = PanelCorner.CENTRE
	# Level: step to the seed choice, then the right trigger up to 40 and B up to 42.
	now = _select(wiring, DevMenuSpec.KIND_LEVEL, now + 0.5)
	while wiring.menu.model.levels.choice() != DevMenuLevels.CHOICE_SEED:
		_press(wiring, right, now)
		now += 0.1
	var far: Dictionary = _values()
	far["right_trigger"] = 1.0
	for step: int in 4:
		_press(wiring, far, now)
		now += 0.1
	for step: int in 2:
		_press(wiring, _values({"right_button_upper": true}), now)
		now += 0.1
	_confirm(wiring, now)
	var darkest: float = _wait(wiring, now + 0.1, DevMenuWiring.FADE_SECONDS * 3.0)
	var after_seed: Array[String] = restarts.duplicate()
	var faded_in: bool = wiring.alpha == 0.0
	# Restart: open again and restart the same source.
	now += 2.0
	_tap(wiring, now)
	now = _select(wiring, DevMenuSpec.KIND_RESTART, now + 0.5)
	_confirm(wiring, now)
	_wait(wiring, now + 0.1, DevMenuWiring.FADE_SECONDS * 3.0)
	_done(wiring)
	if after_seed != ["seed:42"] or wiring.is_open():
		return "the seed choice restarted %s, menu open %s" % [after_seed, wiring.is_open()]
	if darkest < 1.0 or not faded_in:
		return "the restart was not behind a fade (darkest %.2f, cleared %s)" % [darkest, faded_in]
	if restarts != ["seed:42", "seed:42"]:
		return "restart flew %s" % [restarts]
	return ""


func test_random_flies_a_fresh_seed() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired("", restarts)
	wiring.pick_seed = func() -> int: return 77
	wiring.apply("level:random")
	_wait(wiring, 1.0, DevMenuWiring.FADE_SECONDS * 3.0)
	_done(wiring)
	return "" if restarts == ["seed:77"] else "random flew %s" % [restarts]


## An update wiring whose start-up check, from a fake transport, offers a newer build.
static func _update_wiring() -> UpdateWiring:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var running: BuildInfo = BuildInfo.new()
	running.commit = OTHER_COMMIT
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	fake.body = FileAccess.get_file_as_string(FIXTURE)
	var update: UpdateWiring = UpdateWiring.new()
	update.attach_with(null, UpdateRequest.new(settings, fake, running, true))
	return update


func test_a_waiting_update_is_an_entry_that_starts_it_and_none_without() -> String:
	var restarts: Array[String] = []
	var plain: DevMenuWiring = _wired("", restarts, UpdateWiring.new())
	_tap(plain, 1.0)
	var plain_lines: Array[String] = plain.menu.texts()
	_done(plain)
	for line: String in plain_lines:
		if line.contains("Update"):
			return "an update entry shows without a waiting build: %s" % [plain_lines]
	var update: UpdateWiring = _update_wiring()
	var version: String = update.waiting_version()
	var chosen: Array[Dictionary] = []
	update.update_chosen.connect(func(result: Dictionary) -> void: chosen.append(result))
	var wiring: DevMenuWiring = _wired("", restarts, update)
	_tap(wiring, 1.0)
	var lines: Array[String] = wiring.menu.texts()
	var listed: bool = version != "" and lines[0] == "> Update to %s" % version
	_confirm(wiring, 2.0)
	var open: bool = wiring.is_open()
	_done(wiring)
	update.notice.free()
	if not listed:
		return "the waiting build %s is not the first entry: %s" % [version, lines]
	if chosen.size() != 1 or open or not restarts.is_empty():
		return "choosing the entry started %d updates, menu open %s, restarts %s" % [chosen.size(), open, restarts]
	return ""


func test_the_tap_does_nothing_during_the_flight_test_or_an_end_screen() -> String:
	var restarts: Array[String] = []
	var flight_test: FlightTestWiring = FlightTestWiring.new()
	flight_test.choice_path = _scratch("choice.json")
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	flight_test.begin(FlightTestWiring.Start.TUNNEL, comfort, comfort.set_preset)
	var during_test: DevMenuWiring = _wired("", restarts, null, flight_test)
	_tap(during_test, 1.0)
	var test_running: bool = flight_test.running()
	var opened_in_test: bool = during_test.is_open()
	_done(during_test)
	if flight_test.panel != null:
		flight_test.panel.free()
	if not test_running or opened_in_test:
		return "flight test running %s, menu opened %s" % [test_running, opened_in_test]
	for escape: bool in [false, true]:
		var destroyed: DestroyedWiring = DestroyedWiring.new()
		var wiring: DevMenuWiring = _wired("", restarts, null, null, destroyed)
		_tap(wiring, 1.0)
		var opened_before: bool = wiring.is_open()
		var sequence: DestroyedSequence = destroyed.escape.sequence if escape else destroyed.sequence
		sequence.update(0.0, 0.5, false)
		_wait(wiring, 2.0, 0.1)
		var closed_by_screen: bool = not wiring.is_open()
		_tap(wiring, 3.0)
		var opened_on_screen: bool = wiring.is_open()
		_done(wiring)
		if not opened_before or not closed_by_screen or opened_on_screen:
			return "escape %s: opened before %s, closed by the screen %s, opened on it %s" \
				% [escape, opened_before, closed_by_screen, opened_on_screen]
	return ""


func test_the_break_prompt_still_takes_the_tap_first() -> String:
	var restarts: Array[String] = []
	var update: UpdateWiring = UpdateWiring.new()
	var taken: Array[int] = []
	update.tap_taker = func() -> bool:
		taken.append(1)
		return true
	var wiring: DevMenuWiring = _wired("", restarts, update)
	_tap(wiring, 1.0)
	var opened: bool = wiring.is_open()
	_done(wiring)
	return "" if taken.size() == 1 and not opened else "taken %d, opened %s" % [taken.size(), opened]


func test_main_is_not_longer_than_before() -> String:
	var lines: int = FileAccess.get_file_as_string("res://main.gd").split("\n").size() - 1
	return "" if lines <= MAIN_LINES_BEFORE else "main.gd has %d lines, more than %d" % [lines, MAIN_LINES_BEFORE]
