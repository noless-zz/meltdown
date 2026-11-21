extends RefCounted

## The take-a-break prompt in the game (#716, CMF-10, CMF-6, CMF-8, ARC-3):
## when it is due through the wiring with a fake clock, which time counts,
## the switch-off setting, and how it shares the menu tap with the update notice.

const MINUTE: float = 60.0
## One-second frames keep half an hour of flying quick; the reminder only sums them.
const STEP: float = 1.0


static func _comfort(number: int) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.set_preset(number)
	return comfort


## The shipped break prompt file with `enabled` set as given.
static func _look(enabled: bool) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BreakPromptLook.DEFAULT_FILE))
	data["enabled"] = enabled
	return BreakPromptLook.parse(JSON.stringify(data))


static func _wired(comfort: ComfortWiring, update: UpdateWiring = null, look: Dictionary = {}) -> BreakPromptWiring:
	var wiring: BreakPromptWiring = BreakPromptWiring.new()
	wiring.attach(null, comfort, update, look)
	return wiring


static func _fly(wiring: BreakPromptWiring, seconds: float, flying: bool = true) -> void:
	for i: int in roundi(seconds / STEP):
		wiring.update(STEP, flying, true)


static func _done(wiring: BreakPromptWiring) -> void:
	if wiring.prompt != null:
		wiring.prompt.free()


## A tap of the menu button at `at` seconds on the update wiring's clock.
static func _tap(update: UpdateWiring, at: float) -> void:
	update.press_menu(true, at)
	update.press_menu(false, at + 0.2)


## An update wiring whose checks go to a fake transport and fail at once, so
## a tap that reaches it shows as one more request.
static func _update_wiring(transport: FakeUpdateTransport) -> UpdateWiring:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var update: UpdateWiring = UpdateWiring.new()
	update.attach_with(null, UpdateRequest.new(settings, transport, BuildInfo.new(), true))
	return update


func test_due_after_thirty_flown_minutes_on_presets_one_to_three() -> String:
	for number: int in [1, 2, 3]:
		var wiring: BreakPromptWiring = _wired(_comfort(number))
		_fly(wiring, 30.0 * MINUTE - STEP)
		var early: bool = wiring.shown()
		_fly(wiring, STEP)
		var due: bool = wiring.shown()
		var text: String = wiring.prompt.body_text()
		_done(wiring)
		if early:
			return "preset %d: shown before 30 minutes" % number
		if not due:
			return "preset %d: not shown after 30 flown minutes" % number
		if not text.contains("30 minutes"):
			return "preset %d: body does not say 30 minutes: %s" % [number, text]
	return ""


func test_never_on_preset_four() -> String:
	var wiring: BreakPromptWiring = _wired(_comfort(4))
	_fly(wiring, 120.0 * MINUTE)
	var shown: bool = wiring.shown()
	_done(wiring)
	return "shown on preset 4" if shown else ""


func test_switch_off_from_the_file_is_applied_at_start() -> String:
	var off: BreakPromptWiring = _wired(_comfort(1), null, _look(false))
	_fly(off, 60.0 * MINUTE)
	var off_shown: bool = off.shown()
	var off_enabled: bool = off.reminder.is_enabled()
	_done(off)
	var shipped: BreakPromptWiring = _wired(_comfort(1))
	var shipped_enabled: bool = shipped.reminder.is_enabled()
	_done(shipped)
	if off_enabled or off_shown:
		return "switched off in the file, yet the reminder runs"
	if not shipped_enabled:
		return "the shipped file's switch is on, yet the reminder is off"
	return ""


func test_time_not_flying_does_not_count() -> String:
	var wiring: BreakPromptWiring = _wired(_comfort(1))
	_fly(wiring, 20.0 * MINUTE)
	_fly(wiring, 60.0 * MINUTE, false)
	var after_pause: bool = wiring.shown()
	_fly(wiring, 10.0 * MINUTE - STEP)
	var early: bool = wiring.shown()
	_fly(wiring, STEP)
	var due: bool = wiring.shown()
	_done(wiring)
	if after_pause or early:
		return "time not flying was counted"
	if not due:
		return "not shown after 30 flown minutes either side of a pause"
	return ""


