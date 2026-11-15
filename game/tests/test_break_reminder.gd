extends RefCounted

## The "take a break" reminder (CMF-10): when it falls due, what counts towards
## it, and how the preset files carry its interval (CMF-1, ARC-4). It stays out
## of the simulation (CMF-6, ARC-3).

const SCRIPT_PATH: String = "res://xr/break_reminder.gd"
const CORE_DIR: String = "res://core"
const SCRATCH_DIR: String = "user://test_break_reminder"
const STEP_S: float = 1.0 / 60.0
const THIRTY_MIN_S: float = 30.0 * 60.0


static func reminder_for(number: int) -> BreakReminder:
	return BreakReminder.new(ComfortPresetFiles.load_number(number))


## Advances in 60 Hz steps, as the game would.
static func fly_ticks(reminder: BreakReminder, ticks: int) -> void:
	for i: int in ticks:
		reminder.advance(STEP_S, true)


func test_due_at_exactly_thirty_minutes_on_presets_1_to_3() -> String:
	for number: int in [1, 2, 3]:
		var reminder: BreakReminder = reminder_for(number)
		fly_ticks(reminder, 30 * 60 * 60 - 1)
		if reminder.due():
			return "preset %d: due one tick before 30 minutes" % number
		fly_ticks(reminder, 1)
		if not reminder.due():
			return "preset %d: not due after exactly 30 minutes of 60 Hz ticks" % number
		var whole: BreakReminder = reminder_for(number)
		whole.advance(THIRTY_MIN_S - 0.001, true)
		if whole.due():
			return "preset %d: due at 29:59.999" % number
		whole.advance(0.001, true)
		if not whole.due():
			return "preset %d: not due at 30:00 in large steps" % number
	return ""


func test_never_due_on_preset_4() -> String:
	var reminder: BreakReminder = reminder_for(4)
	for hour: int in 10:
		reminder.advance(3600.0, true)
		if reminder.due():
			return "preset 4 became due after %d hours" % (hour + 1)
	return ""


func test_paused_time_does_not_count() -> String:
	var reminder: BreakReminder = reminder_for(1)
	reminder.advance(THIRTY_MIN_S - 60.0, true)
	reminder.advance(3600.0, false)
	if reminder.due():
		return "an hour paused made the reminder due"
	if not is_equal_approx(reminder.flown_seconds(), THIRTY_MIN_S - 60.0):
		return "paused time was counted: %s s flown" % reminder.flown_seconds()
	reminder.advance(60.0, true)
	if not reminder.due():
		return "not due once the flying time reached 30 minutes"
	return ""


func test_acknowledge_restarts_the_interval() -> String:
	var reminder: BreakReminder = reminder_for(2)
	reminder.advance(THIRTY_MIN_S + 120.0, true)
	if not reminder.due():
		return "not due after 32 minutes"
	reminder.acknowledge()
	if reminder.due():
		return "still due after acknowledge"
	if reminder.flown_seconds() != 0.0:
		return "the next interval starts at %s s, expected 0" % reminder.flown_seconds()
	reminder.advance(THIRTY_MIN_S - 1.0, true)
	if reminder.due():
		return "due before a full new interval (the overrun carried over)"
	reminder.advance(1.0, true)
	if not reminder.due():
		return "not due after a full second interval"
	return ""


func test_switching_off_clears_a_pending_prompt() -> String:
	var reminder: BreakReminder = reminder_for(3)
	reminder.advance(THIRTY_MIN_S, true)
	if not reminder.due():
		return "not due after 30 minutes"
	reminder.set_enabled(false)
	if reminder.due():
		return "still due after switching off"
	reminder.advance(2.0 * THIRTY_MIN_S, true)
	if reminder.due():
		return "became due while switched off"
	reminder.set_enabled(true)
	if reminder.due():
		return "due at once on switching back on"
	reminder.advance(THIRTY_MIN_S, true)
	if not reminder.due():
		return "not due 30 minutes after switching back on"
	return ""


