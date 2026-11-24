extends RefCounted

## The music table (#1303, AUD-3, ARC-4): the shipped file has a calm layer,
## tension layers by alarm, a meltdown and a hub track, fades from data, a
## music volume of its own, and every sound it names exists. Bad files are
## rejected naming the field.


static func _valid() -> Dictionary:
	return {
		"volume_db": -12.0, "crossfade_seconds": 2.0, "meltdown_seconds": 0.5, "end_fade_seconds": 1.5,
		"layers": [
			{"id": "calm", "plays": "run", "from_alarm": 0.0, "sound": "res://a.wav", "volume_db": 0.0},
			{"id": "tense", "plays": "run", "from_alarm": 0.5, "sound": "res://b.wav", "volume_db": -3.0},
			{"id": "melt", "plays": "meltdown", "sound": "res://c.wav"},
			{"id": "home", "plays": "hub", "sound": "res://d.wav"},
		],
	}


static func _with(key: String, value: Variant) -> String:
	var data: Dictionary = _valid()
	data[key] = value
	return JSON.stringify(data)


func test_shipped_table_has_every_part() -> String:
	var table: MusicTable = MusicTable.load_file()
	if table.error != "":
		return "rejected: %s" % table.error
	var run: Array[MusicLayer] = table.layers_playing(MusicLayer.RUN)
	var tension: Array[MusicLayer] = run.filter(func(l: MusicLayer) -> bool: return l.from_alarm > 0.0)
	if run.size() - tension.size() != 1:
		return "%d calm layers" % (run.size() - tension.size())
	if tension.is_empty():
		return "no tension layer"
	if table.layers_playing(MusicLayer.MELTDOWN).size() != 1 or table.layers_playing(MusicLayer.HUB).size() != 1:
		return "not one meltdown and one hub track"
	return ""


func test_shipped_sounds_exist_and_loop() -> String:
	for layer: MusicLayer in MusicTable.load_file().layers:
		if not ResourceLoader.exists(layer.sound):
			return "%s: no %s" % [layer.id, layer.sound]
		var stream: AudioStreamWAV = load(layer.sound) as AudioStreamWAV
		if stream == null:
			return "%s: %s is no WAV stream" % [layer.id, layer.sound]
		if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			return "%s does not loop" % layer.sound
	return ""


func test_music_volume_is_its_own() -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MusicTable.DEFAULT_FILE))
	if not (data as Dictionary).has("volume_db"):
		return "no music volume_db"
	var cues: Variant = JSON.parse_string(FileAccess.get_file_as_string(SoundCueTable.DEFAULT_FILE))
	if (cues as Dictionary).has("volume_db") or (cues as Dictionary).has("music"):
		return "the cue table holds a music volume"
	return "" if MusicTable.load_file().volume_db == float(data["volume_db"]) else "volume not read"


func test_valid_table_is_read() -> String:
	var table: MusicTable = MusicTable.parse(JSON.stringify(_valid()))
	if table.error != "":
		return table.error
	if table.layers.size() != 4 or table.layer("tense").from_alarm != 0.5:
		return "layers not read"
	if table.crossfade_seconds != 2.0 or table.meltdown_seconds != 0.5 or table.end_fade_seconds != 1.5:
		return "fades not read"
	return "" if table.layer("melt").volume_db == 0.0 else "missing volume_db is not 0"


func test_fades_must_be_above_zero_and_meltdown_within_a_second() -> String:
	for key: String in ["crossfade_seconds", "meltdown_seconds", "end_fade_seconds"]:
		var table: MusicTable = MusicTable.parse(_with(key, 0.0))
		if not table.error.contains(key) or not table.layers.is_empty():
			return "%s 0 gave '%s'" % [key, table.error]
	var slow: MusicTable = MusicTable.parse(_with("meltdown_seconds", 1.5))
	return "" if slow.error.contains("meltdown_seconds") else "a 1.5 s meltdown switch was read"


func test_needs_calm_meltdown_and_hub() -> String:
	var data: Dictionary = _valid()
	(data["layers"] as Array).remove_at(0)
	if not MusicTable.parse(JSON.stringify(data)).error.contains("calm"):
		return "no calm layer was read"
	for plays: String in ["meltdown", "hub"]:
		data = _valid()
		data["layers"] = (data["layers"] as Array).filter(func(row: Dictionary) -> bool: return row["plays"] != plays)
		if not MusicTable.parse(JSON.stringify(data)).error.contains(plays):
			return "no %s layer was read" % plays
	return ""


func test_bad_rows_are_rejected() -> String:
	var bad: Array[Dictionary] = [
		{"id": "x", "plays": "lobby", "sound": "res://x.wav"},
		{"id": "x", "plays": "run", "sound": "x.wav"},
		{"id": "x", "plays": "run", "from_alarm": 1.5, "sound": "res://x.wav"},
		{"id": "", "plays": "run", "sound": "res://x.wav"},
		{"id": "x", "plays": "run", "sound": "res://x.wav", "volume_db": "loud"},
		{"id": "calm", "plays": "run", "sound": "res://x.wav"},
	]
	for row: Dictionary in bad:
		var data: Dictionary = _valid()
		(data["layers"] as Array).append(row)
		var table: MusicTable = MusicTable.parse(JSON.stringify(data))
		if not table.error.begins_with("layers[4]"):
			return "%s gave '%s'" % [row, table.error]
	return ""


func test_missing_and_broken_files_are_rejected() -> String:
	if MusicTable.load_file("res://data/audio/no_music.json").error == "":
		return "a missing file was read"
	if MusicTable.parse("[1, 2]").error == "":
		return "a list was read"
	return "" if MusicTable.parse(_with("volume_db", "loud")).error.contains("volume_db") else "bad volume read"
