extends RefCounted

## The robot voice table (#1363, AUD-2, ARC-4): the shipped file is read,
## every robot type has its own loop, and bad files are refused naming the field.

const GOOD: String = """{"max_voices": 3, "reference_m": 2, "far_cutoff_hz": 2000,
	"muffle_cutoff_hz": 600, "voices": {"drone": {"sound": "res://a.wav", "volume_db": -6,
	"pitch_min": 0.9, "pitch_max": 1.2, "range_m": 25, "muffle_db": -10}}}"""


func test_good_table_is_read() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(GOOD)
	if table.error != "":
		return table.error
	var row: RobotVoiceRow = table.voice("drone")
	if row == null or row.sound != "res://a.wav" or row.range_m != 25.0 or row.muffle_db != -10.0:
		return "drone row not read"
	if table.max_voices != 3 or table.reference_m != 2.0 or table.muffle_cutoff_hz != 600.0:
		return "table numbers not read"
	return "" if table.voice("warden") == null else "a type with no row has a voice"


func test_bad_tables_are_refused_by_field() -> String:
	var cases: Dictionary[String, String] = {
		GOOD.replace("\"max_voices\": 3", "\"max_voices\": 0"): "max_voices",
		GOOD.replace("\"reference_m\": 2", "\"reference_m\": -1"): "reference_m",
		GOOD.replace("\"muffle_cutoff_hz\": 600", "\"muffle_cutoff_hz\": \"x\""): "muffle_cutoff_hz",
		GOOD.replace("res://a.wav", "a.wav"): "voices.drone: sound",
		GOOD.replace("\"pitch_min\": 0.9", "\"pitch_min\": 1.5"): "pitch_min",
		GOOD.replace("\"range_m\": 25", "\"range_m\": 0"): "range_m",
		GOOD.replace("\"muffle_db\": -10", "\"muffle_db\": 3"): "muffle_db",
		GOOD.replace("\"muffle_db\": -10", "\"muffle_db\": null"): "muffle_db",
		"[]": "not a JSON object",
	}
	for text: String in cases:
		var table: RobotVoiceTable = RobotVoiceTable.parse(text)
		if not table.error.contains(cases[text]):
			return "expected an error naming %s, got '%s'" % [cases[text], table.error]
		if not table.voices.is_empty():
			return "a refused table kept voices"
	return ""


func test_missing_file_is_refused() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.load_file("res://no/such/voices.json")
	return "" if table.error.contains("no such file") else "missing file read as '%s'" % table.error


func test_shipped_table_voices_every_robot_type_differently() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.load_file()
	if table.error != "":
		return "shipped table refused: %s" % table.error
	var sounds: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data/robots"):
		if not file.ends_with(".json"):
			continue
		var id: String = file.get_basename()
		var row: RobotVoiceRow = table.voice(id)
		if row == null:
			return "robot type %s has no voice" % id
		if not ResourceLoader.exists(row.sound):
			return "%s's loop %s is missing" % [id, row.sound]
		if sounds.has(row.sound):
			return "%s shares its loop with another type" % id
		sounds.append(row.sound)
		if row.muffle_db >= 0.0:
			return "a wall does not quieten %s" % id
	return "" if sounds.size() >= 1 else "no robot types found"


func test_shipped_loops_repeat() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.load_file()
	for id: String in table.voices:
		var stream: AudioStreamWAV = load(table.voices[id].sound) as AudioStreamWAV
		if stream == null:
			return "%s's loop is not a wav" % id
		if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			return "%s's loop does not repeat; import it with edit/loop_mode=2" % id
	return ""


func test_pitch_follows_speed() -> String:
	var row: RobotVoiceRow = RobotVoiceTable.parse(GOOD).voice("drone")
	if not is_equal_approx(row.pitch_for(0.0, 8.0), 0.9):
		return "at rest %.3f" % row.pitch_for(0.0, 8.0)
	if not is_equal_approx(row.pitch_for(8.0, 8.0), 1.2) or not is_equal_approx(row.pitch_for(30.0, 8.0), 1.2):
		return "at or past top speed not pitch_max"
	if not is_equal_approx(row.pitch_for(4.0, 8.0), 1.05):
		return "half speed %.3f" % row.pitch_for(4.0, 8.0)
	return "" if is_equal_approx(row.pitch_for(4.0, 0.0), 0.9) else "a type with no top speed is not at rest pitch"