func test_preset_change_keeps_elapsed_time() -> String:
	var reminder: BreakReminder = reminder_for(1)
	reminder.advance(20.0 * 60.0, true)
	reminder.set_preset(ComfortPresetFiles.load_number(3))
	if not is_equal_approx(reminder.flown_seconds(), 20.0 * 60.0):
		return "the preset change reset the count to %s s" % reminder.flown_seconds()
	reminder.advance(10.0 * 60.0, true)
	if not reminder.due():
		return "not due after 20 minutes on preset 1 and 10 on preset 3"
	return ""


func test_change_to_preset_4_stops_reminders() -> String:
	var reminder: BreakReminder = reminder_for(2)
	reminder.advance(THIRTY_MIN_S, true)
	reminder.set_preset(ComfortPresetFiles.load_number(4))
	if reminder.due():
		return "a pending prompt survived the change to preset 4"
	reminder.advance(3.0 * THIRTY_MIN_S, true)
	if reminder.due():
		return "due on preset 4"
	return ""


func test_shipped_presets_carry_the_interval() -> String:
	var wanted: Array[float] = [30.0, 30.0, 30.0, 0.0]
	for index: int in wanted.size():
		var preset: ComfortPreset = ComfortPresetFiles.load_number(index + 1)
		if preset == null:
			return "preset %d was rejected" % (index + 1)
		if preset.break_reminder_minutes != wanted[index]:
			return "preset %d break_reminder_minutes is %s, expected %s" \
				% [index + 1, preset.break_reminder_minutes, wanted[index]]
	return ""


func test_invalid_value_rejects_the_preset_file() -> String:
	var cases: Dictionary[String, String] = {
		"negative": "break_reminder_minutes = -5.0\n",
		"text": "break_reminder_minutes = \"thirty\"\n",
		"missing": "",
	}
	for case_name: String in cases:
		var path: String = _write_variant(case_name, cases[case_name])
		if path.is_empty():
			return "could not write the %s case" % case_name
		if ComfortPresetFiles.load_path(path) != null:
			return "a preset file with a %s break_reminder_minutes was accepted" % case_name
	var zero: String = _write_variant("zero", "break_reminder_minutes = 0\n")
	if ComfortPresetFiles.load_path(zero) == null:
		return "a preset file with break_reminder_minutes = 0 was rejected"
	return ""


func test_reads_nothing_from_the_simulation() -> String:
	var script: GDScript = load(SCRIPT_PATH) as GDScript
	if script.get_instance_base_type() != &"RefCounted":
		return "BreakReminder extends %s, expected RefCounted" % script.get_instance_base_type()
	var text: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	if text.contains(CORE_DIR):
		return "break_reminder.gd refers to %s" % CORE_DIR
	var declares: RegEx = RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var checked: int = 0
	for file: String in DirAccess.get_files_at(CORE_DIR):
		if not file.ends_with(".gd"):
			continue
		var found: RegExMatch = declares.search(FileAccess.get_file_as_string(CORE_DIR.path_join(file)))
		if found == null:
			continue
		checked += 1
		if RegEx.create_from_string("\\b%s\\b" % found.get_string(1)).search(text) != null:
			return "break_reminder.gd refers to the core class %s" % found.get_string(1)
	for word: String in ["Time.", "OS.get_ticks", "get_tree", "Engine."]:
		if text.contains(word):
			return "break_reminder.gd reads its own clock or the scene (%s)" % word
	return "" if checked > 0 else "no core classes were read"


## Writes preset 1 with its `break_reminder_minutes` line replaced by `line`.
## Returns the path, or "" when it could not be written.
static func _write_variant(case_name: String, line: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var source: String = FileAccess.get_file_as_string(ComfortPresetFiles.PATHS[0])
	var lines: PackedStringArray = source.split("\n")
	var out: PackedStringArray = PackedStringArray()
	for text: String in lines:
		if not text.begins_with("break_reminder_minutes = "):
			out.append(text)
	var path: String = "%s/comfort_%s.tres" % [SCRATCH_DIR, case_name]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string("\n".join(out).strip_edges(false, true) + "\n" + line)
	file.close()
	return path
