extends RefCounted

## The room tone table (#1399, AUD-1, ARC-4): the shipped file is read and
## every layer has a sound; a bad field is named; a box's span picks its
## space; the reactor's pulse rises with nearness; and every tone sits well
## under the music, the engine, the shot cues and the robot voices.

## How far under the quietest of the others the loudest tone must stay, dB.
const HEADROOM_DB: float = 6.0

const GOOD: Dictionary = {
	"fade_seconds": 1.0,
	"spaces": [
		{"id": "tunnel", "from_span_m": 0.0, "sound": "res://a.wav", "volume_db": -38.0},
		{"id": "room", "from_span_m": 10.0, "sound": "res://b.wav", "volume_db": -37.0},
	],
	"reactor": {"sound": "res://c.wav", "volume_db": -35.0, "near_m": 30.0, "full_m": 10.0},
	"meltdown": {"sound": "res://d.wav", "volume_db": -32.0},
	"hangar": {"sound": "res://e.wav", "volume_db": -38.0},
}


static func _with(path: Array, value: Variant) -> String:
	var data: Dictionary = GOOD.duplicate(true)
	var node: Variant = data
	for index: int in path.size() - 1:
		node = node[path[index]]
	if value == null:
		(node as Dictionary).erase(path[-1])
	else:
		node[path[-1]] = value
	return JSON.stringify(data)


func test_shipped_table_reads_and_every_sound_exists() -> String:
	var table: RoomToneTable = RoomToneTable.load_file()
	if table.error != "":
		return "the shipped table was rejected: %s" % table.error
	if table.space_ids.size() < 3:
		return "%d spaces; expected tunnel, room and chamber" % table.space_ids.size()
	for id: String in table.layer_ids():
		if not ResourceLoader.exists(table.sounds[id]):
			return "%s has no sound at %s" % [id, table.sounds[id]]
	return ""


func test_good_table_reads() -> String:
	var table: RoomToneTable = RoomToneTable.parse(JSON.stringify(GOOD))
	if table.error != "":
		return "rejected: %s" % table.error
	var ids: Array[String] = table.layer_ids()
	return "" if str(ids) == str(["tunnel", "room", "reactor", "meltdown", "hangar"]) else "layers %s" % [ids]


func test_bad_fields_are_named() -> String:
	var cases: Dictionary[String, String] = {
		"fade_seconds": _with(["fade_seconds"], 0.0),
		"spaces must": _with(["spaces"], []),
		"spaces[0].from_span_m must be 0": _with(["spaces", 0, "from_span_m"], 2.0),
		"spaces[1].from_span_m must be above": _with(["spaces", 1, "from_span_m"], 0.0),
		"spaces[1].id tunnel": _with(["spaces", 1, "id"], "tunnel"),
		"spaces[1].id hangar": _with(["spaces", 1, "id"], "hangar"),
		"spaces[0].sound": _with(["spaces", 0, "sound"], "a.wav"),
		"meltdown.volume_db": _with(["meltdown", "volume_db"], 3.0),
		"hangar must": _with(["hangar"], null),
		"reactor.near_m": _with(["reactor", "near_m"], "far"),
		"reactor.full_m must be below": _with(["reactor", "full_m"], 40.0),
	}
	for expected: String in cases:
		var table: RoomToneTable = RoomToneTable.parse(cases[expected])
		if not table.error.contains(expected):
			return "expected an error naming '%s', got '%s'" % [expected, table.error]
		if not table.layer_ids().is_empty():
			return "a rejected table (%s) kept layers" % expected
	return ""


func test_span_picks_the_space() -> String:
	var table: RoomToneTable = RoomToneTable.parse(JSON.stringify(GOOD))
	var cases: Dictionary[float, String] = {0.5: "tunnel", 9.9: "tunnel", 10.0: "room", 40.0: "room"}
	for span: float in cases:
		if table.space_for_span(span) != cases[span]:
			return "span %.1f gave %s, not %s" % [span, table.space_for_span(span), cases[span]]
	var walls: BoxUnion = BoxUnion.new([BoxBounds.new(Vector3(-3, -3, -40), Vector3(3, 3, 0)),
		BoxBounds.new(Vector3(-10, -10, -60), Vector3(10, 10, -40))] as Array[BoxBounds])
	var heard: Array[String] = [table.space_at(walls, Vector3(0, 0, -10)),
		table.space_at(walls, Vector3(0, 0, -50)), table.space_at(walls, Vector3(0, 50, 0))]
	return "" if str(heard) == str(["tunnel", "room", ""]) else "heard %s" % [heard]


func test_reactor_pulse_rises_with_nearness() -> String:
	var table: RoomToneTable = RoomToneTable.parse(JSON.stringify(GOOD))
	var shares: Array[float] = [table.reactor_share(50.0), table.reactor_share(30.0),
		table.reactor_share(20.0), table.reactor_share(10.0), table.reactor_share(2.0)]
	return "" if str(shares) == str([0.0, 0.0, 0.5, 1.0, 1.0]) else "shares %s" % [shares]


func test_tones_sit_well_under_music_engine_cues_and_voices() -> String:
	var table: RoomToneTable = RoomToneTable.load_file()
	var music: MusicTable = MusicTable.load_file()
	var engine: EngineSoundTable = EngineSoundTable.load_file()
	var cues: SoundCueTable = SoundCueTable.load_file()
	var voices: RobotVoiceTable = RobotVoiceTable.load_file()
	for refused: String in [table.error, music.error, engine.error, cues.error, voices.error]:
		if refused != "":
			return "a sound table was refused: %s" % refused
	var levels: Dictionary[String, float] = {"engine idle": engine.idle_db}
	for layer: MusicLayer in music.layers:
		levels["music " + layer.id] = music.volume_db + layer.volume_db
	for id: String in cues.cues:
		if id.begins_with(SoundCueTable.SHOT_FIRED):
			levels[id] = cues.cues[id].volume_db
	for id: String in voices.voices:
		levels["voice " + id] = voices.voices[id].volume_db
	# A space and the reactor pulse can sound together: at most 3 dB over the louder.
	var loudest: float = table.loudest_db() + 3.0
	for name: String in levels:
		if loudest > levels[name] - HEADROOM_DB:
			return "the tones at up to %.1f dB are not %.0f dB under %s at %.1f dB" % [loudest,
				HEADROOM_DB, name, levels[name]]
	return ""
