extends RefCounted

## The saved comfort choice (CMF-4): first launch, round trip, rejecting bad
## files by field, and holding nothing that changes the simulation (CMF-6).

const SCRIPT_PATH: String = "res://xr/comfort_choice.gd"
const SCRATCH_DIR: String = "user://test_comfort_choice"


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


func test_missing_file_is_first_launch_with_the_default_preset() -> String:
	var choice: ComfortChoice = ComfortChoice.new()
	choice.load_from(scratch("missing.json"))
	if not choice.first_launch():
		return "a missing file was not a first launch"
	if choice.preset() != 2:
		return "preset %d on first launch, expected 2" % choice.preset()
	if choice.preset() != ComfortPresetFiles.START_NUMBER:
		return "first-launch preset differs from ComfortPresetFiles.START_NUMBER"
	if not choice.load_error().is_empty():
		return "a missing file was reported as an error: %s" % choice.load_error()
	return ""


func test_default_path_is_the_meltdown_comfort_file() -> String:
	if ComfortChoice.DEFAULT_PATH != "user://meltdown_comfort.json":
		return "default path is %s" % ComfortChoice.DEFAULT_PATH
	return ""


func test_round_trip() -> String:
	var path: String = scratch("round_trip.json")
	for number: int in [1, 2, 3, 4]:
		for done: bool in [false, true]:
			var choice: ComfortChoice = ComfortChoice.new()
			if done:
				choice.finish_test(number)
			else:
				choice.set_preset(number)
			if not choice.save_to(path):
				return "could not save %s" % path
			var back: ComfortChoice = ComfortChoice.new()
			back.load_from(path)
			if back.preset() != number or back.first_launch() == done:
				return "saved preset %d done %s, read back preset %d first launch %s" % [
					number, done, back.preset(), back.first_launch()]
			if not back.load_error().is_empty():
				return "a saved file was rejected: %s" % back.load_error()
	return ""


func test_saving_after_the_test_marks_it_done() -> String:
	var path: String = scratch("after_test.json")
	var choice: ComfortChoice = ComfortChoice.new()
	choice.load_from(path)
	if not choice.first_launch():
		return "not a first launch before the test"
	if not choice.finish_test(3):
		return "finish_test(3) refused"
	choice.save_to(path)
	var next_start: ComfortChoice = ComfortChoice.new()
	next_start.load_from(path)
	if next_start.first_launch():
		return "the next start was still a first launch"
	if next_start.preset() != 3:
		return "the next start has preset %d, expected the recommended 3" % next_start.preset()
	# Changing preset later (an X press) keeps the test done.
	next_start.set_preset(1)
	next_start.save_to(path)
	var third: ComfortChoice = ComfortChoice.new()
	third.load_from(path)
	if third.first_launch() or third.preset() != 1:
		return "a later preset change was not kept: preset %d, first launch %s" % [third.preset(), third.first_launch()]
	return ""


func test_skipped_test_saves_preset_1_and_done() -> String:
	var path: String = scratch("skipped.json")
	var choice: ComfortChoice = ComfortChoice.new()
	choice.finish_test(1)
	choice.save_to(path)
	var back: ComfortChoice = ComfortChoice.new()
	back.load_from(path)
	if back.first_launch() or back.preset() != 1:
		return "a skipped test read back as preset %d, first launch %s" % [back.preset(), back.first_launch()]
	return ""


func test_each_bad_value_is_rejected_naming_the_field() -> String:
	var cases: Dictionary = {
		"{\"preset\": 0, \"flight_test_done\": true}": "preset",
		"{\"preset\": 5, \"flight_test_done\": true}": "preset",
		"{\"preset\": 2.5, \"flight_test_done\": true}": "preset",
		"{\"preset\": \"3\", \"flight_test_done\": true}": "preset",
		"{\"preset\": null, \"flight_test_done\": true}": "preset",
		"{\"flight_test_done\": true}": "preset",
		"{\"preset\": 3, \"flight_test_done\": \"yes\"}": "flight_test_done",
		"{\"preset\": 3, \"flight_test_done\": 1}": "flight_test_done",
		"{\"preset\": 3}": "flight_test_done",
		"{\"preset\": 3, \"flight_test_done\": true, \"speed\": 2}": "speed",
	}
	var path: String = scratch("bad.json")
	for text: String in cases:
		write(path, text)
		var choice: ComfortChoice = ComfortChoice.new()
		choice.load_from(path)
		var field: String = cases[text]
		if not choice.first_launch() or choice.preset() != ComfortPresetFiles.START_NUMBER:
			return "%s was not treated as missing (preset %d, first launch %s)" % [text, choice.preset(), choice.first_launch()]
		if not choice.load_error().contains("\"%s\"" % field):
			return "%s: error \"%s\" does not name %s" % [text, choice.load_error(), field]
	return ""


func test_unreadable_file_is_first_launch() -> String:
	var path: String = scratch("garbled.json")
	for text: String in ["", "not json {", "[3, true]", "7"]:
		write(path, text)
		var choice: ComfortChoice = ComfortChoice.new()
		choice.load_from(path)
		if not choice.first_launch() or choice.preset() != ComfortPresetFiles.START_NUMBER:
			return "\"%s\" was not treated as missing" % text
		if choice.load_error().is_empty():
			return "\"%s\" was not reported" % text
	return ""


func test_bad_file_after_a_good_load_resets_to_first_launch() -> String:
	var path: String = scratch("good_then_bad.json")
	var choice: ComfortChoice = ComfortChoice.new()
	choice.finish_test(4)
	choice.save_to(path)
	choice.load_from(path)
	write(path, "{\"preset\": 9, \"flight_test_done\": true}")
	choice.load_from(path)
	if not choice.first_launch() or choice.preset() != ComfortPresetFiles.START_NUMBER:
		return "a bad file kept the earlier choice: preset %d" % choice.preset()
	return ""


func test_set_preset_refuses_numbers_outside_1_to_4() -> String:
	var choice: ComfortChoice = ComfortChoice.new()
	choice.set_preset(3)
	for number: int in [0, 5, -1]:
		if choice.set_preset(number):
			return "set_preset(%d) was accepted" % number
		if choice.finish_test(number):
			return "finish_test(%d) was accepted" % number
	if choice.preset() != 3 or not choice.first_launch():
		return "a refused number changed the choice"
	return ""


func test_file_holds_only_the_preset_and_the_test_flag() -> String:
	var path: String = scratch("fields.json")
	var choice: ComfortChoice = ComfortChoice.new()
	choice.finish_test(2)
	choice.save_to(path)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return "saved file is not a JSON object"
	var keys: Array = (data as Dictionary).keys()
	keys.sort()
	if keys != ["flight_test_done", "preset"]:
		return "saved fields %s, expected only flight_test_done and preset (CMF-6)" % str(keys)
	return ""


func test_stays_out_of_the_simulation() -> String:
	var script: GDScript = load(SCRIPT_PATH) as GDScript
	if script.get_instance_base_type() != &"RefCounted":
		return "ComfortChoice extends %s, expected RefCounted" % script.get_instance_base_type()
	var text: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	for word: String in ["res://core", "SimState", "ShipState", "Node"]:
		if text.contains(word):
			return "comfort_choice.gd mentions %s" % word
	return ""
