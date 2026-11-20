extends RefCounted

## The update notice in the headset: a newer build is offered with "Update"
## and "Later", a menu tap shorter than the reset hold chooses or asks, and
## "Update" only emits a signal; nothing downloads or installs (#646).

const FIXTURE: String = "res://tests/fixtures/main_latest_release.json"
const RELEASE_COMMIT: String = "e1b0a77b6477cc25b84e96bf7e7aefdcc6c27ee5"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"


static func _wired(running_commit: String, fake: FakeUpdateTransport, panel: Node3D) -> UpdateWiring:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var running: BuildInfo = BuildInfo.new()
	running.commit = running_commit
	fake.body = FileAccess.get_file_as_string(FIXTURE)
	var wiring: UpdateWiring = UpdateWiring.new()
	wiring.attach_with(panel, UpdateRequest.new(settings, fake, running, true))
	return wiring


## A tap: down at `at`, up `held` seconds later.
static func _tap(wiring: UpdateWiring, at: float, held: float = 0.2) -> void:
	wiring.press_menu(true, at)
	wiring.press_menu(false, at + held)


func test_a_menu_tap_is_shorter_than_the_reset_hold() -> String:
	var tap: MenuTap = MenuTap.new()
	if tap.feed(true, 1.0) or tap.feed(true, 1.1):
		return "a press counted as a tap before release"
	if not tap.feed(false, 1.3):
		return "a short press and release was not a tap"
	tap.feed(true, 2.0)
	if tap.feed(false, 2.0 + ResetHold.RESET_HOLD_SECONDS):
		return "a press as long as the reset hold counted as a tap"
	return "" if not tap.feed(false, 5.0) else "a frame with nothing pressed was a tap"


func test_a_newer_build_is_offered_on_start_and_update_emits_only() -> String:
	var panel: Node3D = Node3D.new()
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	var wiring: UpdateWiring = _wired(OTHER_COMMIT, fake, panel)
	var chosen: Array[Dictionary] = []
	wiring.update_chosen.connect(func(result: Dictionary) -> void: chosen.append(result))
	var message: String = ""
	if not wiring.notice.offering or not wiring.notice.is_showing():
		message = "no offer after the start-up check"
	elif wiring.notice.line_text() != "Update available: e1b0a77, built 2026-11-15 19:07 UTC":
		message = "the offer read '%s'" % wiring.notice.line_text()
	elif wiring.notice.get_parent() != panel:
		message = "the notice is not on the panel"
	else:
		_tap(wiring, 10.0)
		if chosen.size() != 1 or chosen[0].get("commit", "") != RELEASE_COMMIT:
			message = "Update emitted %s" % [chosen]
		elif wiring.notice.is_showing():
			message = "the notice stayed up after Update"
		elif fake.urls.size() != 1:
			message = "choosing Update sent another request"
	panel.free()
	return message


func test_later_is_letting_the_offer_go() -> String:
	var panel: Node3D = Node3D.new()
	var wiring: UpdateWiring = _wired(OTHER_COMMIT, FakeUpdateTransport.new(), panel)
	var later: Array[bool] = []
	var chosen: Array[bool] = []
	wiring.notice.later_chosen.connect(func() -> void: later.append(true))
	wiring.update_chosen.connect(func(_result: Dictionary) -> void: chosen.append(true))
	wiring.notice.advance(UpdateNotice.OFFER_SECONDS - 0.5)
	var message: String = ""
	if not wiring.notice.offering:
		message = "the offer went before its time"
	else:
		wiring.notice.advance(1.0)
		if wiring.notice.is_showing() or later.size() != 1 or not chosen.is_empty():
			message = "after the offer time: showing %s, later %d, update %d" % [
				wiring.notice.is_showing(), later.size(), chosen.size()]
	panel.free()
	return message


func test_up_to_date_shows_nothing_on_start_and_a_line_when_asked() -> String:
	var panel: Node3D = Node3D.new()
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	var wiring: UpdateWiring = _wired(RELEASE_COMMIT, fake, panel)
	var message: String = ""
	if wiring.notice.is_showing():
		message = "up to date showed '%s' on start" % wiring.notice.line_text()
	else:
		_tap(wiring, 3.0)
		if fake.urls.size() != 2:
			message = "a tap without an offer did not ask: %d requests" % fake.urls.size()
		elif wiring.notice.line_text() != "Up to date: e1b0a77" or wiring.notice.offering:
			message = "asked line was '%s'" % wiring.notice.line_text()
		else:
			wiring.notice.advance(UpdateNotice.REASON_SECONDS + 0.1)
			if wiring.notice.is_showing():
				message = "the reason line stayed up"
	panel.free()
	return message


func test_a_failed_start_shows_nothing() -> String:
	var panel: Node3D = Node3D.new()
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	fake.result = HTTPRequest.RESULT_CANT_CONNECT
	var wiring: UpdateWiring = _wired(OTHER_COMMIT, fake, panel)
	var message: String = ""
	if wiring.notice.is_showing():
		message = "a failed start-up check showed '%s'" % wiring.notice.line_text()
	panel.free()
	return message


func test_a_long_hold_neither_asks_nor_chooses() -> String:
	var panel: Node3D = Node3D.new()
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	var wiring: UpdateWiring = _wired(OTHER_COMMIT, fake, panel)
	var chosen: Array[bool] = []
	wiring.update_chosen.connect(func(_result: Dictionary) -> void: chosen.append(true))
	_tap(wiring, 1.0, ResetHold.RESET_HOLD_SECONDS + 0.1)
	var message: String = ""
	if not chosen.is_empty() or fake.urls.size() != 1 or not wiring.notice.offering:
		message = "the reset hold chose Update or asked again"
	panel.free()
	return message


func test_an_unwired_build_ignores_the_menu_button() -> String:
	var wiring: UpdateWiring = UpdateWiring.new()
	_tap(wiring, 1.0)
	return "" if wiring.request == null and wiring.notice == null else "an unattached wiring built parts"


func test_an_acceptance_run_never_checks() -> String:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	if not UpdateWiring.may_attach(true, settings, true, ""):
		return "a debug headset build without a suite should check"
	if UpdateWiring.may_attach(true, settings, true, "m1"):
		return "an acceptance run must not send the update check"
	if UpdateWiring.may_attach(false, settings, true, ""):
		return "a release build must never check"
	return ""
