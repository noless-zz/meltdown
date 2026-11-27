class_name MenuSounds
extends Node3D

## Short, soft sounds for the development menu (#1457, AUD-1, CRW-2): open,
## pointing at another row, changing a value, a confirm, a refused press and
## back or close, so the menu answers like the base's stations (#1401). Which
## sound, how loud and how often come from `MenuSoundTable`
## (`data/audio/menu_sounds.json`, ARC-4), reusing the stations' files.
##
## It hangs under the `DevMenu` panel, so a sound comes from where the menu
## floats, on the existing `Effects` bus; the bus layout is not changed. The
## menu opens in the mine, at the base, at the shaft choice and on the end
## screens, and so do its sounds. In solo play the open menu pauses the
## session (`DevMenuPause`); this node is processed always and keeps its clock
## from the wiring's steady time, so sounds still play while paused.
##
## `DevMenuWiring.read` hands it each frame's menu state from before the tap
## and the stick acted, the actions held and what the menu returned (`hear`).
## It changes no menu, profile or simulation state (ARC-3, MP-2) and reads no
## comfort setting. Without an audio device it still records what it would
## play, for tests and checks.

const NODE_NAME: String = "MenuSounds"
## Most sounds `requested` keeps.
const LOG_LIMIT: int = 256

var table: MenuSoundTable
## Plays when true; when false only `requested` grows, for tests and checks.
var enabled: bool = SoundCues.audio_available()
## Sound names played, oldest first, at most `LOG_LIMIT`.
var requested: Array[String] = []

var _menu: DevMenu
var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _streams: Dictionary[String, AudioStream] = {}
var _last_played: Dictionary[String, float] = {}
var _held: Dictionary = {}


## Sounds for `menu`, which it hangs under when given one.
func _init(menu: DevMenu = null, p_table: MenuSoundTable = MenuSoundTable.load_file()) -> void:
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_ALWAYS  # Heard while the open menu pauses the session.
	_menu = menu
	table = p_table
	if menu != null:
		menu.add_child(self)
	if table.error != "":
		push_warning("menu sounds off: %s" % table.error)
		return
	for i: int in table.voices:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "Voice%d" % i
		player.bus = RoomReverb.BUS
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		# The panel floats within reach, so the file's level is the level heard.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500.0
		_players.append(player)
		add_child(player)
	for sound_name: String in table.sounds:
		var path: String = table.sounds[sound_name]["sound"]
		_streams[sound_name] = load(path) as AudioStream if ResourceLoader.exists(path) else null


## One frame of the menu: `before` is `MenuSoundTable.state` taken before the
## tap and the stick acted, `held` the menu actions held this frame
## (`DevMenuWiring.actions`), `result` what the menu returned and `now` the
## wiring's steady clock in seconds. Returns the sound played, or "".
func hear(before: Dictionary, held: Dictionary, result: String, now: float) -> String:
	var down: Array[String] = MenuSoundTable.pressed(_held, held)
	_held = held.duplicate()
	if table.error != "":
		return ""
	var sound_name: String = table.event(before, MenuSoundTable.state(_menu), down, result)
	if sound_name == "":
		return ""
	return sound_name if play(sound_name, now) else ""


## Plays `sound_name` at the panel unless it played less than its `min_gap_s`
## before `now`. True when it played (or would have, unheard).
func play(sound_name: String, now: float) -> bool:
	if not table.due(sound_name, _last_played.get(sound_name, -INF), now):
		return false
	_last_played[sound_name] = now
	requested.append(sound_name)
	if requested.size() > LOG_LIMIT:  # A long session keeps only the latest.
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
