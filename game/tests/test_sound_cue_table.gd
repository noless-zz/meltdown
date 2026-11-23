extends RefCounted

## The sound cue table (#1290, AUD-1, ARC-4): every event kind the core emits
## has a cue or is listed as silent, every weapon's shot sounds, every sound
## file in it loads, and a broken file is rejected with the field named.

const WEAPONS_DIR: String = "res://data/weapons"


func test_shipped_table_is_read() -> String:
	var table: SoundCueTable = SoundCueTable.load_file()
	if table.error != "":
		return "the shipped table was rejected: %s" % table.error
	if table.max_voices < 1:
		return "max_voices is %d" % table.max_voices
	return ""


func test_every_event_kind_has_a_cue_or_is_silent() -> String:
	var missing: Array[String] = SoundCueTable.load_file().unheard_kinds()
	return "" if missing.is_empty() else "no cue and not silent: %s" % [missing]


func test_listed_hits_and_events_have_cues() -> String:
	# The issue's list: shots, bolt on wall, robot hit and kill, ship hit, pickup, meltdown, escape.
	var table: SoundCueTable = SoundCueTable.load_file()
	for id: String in ["SHOT_FIRED", "SHOT_FIRED:robot", "BOLT_IMPACT", "ROBOT_HIT", "ROBOT_DESTROYED",
			"SHIP_HIT", "SALVAGE_COLLECTED", "REACTOR_DESTROYED", "SHIP_ESCAPED"]:
		if table.cue(id) == null:
			return "%s has no cue" % id
	return ""


func test_every_weapon_has_its_own_shot() -> String:
	var table: SoundCueTable = SoundCueTable.load_file()
	for file: String in DirAccess.get_files_at(WEAPONS_DIR):
		if not file.ends_with(".json"):
			continue
		var id: String = file.get_basename()
		if not table.cues.has(SoundCueTable.shot_cue(id)):
			return "weapon %s has no SHOT_FIRED:%s cue" % [id, id]
	return ""


func test_every_sound_loads() -> String:
	var table: SoundCueTable = SoundCueTable.load_file()
	for id: String in table.cues:
		var path: String = table.cues[id].sound
		if not ResourceLoader.exists(path) or not load(path) is AudioStream:
			return "%s: %s is no sound" % [id, path]
	return ""


func test_unknown_weapon_falls_back_to_plain_shot() -> String:
	var table: SoundCueTable = SoundCueTable.load_file()
	var cue: SoundCue = table.cue(SoundCueTable.shot_cue("a_weapon_added_later"))
	if cue == null or cue.id != SoundCueTable.SHOT_FIRED:
		return "a new weapon's shot gave %s" % cue
	if table.cue("NOT_A_CUE") != null:
		return "an unknown cue was found"
	return ""


func test_small_wall_knocks_are_silent() -> String:
	var table: SoundCueTable = SoundCueTable.load_file()
	if table.plays(SoundCueHit.new("WALL_IMPACT", Vector3.ZERO, 0.1)):
		return "a slide along the wall at 0.1 m/s sounded"
	if not table.plays(SoundCueHit.new("WALL_IMPACT", Vector3.ZERO, 3.0)):
		return "a knock at 3 m/s was silent"
	return ""


func test_silent_kinds_play_nothing() -> String:
	var table: SoundCueTable = SoundCueTable.load_file()
	for kind: String in table.silent:
		if table.plays(SoundCueHit.new(kind)):
			return "silent %s plays" % kind
	return ""


func test_rejects_broken_files() -> String:
	var row: String = '"sound": "res://a.wav", "volume_db": 0, "pitch_min": 1, "pitch_max": 1'
	var cases: Dictionary[String, String] = {
		"[]": "not a JSON object",
		'{"max_voices": 0, "cues": {}}': "max_voices",
		'{"max_voices": 4}': "cues must",
		'{"max_voices": 4, "cues": {"A": {"volume_db": 0, "pitch_min": 1, "pitch_max": 1}}}': "cues.A",
		'{"max_voices": 4, "cues": {"A": {"sound": "a.wav", "volume_db": 0, "pitch_min": 1, "pitch_max": 1}}}': "cues.A",
		'{"max_voices": 4, "cues": {"A": {%s, "pitch_min": 2}}}' % row.replace('"pitch_min": 1, ', ""): "cues.A",
		'{"max_voices": 4, "cues": {"A": {%s, "min_magnitude": -1}}}' % row: "cues.A",
		'{"max_voices": 4, "cues": {}, "silent": ["NO_SUCH_KIND"]}': "NO_SUCH_KIND",
		'{"max_voices": 4, "cues": {"SHIP_HIT": {%s}}, "silent": ["SHIP_HIT"]}' % row: "both",
	}
	for text: String in cases:
		var table: SoundCueTable = SoundCueTable.parse(text)
		if not table.error.contains(cases[text]):
			return "%s gave error '%s', expected one naming '%s'" % [text, table.error, cases[text]]
		if not table.cues.is_empty():
			return "a rejected table kept cues"
	return ""


func test_missing_file_is_rejected() -> String:
	var table: SoundCueTable = SoundCueTable.load_file("res://data/audio/no_such_file.json")
	return "" if table.error.contains("no such file") else "error was '%s'" % table.error


func test_pitch_stays_in_range() -> String:
	var cue: SoundCue = SoundCue.new()
	cue.pitch_min = 0.9
	cue.pitch_max = 1.1
	if not is_equal_approx(cue.pitch(0.0), 0.9) or not is_equal_approx(cue.pitch(1.0), 1.1):
		return "pitch ends were %f and %f" % [cue.pitch(0.0), cue.pitch(1.0)]
	if cue.pitch(5.0) > 1.1 or cue.pitch(-1.0) < 0.9:
		return "pitch left its range"
	return ""
