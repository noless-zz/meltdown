extends RefCounted

## The custom comfort mode chosen in the game (CMF-1, #806): the preset button
## reaches it only with an accepted file, the launch switch starts in it, the
## saved choice keeps it and falls back to its base, and it feeds everything a
## numbered preset does (CMF-7 swivel, PRF-1 refresh rate) without touching the
## simulation (CMF-6, ARC-3).

const SCRATCH_DIR: String = "user://test_comfort_custom_choice"
const X: String = "left_button_lower"
const CUSTOM: int = ComfortPresetFiles.CUSTOM_NUMBER


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


## A comfort wiring reading its custom file from `custom_text` ("" for none).
static func comfort(custom_text: String, name: String) -> ComfortWiring:
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	wiring.custom_path = scratch(name)
	if custom_text != "":
		write(wiring.custom_path, custom_text)
	return wiring


## The presets the button visits from preset 1, `presses` presses long.
static func cycle(wiring: ComfortWiring, presses: int) -> Array[int]:
	wiring.set_preset(1)
	var seen: Array[int] = [wiring.number]
	for i: int in presses:
		wiring.read_preset_button({X: true})
		wiring.read_preset_button({})
		seen.append(wiring.number)
	return seen


func test_custom_is_the_fifth_place_in_the_cycle() -> String:
	if CUSTOM != 5:
		return "CUSTOM_NUMBER is %d, expected 5" % CUSTOM
	return ""


func test_button_cycles_through_custom_with_an_accepted_file() -> String:
	var wiring: ComfortWiring = comfort("{\"base\": 3, \"display_name\": \"Mine\"}", "good.json")
	var seen: Array[int] = cycle(wiring, 6)
	if seen != [1, 2, 3, 4, CUSTOM, 1, 2]:
		return "with a file the button visits %s" % str(seen)
	wiring.set_preset(CUSTOM)
	if wiring.preset.display_name != "Mine" or wiring.preset != wiring.custom().preset:
		return "the custom mode is %s, not the file's preset" % wiring.preset.display_name
	return ""


func test_button_cycles_one_to_four_without_a_file() -> String:
	var seen: Array[int] = cycle(comfort("", "none.json"), 5)
	if seen != [1, 2, 3, 4, 1, 2]:
		return "without a file the button visits %s" % str(seen)
	return ""


func test_a_rejected_file_is_not_offered_and_its_field_is_named() -> String:
	var wiring: ComfortWiring = comfort("{\"base\": 3, \"pitch_mode\": \"SIDEWAYS\"}", "rejected.json")
	var seen: Array[int] = cycle(wiring, 5)
	if seen != [1, 2, 3, 4, 1, 2]:
		return "with a rejected file the button visits %s" % str(seen)
	if not wiring.custom().error.contains("\"pitch_mode\""):
		return "the rejection \"%s\" does not name pitch_mode" % wiring.custom().error
	return ""


func test_the_file_is_read_once_so_a_rejection_is_logged_once() -> String:
	var wiring: ComfortWiring = comfort("{\"base\": 9}", "once.json")
	var first: ComfortCustom = wiring.custom()
	cycle(wiring, 10)
	if wiring.custom() != first:
		return "the custom file was read again"
	if not first.error.contains("\"base\""):
		return "the rejection \"%s\" does not name base" % first.error
	return ""


func test_custom_without_a_file_keeps_the_current_preset() -> String:
	var wiring: ComfortWiring = comfort("", "keep.json")
	wiring.set_preset(3)
	wiring.set_preset(CUSTOM)
	if wiring.number != 3 or wiring.preset.display_name != ComfortPresetFiles.load_number(3).display_name:
		return "custom without a file left preset %d %s" % [wiring.number, wiring.preset.display_name]
	return ""


func test_launch_switch_argument_and_intent() -> String:
	if not ComfortSwitch.parse(PackedStringArray(["--comfort=custom"]), "").custom:
		return "--comfort=custom was not taken"
	if not ComfortSwitch.parse(PackedStringArray(), "custom").custom:
		return "the intent extra custom was not taken"
	if not ComfortSwitch.parse(PackedStringArray(["--comfort=custom"]), "nonsense").custom:
		return "the argument did not win over the intent extra"
	var none: ComfortSwitch = ComfortSwitch.parse(PackedStringArray(["--comfort-preset=3"]), "")
	if none.custom or not none.warnings.is_empty():
		return "--comfort-preset alone switched the custom mode or warned"
	if none.number(PackedStringArray(["--comfort-preset=3"])) != 3:
		return "without the switch --comfort-preset=3 gave %d" % none.number(PackedStringArray(["--comfort-preset=3"]))
	if ComfortSwitch.parse(PackedStringArray(["--comfort=custom"]), "").number(PackedStringArray()) != CUSTOM:
		return "the switch did not start in the custom mode"
	return ""


