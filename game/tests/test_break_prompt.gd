extends RefCounted

## The "take a break" prompt (#700, CMF-10): when it shows and hides, what it
## says, its switch-off setting, its data file (ARC-4), and that showing it
## changes nothing but its own visibility (CMF-6, CMF-8, ARC-3).

const THIRTY_MIN_S: float = 30.0 * 60.0


static func _reminder_for(number: int) -> BreakReminder:
	return BreakReminder.new(ComfortPresetFiles.load_number(number))


static func _shipped_text() -> String:
	return FileAccess.get_file_as_string(BreakPromptLook.DEFAULT_FILE)


## The shipped file's text with `key` set to `value`.
static func _text_with(key: String, value: Variant) -> String:
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data[key] = value
	return JSON.stringify(data)


func test_shipped_file_loads() -> String:
	var look: Dictionary = BreakPromptLook.parse(_shipped_text())
	if look.has("error"):
		return "shipped break_prompt.json rejected: %s" % look["error"]
	if not bool(look["enabled"]):
		return "reminders should ship switched on"
	var prompt: BreakPrompt = BreakPrompt.new()
	var problem: String = "" if prompt.look_error() == "" else "prompt reports %s" % prompt.look_error()
	prompt.free()
	return problem


func test_hidden_before_thirty_minutes_then_shown_and_hidden_on_acknowledge() -> String:
	for number: int in [1, 2, 3]:
		var reminder: BreakReminder = _reminder_for(number)
		var prompt: BreakPrompt = BreakPrompt.new()
		var problem: String = ""
		reminder.advance(THIRTY_MIN_S - 1.0, true)
		if prompt.show_if(reminder) or prompt.is_shown():
			problem = "preset %d: shown at 29:59" % number
		reminder.advance(1.0, true)
		if problem == "" and not prompt.show_if(reminder):
			problem = "preset %d: not shown at 30:00" % number
		if problem == "" and not prompt.acknowledge():
			problem = "preset %d: acknowledge did not dismiss a shown prompt" % number
		if problem == "" and (prompt.is_shown() or reminder.due()):
			problem = "preset %d: still shown or due after acknowledge" % number
		if problem == "" and prompt.show_if(reminder):
			problem = "preset %d: shown again straight after acknowledge" % number
		reminder.advance(THIRTY_MIN_S - 1.0, true)
		if problem == "" and prompt.show_if(reminder):
			problem = "preset %d: shown again 29:59 after acknowledge" % number
		reminder.advance(1.0, true)
		if problem == "" and not prompt.show_if(reminder):
			problem = "preset %d: not shown again 30 minutes after acknowledge" % number
		prompt.free()
		if problem != "":
			return problem
	return ""


func test_never_shown_on_preset_4() -> String:
	var reminder: BreakReminder = _reminder_for(4)
	var prompt: BreakPrompt = BreakPrompt.new()
	var problem: String = ""
	for hour: int in 10:
		reminder.advance(3600.0, true)
		if prompt.show_if(reminder) or prompt.is_shown():
			problem = "shown on preset 4 after %d hours" % (hour + 1)
			break
	prompt.free()
	return problem


func test_never_shown_when_switched_off() -> String:
	var reminder: BreakReminder = _reminder_for(1)
	var prompt: BreakPrompt = BreakPrompt.new()
	var problem: String = ""
	reminder.advance(THIRTY_MIN_S, true)
	if not prompt.show_if(reminder):
		problem = "not shown when due"
	reminder.set_enabled(false)
	if problem == "" and prompt.show_if(reminder):
		problem = "still shown after switching off"
	reminder.advance(3.0 * THIRTY_MIN_S, true)
	if problem == "" and prompt.show_if(reminder):
		problem = "shown while switched off"
	prompt.free()
	return problem


func test_file_switch_off_is_applied_to_the_reminder() -> String:
	var look: Dictionary = BreakPromptLook.parse(_text_with("enabled", false))
	if look.has("error"):
		return "file with enabled false rejected: %s" % look["error"]
	var prompt: BreakPrompt = BreakPrompt.new(look)
	var reminder: BreakReminder = _reminder_for(2)
	prompt.apply_setting(reminder)
	var problem: String = ""
	if reminder.is_enabled():
		problem = "\"enabled\": false did not switch the reminder off"
	reminder.advance(2.0 * THIRTY_MIN_S, true)
	if problem == "" and prompt.show_if(reminder):
		problem = "shown with reminders switched off in the file"
	var on: BreakPrompt = BreakPrompt.new()
	on.apply_setting(reminder)
	if problem == "" and not reminder.is_enabled():
		problem = "the shipped file did not switch the reminder on"
	on.free()
	prompt.free()
	return problem


