class_name ShaftChoiceSounds
extends Node3D

## Sounds at the shaft choice between levels (#1455, AUD-1, RUN-1, CRW-2):
## pointing onto another shaft or row, choosing a shaft, a refused press and
## leaving for the next level, so choosing a shaft feels like the base's
## stations (#1401). Which sound, how loud and how often come from
## `ShaftSoundTable` (`data/audio/shaft_sounds.json`, ARC-4); the shipped file
## plays the base's original `hub_*.wav` files (NAM-3).
##
## `ShaftChoiceWiring` hangs it under the shaft panel, so a sound is heard from
## the panel (positional), on the existing `Effects` bus, and hands it each open
## frame's highlight before and after and the press's answer (`hear`). Its
## clock is the frames' own lengths, so the repeat gaps hold in the headset and
## in a scripted acceptance run alike. It changes no panel, run or simulation
## state (ARC-3, MP-2) and reads no comfort setting. Without an audio device it
## still records what it would play, for tests and checks.

const NODE_NAME: String = "ShaftChoiceSounds"
## Most sounds `requested` keeps.
const LOG_LIMIT: int = 64

var table: ShaftSoundTable
## Plays when true; when false only `requested` grows, for tests and checks.
var enabled: bool = SoundCues.audio_available()
## Sound names played since the panel last opened, in order.
var requested: Array[String] = []

var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _streams: Dictionary[String, AudioStream] = {}
var _last_played: Dictionary[String, float] = {}
var _clock: float = 0.0


func _init(p_table: ShaftSoundTable = ShaftSoundTable.load_file()) -> void:
	name = NODE_NAME
	table = p_table
	if table.error != "":
		push_warning("shaft choice sounds off: %s" % table.error)
		return
	for i: int in table.voices:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "Voice%d" % i
		player.bus = RoomReverb.BUS
		# The panel floats in front of the pilot, so the file's level is the level heard.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500.0
		_players.append(player)
		add_child(player)
	for sound_name: String in table.sounds:
		var path: String = table.sounds[sound_name]["sound"]
		_streams[sound_name] = load(path) as AudioStream if ResourceLoader.exists(path) else null


## Called when the panel opens: the log starts empty and nothing is held back.
func opened() -> void:
	requested.clear()
	_last_played.clear()


## One frame of the open panel (see `ShaftSoundTable.events`), `seconds` long.
## Returns the sounds played, in order.
func hear(before: int, after: int, chosen: String, taken: bool, seconds: float) -> Array[String]:
	_clock += maxf(seconds, 0.0)
	var played: Array[String] = []
	if table.error != "":
		return played
	for sound_name: String in ShaftSoundTable.events(before, after, chosen, taken):
		if play(sound_name):
			played.append(sound_name)
	return played


## Plays `sound_name` from the panel unless it played less than its
## `min_gap_s` ago. True when it played (or would have, unheard).
func play(sound_name: String) -> bool:
	if not table.due(sound_name, _last_played.get(sound_name, -INF), _clock):
		return false
	_last_played[sound_name] = _clock
	requested.append(sound_name)
	if requested.size() > LOG_LIMIT:
		requested.pop_front()
	var stream: AudioStream = _streams.get(sound_name, null)
	if not enabled or stream == null or _players.is_empty() or not is_inside_tree():
		return true
	var player: AudioStreamPlayer3D = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = float(table.sounds[sound_name]["volume_db"])
	player.play()
	return true