func test_launch_switch_bad_value_is_ignored_with_a_warning_naming_it() -> String:
	var cases: Dictionary = {"--comfort=Custom": "", "--comfort=5": "", "": "fancy"}
	for arg: String in cases:
		var args: PackedStringArray = PackedStringArray([arg]) if arg != "" else PackedStringArray()
		var switch: ComfortSwitch = ComfortSwitch.parse(args, cases[arg])
		var value: String = arg.trim_prefix(ComfortSwitch.ARG_PREFIX) if arg != "" else cases[arg]
		if switch.custom:
			return "\"%s\" switched the custom mode" % value
		if switch.warnings.size() != 1 or not switch.warnings[0].contains("\"%s\"" % value):
			return "\"%s\" gave warnings %s" % [value, str(switch.warnings)]
		if switch.number(args) != ComfortPresetFiles.START_NUMBER:
			return "\"%s\" changed the start preset" % value
	return ""


func test_a_custom_launch_leaves_the_saved_choice_alone() -> String:
	if FlightTestWiring.start_for(PackedStringArray(), "", "", true) != FlightTestWiring.Start.OFF:
		return "a custom launch would run the flight test or read the saved choice"
	if FlightTestWiring.start_for(PackedStringArray(), "", "", false) != FlightTestWiring.Start.TUNNEL:
		return "a plain tunnel start changed"
	return ""


func test_choice_saves_and_restores_the_custom_mode() -> String:
	var path: String = scratch("choice_round_trip.json")
	var choice: ComfortChoice = ComfortChoice.new()
	choice.finish_test(2)
	if not choice.set_custom(3) or not choice.save_to(path):
		return "the custom mode could not be chosen and saved"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var keys: Array = data.keys()
	keys.sort()
	if keys != ["custom_base", "flight_test_done", "preset"] or data["preset"] != "custom":
		return "the saved custom choice is %s" % str(data)
	var back: ComfortChoice = ComfortChoice.new()
	back.load_from(path)
	if back.preset() != CUSTOM or back.custom_base() != 3 or back.first_launch() or back.load_error() != "":
		return "read back preset %d base %d error \"%s\"" % [back.preset(), back.custom_base(), back.load_error()]
	if back.set_custom(0) or back.set_custom(5) or back.set_preset(CUSTOM):
		return "a bad base or a bare custom number was accepted"
	back.set_preset(4)
	back.save_to(path)
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data.has("custom_base"):
		return "a numbered preset was saved with a custom base"
	return ""


func test_choice_rejects_a_bad_custom_entry_by_field() -> String:
	var cases: Dictionary = {
		"{\"preset\": \"custom\", \"flight_test_done\": true}": "custom_base",
		"{\"preset\": \"custom\", \"custom_base\": 7, \"flight_test_done\": true}": "custom_base",
		"{\"preset\": \"custom\", \"custom_base\": \"3\", \"flight_test_done\": true}": "custom_base",
		"{\"preset\": 3, \"custom_base\": 3, \"flight_test_done\": true}": "custom_base",
		"{\"preset\": \"Custom\", \"custom_base\": 3, \"flight_test_done\": true}": "preset",
	}
	var path: String = scratch("choice_bad.json")
	for text: String in cases:
		write(path, text)
		var choice: ComfortChoice = ComfortChoice.new()
		choice.load_from(path)
		if choice.preset() != ComfortPresetFiles.START_NUMBER or not choice.first_launch():
			return "%s was not treated as missing" % text
		if not choice.load_error().contains("\"%s\"" % cases[text]):
			return "%s: error \"%s\" does not name %s" % [text, choice.load_error(), cases[text]]
	return ""


