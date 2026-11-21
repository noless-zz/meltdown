extends RefCounted

## The 120 Hz option on preset 4 (#838, PRF-1, CMF-1, CMF-6, ARC-3): the
## launch switch and the saved file, which beats which, the rate each preset
## asks for with the option on and off, the fallback when 120 is not offered,
## and the simulation left alone.

const FakeRuntime := preload("res://tests/fake_refresh_runtime.gd")
const SAVED_PATH: String = "user://test_meltdown_refresh.json"
const FRAME: float = 1.0 / 90.0


static func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(SAVED_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _remove() -> void:
	if FileAccess.file_exists(SAVED_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED_PATH))


static func _choice(on: bool) -> RefreshChoice:
	var choice: RefreshChoice = RefreshChoice.new()
	choice.on = on
	return choice


static func _rate(on: bool, offered: Array) -> Array:
	var runtime: RefCounted = FakeRuntime.new(offered, 72.0)
	var rate: RefreshRate = RefreshRate.new()
	rate.choice = _choice(on)
	rate.begin(runtime, ComfortPresetFiles.load_number(4))
	return [rate, runtime]


func test_the_switch_and_extra_are_parsed() -> String:
	var cases: Dictionary = {
		["--refresh=120"]: [true, ""],
		["--refresh=90"]: [false, ""],
		["--refresh=90", "--refresh=120"]: [true, ""],
		["--refresh=120", "--refresh=90"]: [false, ""],
		["--other"]: [false, "120"],
	}
	for args: Array in cases:
		var expected: Array = cases[args]
		var intent: String = expected[1]
		var choice: RefreshChoice = RefreshChoice.parse(PackedStringArray(args), intent)
		var on_wanted: bool = intent == "120" or bool(expected[0])
		if choice.on != on_wanted or not choice.from_switch or not choice.warnings.is_empty():
			return "%s with extra '%s' gave on %s, switch %s, warnings %s" % [
				args, intent, choice.on, choice.from_switch, choice.warnings]
	var argument_wins: RefreshChoice = RefreshChoice.parse(PackedStringArray(["--refresh=90"]), "120")
	if argument_wins.on:
		return "the intent extra beat the argument"
	var none: RefreshChoice = RefreshChoice.parse(PackedStringArray(), "")
	if none.on or none.from_switch or none.source != RefreshChoice.SOURCE_DEFAULT:
		return "no switch gave on %s, switch %s" % [none.on, none.from_switch]
	return ""


func test_a_bad_switch_value_is_warned_and_off() -> String:
	var choice: RefreshChoice = RefreshChoice.parse(PackedStringArray(["--refresh=144"]), "")
	if choice.on or choice.warnings.size() != 1 or not choice.warnings[0].contains("\"144\""):
		return "a bad value gave on %s, warnings %s" % [choice.on, choice.warnings]
	_write("{\"120_hz\": true}")
	choice.use_saved(SAVED_PATH)
	_remove()
	return "" if not choice.on else "a bad switch let the saved choice raise the rate"


func test_the_saved_file_is_read_and_a_bad_one_is_off() -> String:
	_write("{\"120_hz\": true}")
	var choice: RefreshChoice = RefreshChoice.new()
	choice.use_saved(SAVED_PATH)
	if not choice.on or choice.source != RefreshChoice.SOURCE_SAVED:
		_remove()
		return "the saved choice was not read: on %s, source %s" % [choice.on, choice.source]
	for bad: String in ["{\"120_hz\": \"yes\"}", "not json", "[]", "{\"120_hz\": true, \"x\": 1}", "{}"]:
		_write(bad)
		choice = RefreshChoice.new()
		choice.use_saved(SAVED_PATH)
		if choice.on or choice.warnings.size() != 1 or not choice.warnings[0].contains(SAVED_PATH):
			_remove()
			return "'%s' gave on %s, warnings %s" % [bad, choice.on, choice.warnings]
	_remove()
	choice = RefreshChoice.new()
	choice.use_saved(SAVED_PATH)
	return "" if not choice.on and choice.warnings.is_empty() else "no file was not quietly off"


