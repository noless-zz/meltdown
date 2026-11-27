extends RefCounted

## The dev menu wired to the left menu button's tap (#763, PLT-5, DEV-6,
## ARC-3, CMF-8, MP-2): the tap opens and closes it and a hold still resets;
## open, the ship gets neutral input; the tap is ignored during the flight
## test and an end screen's fade, and opens on the dark end screen (#1450);
## `main.gd` stays at its length. The menu's choices
## are in `test_dev_menu_wiring_choices.gd`, which uses this file's public
## static fixtures (#1283).

const SCRATCH_DIR: String = "user://test_dev_menu_wiring"
const FRAME: float = 1.0 / 72.0
## `main.gd`'s length before #763; the issue says it must not grow.
const MAIN_LINES_BEFORE: int = 300


static func scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


## A wiring with no rig, a level start flying `source` and a restart that
## counts its calls in `restarts`.
static func wired(source: String, restarts: Array[String], update: UpdateWiring = null,
		flight_test: FlightTestWiring = null, destroyed: DestroyedWiring = null) -> DevMenuWiring:
	var level_start: LevelStart = LevelStart.new()
	level_start.source = source
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.corner_store = PanelCorner.new(scratch("panel.json"))
	var restart: Callable = func() -> void: restarts.append(level_start.source)
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var levels: Array[String] = ["res://data/levels/g2_level.json"]
	wiring.attach(null, update, level_start, restart, flight_test, destroyed, DevMenu.new(spec, levels))
	return wiring


static func done(wiring: DevMenuWiring) -> void:
	if wiring.menu != null:
		wiring.menu.free()


static func pad_values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


## A tap of the menu button at `at` on the wiring's clock: two frames.
static func tap(wiring: DevMenuWiring, at: float) -> void:
	wiring.read(pad_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(pad_values(), at + 0.2)


## One press of `button` (or a stick push) inside the open menu: two frames.
static func press(wiring: DevMenuWiring, values: Dictionary, at: float) -> void:
	wiring.read(values, at)
	wiring.read(pad_values(), at + FRAME)


static func confirm(wiring: DevMenuWiring, at: float) -> void:
	press(wiring, pad_values({"right_button_lower": true}), at)


## Highlights the entry of `kind`, into its section when it has one (#1301).
static func select(wiring: DevMenuWiring, kind: String, at: float) -> float:
	return DevMenuWalk.select_wired(wiring, kind, at)


## Frames with nothing pressed from `at` for `seconds`; returns the highest fade seen.
static func wait(wiring: DevMenuWiring, at: float, seconds: float) -> float:
	var darkest: float = 0.0
	for frame: int in ceili(seconds / FRAME):
		wiring.read(pad_values(), at + frame * FRAME)
		darkest = maxf(darkest, wiring.alpha)
	return darkest


func test_a_tap_opens_and_closes_the_menu_and_a_hold_resets_with_it_closed() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = wired("", restarts)
	tap(wiring, 1.0)
	var opened: bool = wiring.is_open()
	tap(wiring, 2.0)
	var closed: bool = not wiring.is_open()
	# A hold as long as the reset, with the reset timed on the same frames.
	var hold: ResetHold = ResetHold.new()
	var held: Dictionary = pad_values({ControllerSampler.MENU_BUTTON: true})
	var now: float = 3.0
	var reset: bool = false
	while now < 3.0 + ResetHold.RESET_HOLD_SECONDS + 0.2:
		var values: Dictionary = wiring.read(held, now)
		hold.press(ResetHold.is_held(values))
		hold.advance(FRAME)
		reset = reset or hold.phase != ResetHold.Phase.IDLE
		now += FRAME
	wiring.read(pad_values(), now)
	var result: String = ""
	if not opened or not closed:
		result = "a tap opened: %s, a second tap closed: %s" % [opened, closed]
	elif not reset or wiring.is_open():
		result = "a 1 s hold reset: %s, and left the menu open: %s" % [reset, wiring.is_open()]
	done(wiring)
	return result


## Since #1245 the open menu also pauses solo play, so no tick runs at all.
func test_with_the_menu_open_the_ship_flies_neutral_input() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var wiring: DevMenuWiring = main.get("dev_menu")
	main.call("apply_controls", pad_values({ControllerSampler.MENU_BUTTON: true}))
	main.call("apply_controls", pad_values())
	if not wiring.is_open():
		main.free()
		return "a tap through main.gd did not open the menu"
	var session: LocalSession = main.get("session")
	var hash_at_open: int = session.sim.state_hash()
	var result: String = ""
	for frame: int in 120:
		# Stick, triggers and face buttons, as a pilot flying would hold them,
		# but never A on a confirm-able frame: confirming would close the menu.
		var values: Dictionary = pad_values({"right_button_upper": true, "left_button_upper": frame % 3 == 0})
		values["left_stick"] = Vector2(0.4, 1.0)
		values["right_stick"] = Vector2(0.3, 0.2)
		values["right_trigger"] = 0.3
		values["right_grip"] = 1.0
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)
		var input: ShipInput = (main.get("input_source") as LatestInputSource).latest_input()
		if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO or input.afterburner:
			result = "frame %d: the open menu let input through" % frame
	if result == "" and (not wiring.is_open() or session.sim.state_hash() != hash_at_open):
		result = "the menu closed (%s) or the simulation ran with it open" % (not wiring.is_open())
	main.free()
	return result


