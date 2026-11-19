extends RefCounted

## The headset refresh rate (#598, CMF-1, PRF-1, ARC-3): which offered rate a
## preset asks for, the rate in use taken from the runtime and not from the
## request, the log line, the status panel text and the `refresh_rate`
## acceptance check.

const FakeRuntime := preload("res://tests/fake_refresh_runtime.gd")


static func _preset(rate_hz: int, allow_120: bool) -> ComfortPreset:
	var preset: ComfortPreset = ComfortPreset.new()
	preset.refresh_rate_hz = rate_hz
	preset.allow_120_hz = allow_120
	return preset


func test_the_preset_rate_is_chosen_when_offered() -> String:
	var chosen: float = RefreshRate.choose([72.0, 80.0, 90.0, 120.0], _preset(90, false))
	return "" if chosen == 90.0 else "chose %s from a list with 90" % chosen


func test_without_the_preset_rate_the_highest_below_it_is_chosen() -> String:
	var chosen: float = RefreshRate.choose([60.0, 80.0, 72.0, 120.0], _preset(90, false))
	if chosen != 80.0:
		return "chose %s from [60, 80, 72, 120] for 90" % chosen
	chosen = RefreshRate.choose([72.0], _preset(90, false))
	if chosen != 72.0:
		return "chose %s when only 72 is offered" % chosen
	chosen = RefreshRate.choose([120.0], _preset(90, false))
	if chosen != RefreshRate.UNKNOWN:
		return "chose %s when nothing at or below 90 is offered" % chosen
	if RefreshRate.choose([], _preset(90, false)) != RefreshRate.UNKNOWN:
		return "chose a rate from an empty list"
	return ""


func test_a_rate_reported_slightly_off_still_counts() -> String:
	var chosen: float = RefreshRate.choose([72.00001, 89.99, 120.0], _preset(90, false))
	return "" if chosen == 89.99 else "chose %s for a 90 reported as 89.99" % chosen


func test_120_only_with_allow_120_hz() -> String:
	var offered: Array = [72.0, 90.0, 120.0]
	if RefreshRate.choose(offered, _preset(120, true)) != 120.0:
		return "a 120 Hz preset that allows 120 did not get 120"
	if RefreshRate.choose(offered, _preset(120, false)) != 90.0:
		return "a 120 Hz preset without allow_120_hz was not held to 90"
	if RefreshRate.choose(offered, _preset(90, true)) != 90.0:
		return "allow_120_hz alone raised a 90 Hz preset to 120"
	return ""


func test_every_shipped_preset_asks_for_90() -> String:
	for number: int in range(1, 5):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		var chosen: float = RefreshRate.choose([72.0, 80.0, 90.0, 120.0], preset)
		if chosen != 90.0:
			return "preset %d chose %s" % [number, chosen]
	return ""


func test_begin_requests_the_rate_and_waits_for_the_runtime() -> String:
	var runtime: RefCounted = FakeRuntime.new([72.0, 90.0], 72.0)
	var rate: RefreshRate = RefreshRate.new()
	rate.begin(runtime, _preset(90, false))
	if runtime.get("requests") != [90.0]:
		return "requests were %s" % runtime.get("requests")
	if rate.in_use_hz != RefreshRate.UNKNOWN or rate.settled() or not rate.lines.is_empty():
		return "the request was taken as the rate in use"
	if rate.panel_text() != "? Hz":
		return "the panel reads '%s' before the read-back" % rate.panel_text()
	runtime.emit_signal("refresh_rate_changed", 90.0)
	if rate.in_use_hz != 90.0 or not rate.settled():
		return "the change event did not set the rate in use"
	if rate.lines.size() != 1:
		return "%d lines logged for one change" % rate.lines.size()
	for frame: int in range(RefreshRate.READ_BACK_FRAMES + 1):
		rate.advance_frame()
	if rate.lines.size() != 1:
		return "the read-back logged again after the change event"
	return ""


## The owner's Quest 3 before #10: only 72 offered, the read-back right after
## the session began said 90. Without an event the read-back waits.
func test_without_an_event_the_rate_is_read_back_later() -> String:
	var runtime: RefCounted = FakeRuntime.new([72.0], 72.0)
	var rate: RefreshRate = RefreshRate.new()
	rate.begin(runtime, _preset(90, false))
	if rate.requested_hz != 72.0:
		return "requested %s with only 72 offered" % rate.requested_hz
	for frame: int in range(RefreshRate.READ_BACK_FRAMES - 1):
		rate.advance_frame()
	if rate.settled():
		return "read back before %d frames" % RefreshRate.READ_BACK_FRAMES
	rate.advance_frame()
	if not rate.settled() or rate.in_use_hz != 72.0:
		return "read back %s, settled %s" % [rate.in_use_hz, rate.settled()]
	if rate.panel_text() != "72 Hz":
		return "the panel reads '%s'" % rate.panel_text()
	return ""


