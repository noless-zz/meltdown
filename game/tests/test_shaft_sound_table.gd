extends RefCounted

## The shaft choice's sound table (#1455, AUD-1, RUN-1, ARC-4, NAM-3): the
## shipped file reads, a bad one names its field and leaves the choice silent,
## a frame's highlight and press pick the right sounds, and a sound cannot
## repeat inside its gap.


func test_the_shipped_table_reads_and_every_sound_exists() -> String:
	var table: ShaftSoundTable = ShaftSoundTable.load_file()
	if table.error != "":
		return table.error
	for sound_name: String in ShaftSoundTable.NEEDED:
		var path: String = table.sounds[sound_name]["sound"]
		if not ResourceLoader.exists(path):
			return "%s plays %s, which does not exist" % [sound_name, path]
		if float(table.sounds[sound_name]["volume_db"]) > -6.0:
			return "%s is at %s dB; panel sounds stay soft" % [sound_name, table.sounds[sound_name]["volume_db"]]
	if float(table.sounds["point"]["min_gap_s"]) <= 0.0:
		return "pointing has no repeat gap, so stepping down the list would tick on every frame"
	return ""


func test_the_base_files_are_not_edited_for_it() -> String:
	# Lane-c owns the base's table; the shaft choice has its own file.
	if ShaftSoundTable.DEFAULT_FILE == HubSoundTable.DEFAULT_FILE:
		return "the shaft choice reads the base's sound file"
	return ""


func test_a_bad_table_names_its_field() -> String:
	var good: String = FileAccess.get_file_as_string(ShaftSoundTable.DEFAULT_FILE)
	var cases: Dictionary[String, String] = {
		"[]": "not a JSON object",
		good.replace("\"voices\": 3", "\"voices\": 0"): "voices",
		good.replace("\"voices\": 3", "\"voices\": 1.5"): "voices",
		good.replace("\"voices\": 3,", ""): "voices",
		"{\"voices\": 3, \"sounds\": []}": "sounds must be an object",
		good.replace("\"point\": {", "\"point\": 4, \"pointx\": {"): "sounds.point must be an object",
		good.replace("res://data/audio/hub_select.wav", "hub_select.wav"): "sounds.select.sound",
		good.replace("\"volume_db\": -14.0", "\"volume_db\": \"loud\""): "sounds.refused.volume_db",
		good.replace("\"min_gap_s\": 0.09", "\"min_gap_s\": -1"): "sounds.point.min_gap_s",
		good.replace("\"launch\": {", "\"launchx\": {"): "sounds.launch is missing",
		good.replace("\"refused\": {", "\"refusedx\": {"): "sounds.refused is missing",
	}
	for text: String in cases:
		var table: ShaftSoundTable = ShaftSoundTable.parse(text)
		if table.error.find(cases[text]) < 0:
			return "expected an error naming %s, got '%s'" % [cases[text], table.error]
		if not table.sounds.is_empty():
			return "a rejected table kept its sounds"
	if ShaftSoundTable.load_file("res://no_such_shaft_sounds.json").error.find("no such file") < 0:
		return "a missing file was not named"
	return ""


func test_a_frame_picks_its_sounds() -> String:
	var cases: Array[Array] = [
		[0, 0, "", false, []],
		[0, 1, "", false, ["point"]],
		[2, 1, "", false, ["point"]],
		[1, 1, "deep", true, ["select", "launch"]],
		[1, 1, "deep", false, ["refused"]],
		[0, 1, "hot", true, ["select", "launch"]],
	]
	for case: Array in cases:
		var got: Array[String] = ShaftSoundTable.events(case[0], case[1], case[2], case[3])
		if got != Array(case[4], TYPE_STRING, "", null):
			return "highlight %d to %d, chosen '%s', taken %s: %s, expected %s" % [case[0], case[1], case[2],
				case[3], got, case[4]]
	return ""


func test_a_sound_waits_out_its_gap() -> String:
	var table: ShaftSoundTable = ShaftSoundTable.load_file()
	var gap: float = float(table.sounds["refused"]["min_gap_s"])
	if not table.due("refused", -INF, 0.0):
		return "a sound never played was held back"
	if table.due("refused", 1.0, 1.0 + gap * 0.5):
		return "a sound repeated inside its gap"
	if not table.due("refused", 1.0, 1.0 + gap):
		return "a sound was held back after its gap"
	if table.due("fanfare", -INF, 10.0):
		return "a sound the table does not have was due"
	return ""