func test_the_tap_does_nothing_during_the_flight_test_and_opens_on_a_dark_end_screen() -> String:
	var restarts: Array[String] = []
	var flight_test: FlightTestWiring = FlightTestWiring.new()
	flight_test.choice_path = scratch("choice.json")
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	flight_test.begin(FlightTestWiring.Start.TUNNEL, comfort, comfort.set_preset)
	var during_test: DevMenuWiring = wired("", restarts, null, flight_test)
	tap(during_test, 1.0)
	var test_running: bool = flight_test.running()
	var opened_in_test: bool = during_test.is_open()
	done(during_test)
	if flight_test.panel != null:
		flight_test.panel.free()
	if not test_running or opened_in_test:
		return "flight test running %s, menu opened %s" % [test_running, opened_in_test]
	for escape: bool in [false, true]:
		var destroyed: DestroyedWiring = DestroyedWiring.new()
		var wiring: DevMenuWiring = wired("", restarts, null, null, destroyed)
		tap(wiring, 1.0)
		var opened_before: bool = wiring.is_open()
		var sequence: DestroyedSequence = destroyed.escape.sequence if escape else destroyed.sequence
		sequence.update(0.0, 0.0, false)  # The screen comes up and starts to fade (#1450).
		sequence.update(0.0, 0.5, false)
		wait(wiring, 2.0, 0.1)
		var closed_by_screen: bool = not wiring.is_open()
		tap(wiring, 3.0)
		var opened_while_fading: bool = wiring.is_open()
		sequence.update(0.0, 30.0, false)  # Dark, the line and prompt up.
		tap(wiring, 4.0)
		var opened_on_screen: bool = wiring.is_open()
		var place: String = wiring.menu.model.place
		var texts: Array[String] = wiring.menu.texts()
		done(wiring)
		if not opened_before or not closed_by_screen or opened_while_fading:
			return "escape %s: opened before %s, closed by the screen %s, opened while fading %s" \
				% [escape, opened_before, closed_by_screen, opened_while_fading]
		if not opened_on_screen or place != DevMenuPlaces.END or " | ".join(texts).contains("Mine"):
			return "escape %s: on the dark screen opened %s at %s showing %s" % [escape, opened_on_screen, place, texts]
	return ""


func test_the_break_prompt_still_takes_the_tap_first() -> String:
	var restarts: Array[String] = []
	var update: UpdateWiring = UpdateWiring.new()
	var taken: Array[int] = []
	update.tap_taker = func() -> bool:
		taken.append(1)
		return true
	var wiring: DevMenuWiring = wired("", restarts, update)
	tap(wiring, 1.0)
	var opened: bool = wiring.is_open()
	done(wiring)
	return "" if taken.size() == 1 and not opened else "taken %d, opened %s" % [taken.size(), opened]


func test_main_is_not_longer_than_before() -> String:
	var lines: int = FileAccess.get_file_as_string("res://main.gd").split("\n").size() - 1
	return "" if lines <= MAIN_LINES_BEFORE else "main.gd has %d lines, more than %d" % [lines, MAIN_LINES_BEFORE]