func test_a_later_runtime_change_is_logged() -> String:
	var runtime: RefCounted = FakeRuntime.new([72.0, 90.0], 90.0)
	var rate: RefreshRate = RefreshRate.new()
	rate.begin(runtime, _preset(90, false))
	runtime.emit_signal("refresh_rate_changed", 90.0)
	runtime.emit_signal("refresh_rate_changed", 72.0)
	if rate.lines.size() != 2 or rate.in_use_hz != 72.0:
		return "lines %s, in use %s" % [rate.lines, rate.in_use_hz]
	return ""


func test_a_preset_change_asks_again_and_nothing_before_the_session() -> String:
	var rate: RefreshRate = RefreshRate.new()
	rate.apply(_preset(120, true))
	if rate.requested_hz != RefreshRate.UNKNOWN or rate.panel_text() != "":
		return "a preset change before the session asked for a rate"
	var runtime: RefCounted = FakeRuntime.new([72.0, 90.0, 120.0], 72.0)
	rate.begin(runtime, _preset(90, false))
	rate.apply(_preset(120, true))
	if runtime.get("requests") != [90.0, 120.0]:
		return "requests were %s" % runtime.get("requests")
	if rate.settled():
		return "a new request left the old rate counted as settled"
	return ""


func test_the_log_line_names_requested_offered_and_in_use() -> String:
	var offered: Array[float] = [72.0, 90.0]
	var line: String = RefreshRate.format_line(90.0, offered, 72.0)
	if line != "Meltdown: refresh rate requested 90.0 Hz, offered [72.0, 90.0], in use 72.0 Hz":
		return "line reads '%s'" % line
	var none: Array[float] = []
	line = RefreshRate.format_line(RefreshRate.UNKNOWN, none, 60.0)
	if line != "Meltdown: refresh rate requested none, offered [], in use 60.0 Hz":
		return "line without a request reads '%s'" % line
	return ""


func test_the_rate_sits_beside_the_build_only_in_a_session() -> String:
	var rate: RefreshRate = RefreshRate.new()
	if rate.beside("abc1234") != "abc1234":
		return "a flat run added '%s'" % rate.beside("abc1234")
	rate.begin(FakeRuntime.new([90.0], 72.0), _preset(90, false))
	rate.on_runtime_changed(90.0)
	return "" if rate.beside("abc1234") == "abc1234  90 Hz" else "reads '%s'" % rate.beside("abc1234")


func test_the_check_fails_below_the_preset_and_passes_at_it() -> String:
	var rate: RefreshRate = RefreshRate.new()
	rate.begin(FakeRuntime.new([72.0], 72.0), _preset(90, false))
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceRefreshCheck.judge(rate, 90.0, measurements)
	if outcome[0] != AcceptanceReport.RESULT_FAIL:
		return "an unread rate is %s" % outcome[0]
	rate.on_runtime_changed(72.0)
	outcome = AcceptanceRefreshCheck.judge(rate, 90.0, measurements)
	if outcome[0] != AcceptanceReport.RESULT_FAIL or not String(outcome[1]).contains("72"):
		return "72 Hz for a 90 Hz preset gave %s" % [outcome]
	if measurements.get("refresh_rate_in_use_hz") != 72.0 or measurements.get("refresh_rate_wanted_hz") != 90.0:
		return "measurements %s" % measurements
	rate.on_runtime_changed(90.0)
	outcome = AcceptanceRefreshCheck.judge(rate, 90.0, measurements)
	return "" if outcome[0] == AcceptanceReport.RESULT_PASS else "90 Hz gave %s" % [outcome]


func test_the_check_is_skipped_without_a_runtime_unless_required() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var skipped: Array = AcceptanceRefreshCheck.run(main, false, false, {})
	var required: Array = AcceptanceRefreshCheck.run(main, false, true, {})
	var settled: bool = AcceptanceRefreshCheck.settled(main)
	main.free()
	if skipped[0] != AcceptanceReport.RESULT_SKIPPED:
		return "without a runtime the check is %s" % skipped[0]
	if required[0] != AcceptanceReport.RESULT_FAIL:
		return "a required check without a runtime is %s" % required[0]
	if settled:
		return "the scene's rate counts as settled before any session"
	return ""


func test_the_m1_suite_has_the_refresh_rate_step() -> String:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m1")
	if suites.size() != 1 or suites[0].error != "":
		return "m1 did not load"
	for step: AcceptanceStep in suites[0].steps:
		if step.id == "refresh_rate" and step.checks == [AcceptanceStep.CHECK_REFRESH_RATE]:
			return ""
	return "m1 has no refresh_rate step"
