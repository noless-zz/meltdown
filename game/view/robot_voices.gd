class_name RobotVoices
extends Node3D

## The robots' looping voices (#1363, AUD-2): each robot type hums, grinds or
## whines in its own way, so a pilot can tell what is coming before it is in
## sight. Each tick `RobotVoicePicker` chooses the nearest voices within range;
## each plays as a positional loop that follows its robot, louder and brighter
## as it nears (the 3D player's inverse-distance fall-off and distance
## low-pass), higher as it speeds up, and stopped once the robot is gone.
##
## A voice heard through a wall plays quieter by its row's `muffle_db` on the
## muffled bus, whose low-pass dulls it; that bus sends to the effects bus, so
## the room reverb (#1291) is on every voice.
##
## Pure view: it reads copies the session hands it and writes nothing back
## (ARC-1, MP-2). Without an audio device it chooses voices but plays nothing.

const BUS: StringName = RoomReverb.BUS
const MUFFLED_BUS: StringName = &"RobotVoicesMuffled"

## Plays voices when true; when false, voices are still chosen, for tests and checks.
var enabled: bool = SoundCues.audio_available()
var table: RobotVoiceTable = null
## The voices chosen by the last `follow`, nearest first.
var last_mix: Array[RobotVoiceMix] = []

var _players: Array[AudioStreamPlayer3D] = []
## The robot type each player sounds, "" when free.
var _player_types: Array[String] = []
var _streams: Dictionary[String, AudioStream] = {}


## Voices for `voice_table`, null meaning the shipped table; a rejected table
## is printed once and nothing sounds.
func _init(voice_table: RobotVoiceTable = null) -> void:
	name = "RobotVoices"
	table = voice_table if voice_table != null else RobotVoiceTable.load_file()
	if table.error != "":
		print("Meltdown: robot voices off: %s" % table.error)


## The muffled bus's index, adding it (with its low-pass, sending to the
## effects bus) when it is missing. Call after `RoomReverb.ensure_bus`.
func ensure_bus() -> int:
	var index: int = AudioServer.get_bus_index(MUFFLED_BUS)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, MUFFLED_BUS)
	AudioServer.set_bus_send(index, BUS)
	var low_pass: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = table.muffle_cutoff_hz
	AudioServer.add_bus_effect(index, low_pass)
	return index


## Follows `robots` (session copies) heard at `listener` in `walls`: starts,
## moves and stops the loops. Returns the voices chosen, nearest first.
func follow(robots: Array[RobotState], listener: Vector3, walls: BoxUnion) -> Array[RobotVoiceMix]:
	last_mix = RobotVoicePicker.pick(table, robots, listener, walls)
	var used: Array[bool] = []
	used.resize(_players.size())
	used.fill(false)
	for mix: RobotVoiceMix in last_mix:
		var index: int = _player_for(mix, used)
		used[index] = true
		_sound(index, mix)
	for index: int in _players.size():
		if not used[index]:
			_silence(index)
	return last_mix


## Stops every voice, for a new level.
func reset() -> void:
	for index: int in _players.size():
		_silence(index)
	last_mix = []


## How many players are sounding a voice.
func sounding() -> int:
	return _player_types.size() - _player_types.count("")


## Number of players in the pool, sounding or free.
func player_count() -> int:
	return _players.size()


## The robot type player `index` sounds, "" when free; for tests.
func player_type(index: int) -> String:
	return _player_types[index]


## The player `index`, for tests.
func player(index: int) -> AudioStreamPlayer3D:
	return _players[index]


## A player for `mix` not yet `used` this tick: the one already sounding its
## type nearest the robot, so a loop carries on rather than restarting; else a
## free one; else a new one.
func _player_for(mix: RobotVoiceMix, used: Array[bool]) -> int:
	var best: int = -1
	var best_distance: float = INF
	for index: int in _players.size():
		if used[index] or _player_types[index] != mix.type_id:
			continue
		var gap: float = _players[index].position.distance_to(mix.position)
		if gap < best_distance:
			best_distance = gap
			best = index
	if best >= 0:
		return best
	for index: int in _players.size():
		if not used[index] and _player_types[index] == "":
			return index
	var made: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	made.bus = BUS
	made.unit_size = table.reference_m
	made.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	made.attenuation_filter_cutoff_hz = table.far_cutoff_hz
	add_child(made)
	_players.append(made)
	_player_types.append("")
	used.append(false)
	return _players.size() - 1


func _sound(index: int, mix: RobotVoiceMix) -> void:
	var sounding_player: AudioStreamPlayer3D = _players[index]
	var row: RobotVoiceRow = table.voice(mix.type_id)
	sounding_player.position = mix.position
	sounding_player.volume_db = mix.player_db
	sounding_player.pitch_scale = mix.pitch
	sounding_player.max_distance = row.range_m
	sounding_player.bus = MUFFLED_BUS if mix.muffled else BUS
	if _player_types[index] == mix.type_id:
		return
	_player_types[index] = mix.type_id
	sounding_player.stop()
	sounding_player.stream = _stream(mix.sound)
	if enabled and sounding_player.stream != null and sounding_player.is_inside_tree():
		sounding_player.play()


func _silence(index: int) -> void:
	_player_types[index] = ""
	_players[index].stop()


## The loop at `path` (its import repeats it), or null when it cannot be read.
func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[path]