func test_the_switch_beats_the_saved_choice() -> String:
	_write("{\"120_hz\": true}")
	var off: RefreshChoice = RefreshChoice.parse(PackedStringArray(["--refresh=90"]), "")
	off.use_saved(SAVED_PATH)
	_write("{\"120_hz\": false}")
	var on: RefreshChoice = RefreshChoice.parse(PackedStringArray(), "120")
	on.use_saved(SAVED_PATH)
	_remove()
	if off.on:
		return "the saved 120 beat --refresh=90"
	if not on.on or on.source != RefreshChoice.SOURCE_SWITCH:
		return "the saved off beat the extra 120"
	return ""


func test_a_saved_choice_reads_back() -> String:
	var choice: RefreshChoice = RefreshChoice.new()
	if not choice.save(true, SAVED_PATH):
		return "could not save"
	var loaded: RefreshChoice = RefreshChoice.new()
	loaded.use_saved(SAVED_PATH)
	_remove()
	return "" if loaded.on else "a saved 120 Hz read back off"


func test_the_wanted_rate_per_preset_with_the_option_on_and_off() -> String:
	for number: int in range(1, 5):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		var wanted_on: float = 120.0 if number == 4 else 90.0
		if _choice(true).wanted_hz(preset) != wanted_on:
			return "preset %d with the option on wants %s" % [number, _choice(true).wanted_hz(preset)]
		if _choice(false).wanted_hz(preset) != 90.0:
			return "preset %d with the option off wants %s" % [number, _choice(false).wanted_hz(preset)]
		var offered: Array = [72.0, 80.0, 90.0, 120.0]
		if RefreshRate.choose(offered, preset, true) != wanted_on:
			return "preset %d with the option on chose %s" % [number, RefreshRate.choose(offered, preset, true)]
		if RefreshRate.choose(offered, preset, false) != 90.0:
			return "preset %d with the option off chose %s" % [number, RefreshRate.choose(offered, preset)]
	return ""


func test_preset_changes_follow_the_option() -> String:
	var made: Array = _rate(true, [72.0, 90.0, 120.0])
	var rate: RefreshRate = made[0]
	rate.apply(ComfortPresetFiles.load_number(1))
	rate.apply(ComfortPresetFiles.load_number(4))
	var requests: Array[float] = made[1].get("requests")
	if requests != [120.0, 90.0, 120.0]:
		return "with the option on, presets 4, 1, 4 asked for %s" % [requests]
	made = _rate(false, [72.0, 90.0, 120.0])
	(made[0] as RefreshRate).apply(ComfortPresetFiles.load_number(1))
	requests = made[1].get("requests")
	return "" if requests == [90.0, 90.0] else "with the option off, presets 4, 1 asked for %s" % [requests]


func test_without_120_offered_the_highest_below_is_asked() -> String:
	var made: Array = _rate(true, [72.0, 80.0, 90.0])
	var rate: RefreshRate = made[0]
	if rate.requested_hz != 90.0:
		return "with 120 not offered the option asked for %s" % rate.requested_hz
	rate.on_runtime_changed(90.0)
	if rate.beside("abc1234") != "abc1234  90 Hz":
		return "the panel reads '%s'" % rate.beside("abc1234")
	made = _rate(true, [72.0])
	return "" if (made[0] as RefreshRate).requested_hz == 72.0 else "only 72 offered asked %s" % made[0].requested_hz


func test_the_rate_in_use_is_shown_beside_the_build() -> String:
	var rate: RefreshRate = _rate(true, [72.0, 90.0, 120.0])[0]
	rate.on_runtime_changed(120.0)
	return "" if rate.beside("abc1234") == "abc1234  120 Hz" else "reads '%s'" % rate.beside("abc1234")


## The same flight with the same preset changes on two main scenes, one with
## the option on and asking for 120 Hz, ends on the same state hash (CMF-6).
func test_the_option_leaves_the_simulation_alone() -> String:
	var hashes: Array[int] = []
	for on: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		if on:
			var rate: RefreshRate = main.get("refresh_rate") as RefreshRate
			rate.choice = _choice(true)
			rate.begin(FakeRuntime.new([72.0, 90.0, 120.0], 72.0), ComfortPresetFiles.load_number(4))
		(main.get("input_source") as LatestInputSource).set_input(
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i(200, 400, 0)))
		for frame: int in 120:
			if frame % 30 == 0:
				main.call("set_comfort_preset", 4 if frame % 60 == 0 else 1)
			main.call("advance_frame", FRAME)
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
	return "" if hashes[0] == hashes[1] else "hashes %s differ with the option on" % [hashes]
