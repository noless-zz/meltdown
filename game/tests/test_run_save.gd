extends RefCounted

## The suspended-run data and its JSON text (#949, RUN-8): every key is checked
## and every error names the key.


func _run() -> RunSave:
	var run: RunSave = RunSave.new()
	run.run_seed = 123456789
	run.next_level = 3
	run.ship = "default_ship"
	run.loadout = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}
	return run


func _data() -> Dictionary:
	return JSON.parse_string(_run().to_json())


func _text(data: Dictionary) -> String:
	return JSON.stringify(data)


func test_a_save_reads_back_the_same() -> String:
	var run: RunSave = _run()
	var read: RunSave = RunSave.parse_json(run.to_json())
	if read.error != "":
		return "rejected: %s" % read.error
	if read.run_seed != run.run_seed or read.next_level != 3 or read.ship != "default_ship":
		return "read back seed %d, level %d, ship %s" % [read.run_seed, read.next_level, read.ship]
	if read.loadout != run.loadout or read.version != RunSave.VERSION:
		return "read back loadout %s, version %d" % [read.loadout, read.version]
	if read.to_json() != run.to_json():
		return "a second write gave different text"
	return ""


func test_every_64_bit_seed_reads_back_exactly() -> String:
	# Above 2^53 a JSON number would round; the seed is written as text.
	for seed_value: int in [0, -1, 9007199254740993, 9223372036854775807, -9223372036854775807 - 1]:
		var run: RunSave = _run()
		run.run_seed = seed_value
		var read: RunSave = RunSave.parse_json(run.to_json())
		if read.error != "" or read.run_seed != seed_value:
			return "seed %d read back as %d (%s)" % [seed_value, read.run_seed, read.error]
	return ""


func test_each_missing_key_is_named() -> String:
	for key: String in RunSave.KEYS:
		var data: Dictionary = _data()
		data.erase(key)
		var read: RunSave = RunSave.parse_json(_text(data))
		if not read.error.contains(key):
			return "without %s: '%s'" % [key, read.error]
	return ""


func test_each_wrongly_typed_key_is_named() -> String:
	var bad: Dictionary = {
		"version": ["1", true, 1.5, null],
		"run_seed": [12, "12.0", "012", "+12", "", "99999999999999999999", true],
		"next_level": ["3", 2.5, false, 0, -1],
		"ship": [7, "", "Default Ship", "../x"],
		"loadout": [[], "pulse_cannon", {"tertiary": []}, {"primary": "pulse_cannon"},
			{"primary": [1, ""]}, {"primary": ["a", "b", "c"]}, {"primary": ["Bad-Id", ""]}],
	}
	for key: String in bad:
		for value: Variant in bad[key]:
			var data: Dictionary = _data()
			data[key] = value
			var read: RunSave = RunSave.parse_json(_text(data))
			if read.error == "" or not read.error.contains(key):
				return "%s = %s: '%s'" % [key, JSON.stringify(value), read.error]
			if read.too_new or read.ship != "":
				return "%s = %s gave a non-empty save" % [key, JSON.stringify(value)]
	return ""


func test_an_unknown_key_is_named() -> String:
	var data: Dictionary = _data()
	data["crew"] = []
	var read: RunSave = RunSave.parse_json(_text(data))
	return "" if read.error.contains("crew") else "error '%s'" % read.error


func test_text_that_is_not_a_save_is_rejected() -> String:
	for text: String in ["", "{", "[]", "3", "\"run\""]:
		var read: RunSave = RunSave.parse_json(text)
		if read.error == "" or read.too_new:
			return "'%s' accepted" % text
	return ""


func test_a_newer_version_is_marked_too_new() -> String:
	var data: Dictionary = {"version": RunSave.VERSION + 1, "something_new": 1}
	var read: RunSave = RunSave.parse_json(_text(data))
	if not read.too_new or read.error == "":
		return "too_new %s, error '%s'" % [read.too_new, read.error]
	return ""


func test_check_names_the_bad_field() -> String:
	var cases: Dictionary = {}
	var low: RunSave = _run()
	low.next_level = 0
	cases["next_level"] = low
	var no_ship: RunSave = _run()
	no_ship.ship = ""
	cases["ship"] = no_ship
	var bad_loadout: RunSave = _run()
	bad_loadout.loadout = {"primary": ["Pulse", ""]}
	cases["loadout"] = bad_loadout
	var newer: RunSave = _run()
	newer.version = RunSave.VERSION + 1
	cases["version"] = newer
	for key: String in cases:
		var problem: String = (cases[key] as RunSave).check()
		if not problem.contains(key):
			return "%s: '%s'" % [key, problem]
	return "" if _run().check() == "" else "a good save fails: %s" % _run().check()


func test_the_shipped_ship_loadout_is_accepted() -> String:
	var ship: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/default_ship.json"))
	var run: RunSave = _run()
	run.loadout = ship["loadout"]
	var read: RunSave = RunSave.parse_json(run.to_json())
	if read.error != "" or read.loadout != ship["loadout"]:
		return "default_ship loadout: '%s', %s" % [read.error, read.loadout]
	return ""
