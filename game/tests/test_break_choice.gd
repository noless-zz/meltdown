extends RefCounted

## The take-a-break reminder's on/off choice (CMF-10, #820): saved and loaded,
## a bad file ignored by name, the launch switch beating the file, and
## `BreakPromptWiring.set_enabled` hiding the prompt at once and for good while
## off, without touching the simulation (CMF-6, ARC-3).

const SCRATCH_DIR: String = "user://test_break_choice"
const MINUTE: float = 60.0
const STEP: float = 1.0


static func scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


static func write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _wired(path: String) -> BreakPromptWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.set_preset(3)
	var wiring: BreakPromptWiring = BreakPromptWiring.new()
	wiring.choice = BreakChoice.new(path)
	wiring.attach(null, comfort)
	return wiring


static func _fly(wiring: BreakPromptWiring, seconds: float) -> void:
	for i: int in roundi(seconds / STEP):
		wiring.update(STEP, true, true)


func test_default_path() -> String:
	if BreakChoice.DEFAULT_PATH != "user://meltdown_break.json":
		return "default path is %s" % BreakChoice.DEFAULT_PATH
	return ""


func test_save_and_load() -> String:
	var path: String = scratch("round_trip.json")
	for enabled: bool in [false, true]:
		var choice: BreakChoice = BreakChoice.new(path)
		if not choice.save(enabled):
			return "could not save %s" % enabled
		if BreakChoice.new(path).load_saved(not enabled) != enabled:
			return "saved %s, read back the other" % enabled
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data != {"enabled": enabled}:
			return "the file holds %s, expected only enabled (CMF-6)" % str(data)
	return ""


func test_no_file_gives_the_data_file_default() -> String:
	var path: String = scratch("missing.json")
	for fallback: bool in [false, true]:
		var choice: BreakChoice = BreakChoice.new(path)
		if choice.load_saved(fallback) != fallback or not choice.warnings.is_empty():
			return "no file did not give the default %s quietly" % fallback
	return ""


func test_a_bad_file_is_ignored_with_a_warning_naming_it() -> String:
	var path: String = scratch("bad.json")
	for text: String in ["{", "[true]", "{\"enabled\": 1}", "{\"enabled\": \"off\"}",
			"{\"enabled\": false, \"speed\": 2}", "{}"]:
		write(path, text)
		var choice: BreakChoice = BreakChoice.new(path)
		if choice.load_saved(true) != true:
			return "%s was not ignored" % text
		if choice.warnings.size() != 1 or not choice.warnings[0].contains(path):
			return "%s gave warnings %s" % [text, str(choice.warnings)]
	return ""


func test_launch_switch_beats_the_file_and_is_saved() -> String:
	var path: String = scratch("switch.json")
	var choice: BreakChoice = BreakChoice.new(path)
	choice.save(true)
	if choice.for_launch(true, PackedStringArray(["--break-reminder=off"]), "") != false:
		return "--break-reminder=off did not switch it off"
	if BreakChoice.new(path).load_saved(true) != false:
		return "the switch was not saved"
	if choice.for_launch(true, PackedStringArray(), "on") != true:
		return "the intent extra on did not switch it on"
	if choice.for_launch(true, PackedStringArray(["--break-reminder=off"]), "on") != false:
		return "the argument did not win over the intent extra"
	if BreakChoice.new(path).for_launch(true, PackedStringArray(), "") != false:
		return "a later start without the switch did not keep it off"
	return ""


func test_a_bad_switch_value_is_ignored_with_a_warning() -> String:
	var path: String = scratch("bad_switch.json")
	BreakChoice.new(path).save(false)
	for asked: String in ["maybe", "ON", "1"]:
		var choice: BreakChoice = BreakChoice.new(path)
		if choice.for_launch(true, PackedStringArray(["--break-reminder=" + asked]), "") != false:
			return "\"%s\" changed the saved choice" % asked
		if choice.warnings.size() != 1 or not choice.warnings[0].contains("\"%s\"" % asked):
			return "\"%s\" gave warnings %s" % [asked, str(choice.warnings)]
	return ""


func test_a_saved_off_keeps_the_prompt_away() -> String:
	var path: String = scratch("saved_off.json")
	BreakChoice.new(path).save(false)
	var wiring: BreakPromptWiring = _wired(path)
	_fly(wiring, 60.0 * MINUTE)
	var shown: bool = wiring.shown()
	wiring.prompt.free()
	return "shown with the reminder saved off" if shown else ""


func test_set_enabled_off_hides_a_showing_prompt_for_good() -> String:
	var path: String = scratch("set_off.json")
	var wiring: BreakPromptWiring = _wired(path)
	_fly(wiring, 30.0 * MINUTE)
	if not wiring.shown():
		wiring.prompt.free()
		return "not shown after 30 minutes with the reminder on"
	wiring.set_enabled(false)
	var hidden_at_once: bool = not wiring.shown() and not wiring.prompt.visible
	_fly(wiring, 30.0 * MINUTE)
	var still_hidden: bool = not wiring.shown()
	wiring.prompt.free()
	if not hidden_at_once:
		return "set_enabled(false) left the prompt showing"
	if not still_hidden:
		return "the prompt came back 30 minutes after being switched off"
	if BreakChoice.new(path).load_saved(true) != false:
		return "set_enabled(false) was not saved"
	return ""


func test_on_again_shows_it_when_due() -> String:
	var path: String = scratch("on_again.json")
	BreakChoice.new(path).save(false)
	var wiring: BreakPromptWiring = _wired(path)
	_fly(wiring, 10.0 * MINUTE)
	wiring.set_enabled(true)
	var at_once: bool = wiring.shown()
	_fly(wiring, 30.0 * MINUTE - STEP)
	var early: bool = wiring.shown()
	_fly(wiring, STEP)
	var due: bool = wiring.shown()
	wiring.prompt.free()
	if at_once or early:
		return "on again showed the prompt before a whole interval"
	if not due:
		return "on again did not show the prompt after 30 minutes"
	if BreakChoice.new(path).load_saved(false) != true:
		return "set_enabled(true) was not saved"
	return ""


func test_the_off_line_says_how() -> String:
	var look: Dictionary = BreakPromptLook.load_file()
	if look.has("error") or not str(look["off_text"]).contains("menu"):
		return "off_text \"%s\" does not say to use the menu" % look["off_text"]
	return ""


func test_stays_out_of_the_simulation() -> String:
	var text: String = FileAccess.get_file_as_string("res://xr/break_choice.gd")
	for word: String in ["res://core", "SimState", "ShipState", "LocalSession", "paused"]:
		if text.contains(word):
			return "break_choice.gd mentions %s" % word
	return ""
