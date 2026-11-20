extends RefCounted

## The `MELTDOWN_VIEW` diagnostic line (#651): off unless asked for, one
## sample a second while on, and every value the owner may need to send.


func test_off_unless_the_switch_or_the_setting_turns_it_on() -> String:
	if ViewLog.enabled_by(PackedStringArray(["--comfort-preset=2"]), null):
		return "on without the switch or the setting"
	if ViewLog.enabled_by(PackedStringArray(), "true"):
		return "a text setting turned it on"
	if not ViewLog.enabled_by(PackedStringArray([ViewLog.SWITCH]), false):
		return "the switch did not turn it on"
	if not ViewLog.enabled_by(PackedStringArray(), true):
		return "the setting did not turn it on"
	return ""


## #671 criterion 1: the intent extra alone turns it on.
func test_the_intent_extra_turns_it_on() -> String:
	for value: String in ["1", "true", "TRUE", " true "]:
		if not ViewLog.enabled_by(PackedStringArray(), null, value):
			return "intent value %s did not turn it on" % JSON.stringify(value)
		if not ViewLog.enabled_by(PackedStringArray(), false, value):
			return "intent value %s with the setting off did not turn it on" % JSON.stringify(value)
	return ""


## #671 criterion 2: an empty, `0` or `false` extra leaves it off.
func test_an_off_or_missing_intent_extra_leaves_it_off() -> String:
	for value: String in ["", "0", "false", "no", "2"]:
		if ViewLog.enabled_by(PackedStringArray(["--comfort-preset=2"]), false, value):
			return "intent value %s turned it on" % JSON.stringify(value)
	if ViewLog.enabled_by(PackedStringArray(), null):
		return "no intent value turned it on"
	return ""


## #671 criterion 3: the switch or the setting alone still turns it on,
## whatever the intent says.
func test_the_switch_or_setting_wins_over_the_intent_extra() -> String:
	for value: String in ["", "0", "false", "1"]:
		if not ViewLog.enabled_by(PackedStringArray([ViewLog.SWITCH]), false, value):
			return "the switch with intent %s did not turn it on" % JSON.stringify(value)
		if not ViewLog.enabled_by(PackedStringArray(), true, value):
			return "the setting with intent %s did not turn it on" % JSON.stringify(value)
	return ""


## Off the headset there is no intent to read.
func test_no_intent_value_off_android() -> String:
	return "" if ViewLog.intent_value() == "" else "read an intent value off Android"


func test_an_off_log_writes_nothing() -> String:
	var view_log: ViewLog = ViewLog.new()
	for i: int in 300:
		view_log.sample(i * 0.1, {"preset": 2})
	view_log.event("preset=3")
	return "" if view_log.lines.is_empty() else "an off log wrote %s" % view_log.lines


func test_one_sample_line_a_second() -> String:
	var view_log: ViewLog = ViewLog.new()
	view_log.enabled = true
	for i: int in 451:
		view_log.sample(i / 90.0, {"preset": 2})
	# 0 to 5 s inclusive: a line at 0, 1, 2, 3, 4 and 5 s.
	return "" if view_log.lines.size() == 6 else "%d lines in 5 s" % view_log.lines.size()


func test_the_line_names_every_value_the_issue_asks_for() -> String:
	var guard: ViewGuard = ViewGuard.new()
	var head: Transform3D = Transform3D(Basis(Vector3.UP, -deg_to_rad(30.0)), Vector3(0.0, 0.1, 0.0))
	guard.update(Transform3D.IDENTITY, head, true, CockpitSpec.new(), 2.0)
	var shake: Transform3D = Transform3D(Basis(), Vector3(0.0, 0.01, 0.0))
	var line: String = ViewLog.sample_line(ViewLog.values(guard, head, shake, 3, 42.5, true, 3.5))
	if not line.begins_with(ViewLog.PREFIX + " "):
		return "line does not start with %s: %s" % [ViewLog.PREFIX, line]
	for part: String in ["head_to_window_deg=30.000", "head_offset_m=0.100", "shake_offset_m=0.010",
			"frame_placed_age_s=1.500", "preset=3", "hull=42.500", "tracked=true", "frame_placed_by=recentre"]:
		if not line.contains(part):
			return "line lacks %s: %s" % [part, line]
	return ""


func test_a_preset_change_logs_what_it_rebuilt() -> String:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.view_log.enabled = true
	comfort.set_preset(4)
	var lines: PackedStringArray = comfort.view_log.lines
	if lines.size() != 1 or not lines[0].contains("preset=4") or not lines[0].contains("cockpit_frame"):
		return "preset change logged %s" % lines
	return ""
