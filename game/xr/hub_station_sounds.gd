class_name HubStationSounds
extends Node3D

## Short, soft sounds at the home base's station screens (#1401, AUD-1, CRW-2,
## CRF-3, CRF-4): pointing onto a station or row, select, back, a refused press,
## crafted, mounted, unmounted and launch chosen, so the stations feel like
## machines rather than a menu. Which sound, how loud and how often come from
## `HubSoundTable` (`data/audio/hub_sounds.json`, ARC-4); the files are original,
## synthesised by `tools/synth_hub_sounds.py` (NAM-3).
##
## `HubWiring` hands it each frame's stations state before and after the aim
## and the stick (`hear`). A sound plays from the screen of the station it
## happened on, so it is heard from there (positional), on the existing
## `Effects` bus; the bus layout is not changed. It follows the hub's own
## actions and results only: it changes no hub, profile or simulation state
## (ARC-3, MP-2) and reads no comfort setting. Without an audio device it still
## records what it would play, for tests and checks.

const NODE_NAME: String = "HubStationSounds"
## Most sounds `requested` keeps.
const LOG_LIMIT: int = 256

var table: HubSoundTable
## Plays when true; when false only `requested` grows, for tests and checks.
var enabled: bool = SoundCues.audio_available()
## Sound names played since the hub last opened, in order.
var requested: Array[String] = []
## Station id each of `requested` came from.
var requested_at: Array[String] = []

var _stations: HubStations
var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _streams: Dictionary[String, AudioStream] = {}
var _last_played: Dictionary[String, float] = {}
var _clock: float = 0.0


func _init(stations: HubStations, p_table: HubSoundTable = HubSoundTable.load_file()) -> void:
	name = NODE_NAME
	_stations = stations
	table = p_table
	if table.error != "":
		push_warning("hub sounds off: %s" % table.error)
		return
	for i: int in table.voices:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "Voice%d" % i
		player.bus = RoomReverb.BUS
		# The screens are within arm's reach, so the file's level is the level heard.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500.0
		_players.append(player)
		add_child(player)
	for sound_name: String in table.sounds:
		var path: String = table.sounds[sound_name]["sound"]
		_streams[sound_name] = load(path) as AudioStream if ResourceLoader.exists(path) else null


## Called when the hub opens: the log starts empty and nothing is held back.
func opened() -> void:
	requested.clear()
	requested_at.clear()
	_last_played.clear()


## One frame of the stations: `before` is `HubSoundTable.state` taken before the
## aim and stick acted, `result` what `HubStations.update` returned and
## `seconds` the frame's length. Returns the sound played, or "".
func hear(before: Dictionary, result: Dictionary, seconds: float) -> String:
	_clock += maxf(seconds, 0.0)
	if table.error != "" or _stations == null:
		return ""
	var after: Dictionary = HubSoundTable.state(_stations)
	var sound_name: String = table.event(before, after, _stations.last_acted, result)
	if sound_name == "":
		return ""
	var station: String = after["in_use"] if after["in_use"] != "" else before["in_use"]
	if station == "":
		station = _stations.highlighted_id()
	return sound_name if play(sound_name, station) else ""


## Plays `sound_name` from station `station`'s screen unless it played less
## than its `min_gap_s` ago. True when it played (or would have, unheard).
func play(sound_name: String, station: String) -> bool:
	if not table.due(sound_name, _last_played.get(sound_name, -INF), _clock):
		return false
	_last_played[sound_name] = _clock
	requested.append(sound_name)
	requested_at.append(station)
	if requested.size() > LOG_LIMIT:  # A long stay in the hub keeps only the latest.
		requested.pop_front()
		requested_at.pop_front()
	var stream: AudioStream = _streams.get(sound_name, null)
	if not enabled or stream == null or _players.is_empty() or not is_inside_tree():
		return true
	var player: AudioStreamPlayer3D = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	var screen: Node3D = _stations.screen(station)
	if screen != null and screen.is_inside_tree():
		player.global_position = screen.global_position
	player.stream = stream
	player.volume_db = float(table.sounds[sound_name]["volume_db"])
	player.play()
	return true