func test_acknowledge_while_hidden_keeps_the_count() -> String:
	var reminder: BreakReminder = _reminder_for(1)
	var prompt: BreakPrompt = BreakPrompt.new()
	reminder.advance(600.0, true)
	prompt.show_if(reminder)
	var dismissed: bool = prompt.acknowledge()
	var flown: float = reminder.flown_seconds()
	prompt.free()
	if dismissed:
		return "acknowledge reported a dismiss while hidden"
	if not is_equal_approx(flown, 600.0):
		return "acknowledge while hidden reset the count to %s s" % flown
	return ""


func test_text_says_time_flown_how_to_dismiss_and_switch_off() -> String:
	var reminder: BreakReminder = _reminder_for(1)
	var prompt: BreakPrompt = BreakPrompt.new()
	reminder.advance(THIRTY_MIN_S + 20.0, true)
	prompt.show_if(reminder, true)
	var xr_text: String = prompt.body_text()
	prompt.show_if(reminder, false)
	var flat_text: String = prompt.body_text()
	var title: String = prompt.title_text()
	prompt.free()
	if title.strip_edges() == "":
		return "no title"
	if not xr_text.contains("30 minutes"):
		return "body does not say 30 minutes: %s" % xr_text
	if not xr_text.contains("Press A") or not flat_text.contains("Press Enter"):
		return "dismiss line does not follow the input: %s / %s" % [xr_text, flat_text]
	if not xr_text.contains("switched off"):
		return "body does not say reminders can be switched off: %s" % xr_text
	return ""


func test_sits_below_line_of_sight_and_never_moves() -> String:
	var reminder: BreakReminder = _reminder_for(1)
	var prompt: BreakPrompt = BreakPrompt.new()
	var before: Transform3D = prompt.transform
	reminder.advance(THIRTY_MIN_S, true)
	prompt.show_if(reminder)
	prompt.acknowledge()
	var after: Transform3D = prompt.transform
	prompt.free()
	if before.origin.y >= 0.0 or before.origin.z >= 0.0:
		return "prompt is not below and ahead of the eye: %s" % before.origin
	if before.origin.length() > BreakPromptLook.MAX_DISTANCE_M:
		return "prompt is outside the ship's collision sphere"
	if not after.is_equal_approx(before):
		return "showing or dismissing moved the prompt"
	return ""


func test_showing_changes_nothing_in_the_reminder() -> String:
	var reminder: BreakReminder = _reminder_for(1)
	var prompt: BreakPrompt = BreakPrompt.new()
	reminder.advance(THIRTY_MIN_S, true)
	for i: int in 5:
		prompt.show_if(reminder)
	var due: bool = reminder.due()
	var flown: float = reminder.flown_seconds()
	prompt.free()
	if not due or not is_equal_approx(flown, THIRTY_MIN_S):
		return "show_if changed the reminder: due %s, %s s flown" % [due, flown]
	return ""


func test_bad_values_are_reported() -> String:
	var cases: Dictionary = {
		"enabled": 1,
		"position_m": [0.0, 0.1, -0.5],
		"tilt_deg": 120,
		"pixel_size": "small",
		"title_font": 12.5,
		"body_color": [1.0, 2.0, 0.0],
		"flown_text": "You have flown a while.",
		"off_text": "",
	}
	for key: String in cases:
		var look: Dictionary = BreakPromptLook.parse(_text_with(key, cases[key]))
		if not look.has("error"):
			return "bad \"%s\" was accepted" % key
		if not (look["error"] as String).contains(key):
			return "error for \"%s\" does not name it: %s" % [key, look["error"]]
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data.erase("title_text")
	if not BreakPromptLook.parse(JSON.stringify(data)).has("error"):
		return "missing key was accepted"
	data = JSON.parse_string(_shipped_text())
	data["colour"] = [1, 1, 1]
	if not BreakPromptLook.parse(JSON.stringify(data)).has("error"):
		return "unknown key was accepted"
	if not BreakPromptLook.parse("{nope").has("error"):
		return "broken JSON was accepted"
	return ""


func test_missing_file_is_reported_and_falls_back() -> String:
	var look: Dictionary = BreakPromptLook.load_file("user://no_such_break_prompt.json")
	if not look.has("error") or not (look["error"] as String).contains("no_such_break_prompt"):
		return "missing file not reported: %s" % look.get("error", "")
	var prompt: BreakPrompt = BreakPrompt.new(look)
	var reported: String = prompt.look_error()
	var on: bool = prompt.enabled_by_default()
	prompt.free()
	if reported == "":
		return "prompt built from a missing file reports no error"
	if not on:
		return "fallback should keep reminders on"
	return ""
