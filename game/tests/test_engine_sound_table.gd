extends RefCounted

## The engine sound table (#1398, AUD-1, ARC-4): the shipped file is read,
## every key is checked and a bad one is named, and the engine at its loudest
## stays under every shot cue and robot voice.

const GOOD: String = """{"offset_m": [0, -0.5, 0.8], "fade_seconds": 0.4, "smoothing_seconds": 0.15,
	"thrust_weight": 0.6,
	"idle": {"sound": "res://i.wav", "volume_db": -24, "pitch": 1.0},
	"thrust": {"sound": "res://t.wav", "volume_min_db": -36, "volume_max_db": -18,
		"pitch_min": 0.8, "pitch_max": 1.3},
	"burst": {"sound": "res://b.wav", "volume_db": -16}}"""


func test_good_table_is_read() -> String:
	var table: EngineSoundTable = EngineSoundTable.parse(GOOD)
	if table.error != "":
		return table.error
	if table.offset != Vector3(0.0, -0.5, 0.8) or table.fade_seconds != 0.4 or table.thrust_weight != 0.6:
		return "top-level numbers not read"
	if table.idle_sound != "res://i.wav" or table.idle_db != -24.0 or table.idle_pitch != 1.0:
		return "idle not read"
	if table.thrust_sound != "res://t.wav" or table.thrust_min_db != -36.0 or table.thrust_max_db != -18.0 \
			or table.thrust_pitch_min != 0.8 or table.thrust_pitch_max != 1.3:
		return "thrust not read"
	return "" if table.burst_sound == "res://b.wav" and table.burst_db == -16.0 else "burst not read"


func test_every_key_is_checked_by_name() -> String:
	var cases: Dictionary[String, String] = {
		GOOD.replace("\"offset_m\": [0, -0.5, 0.8]", "\"offset_m\": [0, 1]"): "offset_m",
		GOOD.replace("\"offset_m\": [0, -0.5, 0.8]", "\"offset_m\": [0, \"x\", 1]"): "offset_m",
		GOOD.replace("\"fade_seconds\": 0.4", "\"fade_seconds\": 0"): "fade_seconds",
		GOOD.replace("\"smoothing_seconds\": 0.15", "\"smoothing_seconds\": null"): "smoothing_seconds",
		GOOD.replace("\"thrust_weight\": 0.6", "\"thrust_weight\": 1.5"): "thrust_weight",
		GOOD.replace("res://i.wav", "i.wav"): "idle.sound",
		GOOD.replace("\"volume_db\": -24", "\"volume_db\": \"loud\""): "idle.volume_db",
		GOOD.replace("\"pitch\": 1.0", "\"pitch\": 0"): "idle.pitch",
		GOOD.replace("res://t.wav", "t.wav"): "thrust.sound",
		GOOD.replace("\"volume_min_db\": -36", "\"volume_min_db\": -10"): "thrust.volume_min_db",
		GOOD.replace("\"volume_max_db\": -18,", ""): "thrust.volume_max_db",
		GOOD.replace("\"pitch_min\": 0.8", "\"pitch_min\": 1.5"): "pitch_min",
		GOOD.replace("\"pitch_max\": 1.3", "\"pitch_max\": []"): "thrust.pitch_max",
		GOOD.replace("res://b.wav", ""): "burst.sound",
		GOOD.replace("\"volume_db\": -16", "\"volume_db\": true"): "burst.volume_db",
		"[]": "not a JSON object",
	}
	for text: String in cases:
		var table: EngineSoundTable = EngineSoundTable.parse(text)
		if not table.error.contains(cases[text]):
			return "expected an error naming %s, got '%s'" % [cases[text], table.error]
	for section: String in ["idle", "thrust", "burst"]:
		var data: Dictionary = JSON.parse_string(GOOD)
		data.erase(section)
		var missing: EngineSoundTable = EngineSoundTable.parse(JSON.stringify(data))
		if not missing.error.contains(section):
			return "a table with no %s gave '%s'" % [section, missing.error]
	return ""


func test_missing_file_is_refused() -> String:
	var table: EngineSoundTable = EngineSoundTable.load_file("res://no/such/engine.json")
	return "" if table.error.contains("no such file") else "missing file read as '%s'" % table.error


func test_shipped_table_and_its_sounds() -> String:
	var table: EngineSoundTable = EngineSoundTable.load_file()
	if table.error != "":
		return "the shipped table was refused: %s" % table.error
	for path: String in [table.idle_sound, table.thrust_sound, table.burst_sound]:
		if not ResourceLoader.exists(path):
			return "%s is missing" % path
	for path: String in [table.idle_sound, table.thrust_sound]:
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		if stream == null or stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			return "%s does not loop" % path
	if table.offset.z <= 0.0 or table.offset.y >= 0.0:
		return "the engine at %s is not behind and below the seat" % table.offset
	return ""


func test_engine_is_never_louder_than_shots_or_robot_voices() -> String:
	var table: EngineSoundTable = EngineSoundTable.load_file()
	var cues: SoundCueTable = SoundCueTable.load_file()
	var voices: RobotVoiceTable = RobotVoiceTable.load_file()
	if cues.error != "" or voices.error != "":
		return "a sound table was refused: %s %s" % [cues.error, voices.error]
	var quietest: float = INF
	var quietest_name: String = ""
	for id: String in cues.cues:
		if id.begins_with(SoundCueTable.SHOT_FIRED) and cues.cues[id].volume_db < quietest:
			quietest = cues.cues[id].volume_db
			quietest_name = id
	for id: String in voices.voices:
		if voices.voices[id].volume_db < quietest:
			quietest = voices.voices[id].volume_db
			quietest_name = "voice " + id
	if quietest_name == "":
		return "no shot cue or robot voice to compare with"
	if table.loudest_db() >= quietest:
		return "the engine at %.1f dB is not under %s at %.1f dB" % [table.loudest_db(), quietest_name, quietest]
	return ""