## A flight-test wiring begun from the saved choice `choice_text`, applying to `wiring`.
static func restored(choice_text: String, wiring: ComfortWiring, name: String) -> FlightTestWiring:
	var wired: FlightTestWiring = FlightTestWiring.new()
	wired.choice_path = scratch(name)
	write(wired.choice_path, choice_text)
	wired.begin(FlightTestWiring.Start.SAVED, wiring, wiring.set_preset)
	return wired


func test_saved_custom_is_restored_and_falls_back_to_its_base() -> String:
	var text: String = "{\"preset\": \"custom\", \"custom_base\": 3, \"flight_test_done\": true}"
	var with_file: ComfortWiring = comfort("{\"base\": 3, \"swivel_enabled\": true}", "restore.json")
	restored(text, with_file, "restore_choice.json")
	if with_file.number != CUSTOM:
		return "with the file the saved custom mode came back as preset %d" % with_file.number
	var gone: ComfortWiring = comfort("", "gone.json")
	var wired: FlightTestWiring = restored(text, gone, "gone_choice.json")
	if gone.number != 3:
		return "without the file the saved custom mode gave preset %d, expected its base 3" % gone.number
	wired.update(1.0 / 90.0, false)
	var back: ComfortChoice = ComfortChoice.new()
	back.load_from(wired.choice_path)
	if back.preset() != CUSTOM:
		return "falling back overwrote the saved custom choice with preset %d" % back.preset()
	return ""


func test_pressing_into_custom_saves_it_with_its_base() -> String:
	var wiring: ComfortWiring = comfort("{\"base\": 1}", "press.json")
	var wired: FlightTestWiring = restored("{\"preset\": 4, \"flight_test_done\": true}", wiring, "press_choice.json")
	wiring.read_preset_button({X: true})
	wired.update(1.0 / 90.0, false)
	var back: ComfortChoice = ComfortChoice.new()
	back.load_from(wired.choice_path)
	if wiring.number != CUSTOM or back.preset() != CUSTOM or back.custom_base() != 1:
		return "after X from 4: active %d, saved %d base %d" % [wiring.number, back.preset(), back.custom_base()]
	return ""


func test_custom_file_with_swivel_gives_swivel_on() -> String:
	var wiring: ComfortWiring = comfort("{\"base\": 3, \"swivel_enabled\": true}", "swivel.json")
	wiring.set_preset(CUSTOM)
	if not wiring.preset.swivel_enabled:
		return "the custom preset has swivel off"
	if wiring.preset.yaw_mode != ComfortPresetFiles.load_number(3).yaw_mode:
		return "the custom preset lost its base's rows"
	if ComfortPresetFiles.load_number(3).swivel_enabled:
		return "the shipped preset 3 was changed"
	return ""


func test_custom_feeds_filter_cockpit_shake_and_refresh_rate() -> String:
	var text: String = "{\"base\": 4, \"allow_120_hz\": true, \"refresh_rate_hz\": 120, \"yaw_mode\": \"SNAP\"}"
	var wiring: ComfortWiring = comfort(text, "feeds.json")
	wiring.set_preset(CUSTOM)
	if RefreshRate.target_hz(wiring.preset) != 120.0:
		return "the custom preset asks for %s Hz, expected 120" % RefreshRate.target_hz(wiring.preset)
	if wiring.filter.preset != wiring.preset:
		return "the input filter does not use the custom preset"
	if wiring.hit_shake != null and wiring.hit_shake.preset != wiring.preset:
		return "the hit shake does not use the custom preset"
	if wiring.cockpit_spec().error != "":
		return "the custom preset's cockpit was rejected: %s" % wiring.cockpit_spec().error
	return ""


func test_numbered_presets_are_unchanged_with_a_custom_file() -> String:
	var wiring: ComfortWiring = comfort("{\"base\": 2, \"swivel_enabled\": true}", "numbered.json")
	for number: int in [1, 2, 3, 4]:
		wiring.set_preset(number)
		var shipped: ComfortPreset = ComfortPresetFiles.load_number(number)
		if wiring.number != number or wiring.preset != shipped:
			return "preset %d is not the shipped file with a custom file present" % number
	return ""


func test_the_switch_stays_out_of_the_simulation() -> String:
	var text: String = FileAccess.get_file_as_string("res://xr/comfort_switch.gd")
	for word: String in ["res://core", "SimState", "ShipState", "Sim.", "Node"]:
		if text.contains(word):
			return "comfort_switch.gd mentions %s" % word
	return ""