func test_a_menu_tap_hides_it_and_the_next_is_thirty_minutes_later() -> String:
	var update: UpdateWiring = UpdateWiring.new()  # No request, as on the desktop.
	var wiring: BreakPromptWiring = _wired(_comfort(2), update)
	_fly(wiring, 30.0 * MINUTE)
	var before: bool = wiring.shown()
	_tap(update, 10.0)
	_fly(wiring, STEP)
	var after_tap: bool = wiring.shown()
	_fly(wiring, 30.0 * MINUTE - 2.0 * STEP)
	var early: bool = wiring.shown()
	_fly(wiring, STEP)
	var again: bool = wiring.shown()
	_done(wiring)
	if not before:
		return "not shown before the tap"
	if after_tap:
		return "a menu tap did not hide the prompt"
	if early:
		return "the next prompt came before 30 more flown minutes"
	if not again:
		return "no prompt 30 flown minutes after the tap"
	return ""


func test_the_prompt_takes_the_tap_and_the_update_notice_waits() -> String:
	var transport: FakeUpdateTransport = FakeUpdateTransport.new()
	var update: UpdateWiring = _update_wiring(transport)
	var wiring: BreakPromptWiring = _wired(_comfort(1), update)
	var at_start: int = transport.urls.size()
	_tap(update, 5.0)
	var hidden_tap: int = transport.urls.size()
	_fly(wiring, 30.0 * MINUTE)
	_tap(update, 10.0)
	var shown_tap: int = transport.urls.size()
	_fly(wiring, STEP)
	var hidden: bool = not wiring.shown()
	_tap(update, 15.0)
	var next_tap: int = transport.urls.size()
	_done(wiring)
	update.notice.free()
	if at_start != 1:
		return "expected the start-up check, saw %d requests" % at_start
	if hidden_tap != 2:
		return "a tap with no prompt showing did not reach the update notice"
	if shown_tap != 2:
		return "a tap that dismissed the prompt also asked for an update check"
	if not hidden:
		return "the tap did not dismiss the prompt"
	if next_tap != 3:
		return "the update notice did not get the tap after the prompt was gone"
	return ""


func test_every_preset_change_reaches_the_reminder() -> String:
	var comfort: ComfortWiring = _comfort(4)
	var wiring: BreakPromptWiring = _wired(comfort)
	_fly(wiring, 31.0 * MINUTE)
	var on_four: bool = wiring.shown()
	comfort.set_preset(1)
	_fly(wiring, STEP)
	var on_one: bool = wiring.shown()
	comfort.set_preset(4)
	_fly(wiring, STEP)
	var back_on_four: bool = wiring.shown()
	_done(wiring)
	if on_four:
		return "shown on preset 4"
	if not on_one:
		return "time flown is kept across a preset change, yet preset 1 did not show the prompt"
	if back_on_four:
		return "switching to preset 4 did not clear the prompt"
	return ""


func test_flying_excludes_pause_flight_test_and_lost_ship() -> String:
	var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
	var flight_test: FlightTestWiring = FlightTestWiring.new()
	var destroyed: DestroyedWiring = DestroyedWiring.new()
	if not BreakPromptWiring.is_flying(session, flight_test, destroyed):
		return "flying the tunnel does not count"
	session.paused = true
	if BreakPromptWiring.is_flying(session, flight_test, destroyed):
		return "a paused session counts as flying"
	session.paused = false
	var path: String = "user://test_break_prompt_wiring_choice.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var comfort: ComfortWiring = _comfort(1)
	flight_test.choice_path = path
	flight_test.begin(FlightTestWiring.Start.TUNNEL, comfort, comfort.set_preset)
	var during_test: bool = BreakPromptWiring.is_flying(session, flight_test, destroyed)
	if flight_test.panel != null:
		flight_test.panel.free()
	if not flight_test.running():
		return "the flight test did not start for this check"
	if during_test:
		return "the flight test counts as flying"
	session.sim.ships[0].hull = 0.0
	session.advance(ShipState.TICK_DT)  # The session hands out copies made each tick.
	if BreakPromptWiring.is_flying(session, FlightTestWiring.new(), destroyed):
		return "a lost ship counts as flying"
	return ""
