class_name RoomTones
extends Node

## The room tones (#1399, AUD-1): one looping, non-positional player per layer
## of the `RoomToneTable`, at the levels `RoomToneMix` gives. A layer starts
## when its gain leaves 0 and stops when it is back at 0, so only the bed
## being heard, the one fading out and the reactor's pulse ever play.
##
## The tones play on Master, as the music does, not on the effects bus: they
## are the room itself, so the room reverb (#1291) is not put on them again.
## Pure view: it is handed a mood and session copies and writes nothing back
## (ARC-1, MP-2). Without an audio device it follows the mix but plays nothing.

const AUDIO_BUS: StringName = &"Master"

## Plays when true; the mix is followed either way.
var enabled: bool = SoundCues.audio_available()
var table: RoomToneTable = null
var mix: RoomToneMix = null

var _players: Dictionary[String, AudioStreamPlayer] = {}


## Tones for `tone_table`, null meaning the shipped table; a rejected table is
## printed once and plays nothing.
func _init(tone_table: RoomToneTable = null) -> void:
	name = "RoomTones"
	table = tone_table if tone_table != null else RoomToneTable.load_file()
	if table.error != "":
		print("Meltdown: room tones off: %s" % table.error)
	mix = RoomToneMix.new(table)


## Moves the tones `seconds` on for the ship at `position` in `walls`, in
## `mood`, with `reactor` a session copy or null. Returns the layers sounding.
func follow(mood: MusicMix.Mood, walls: BoxUnion, position: Vector3, reactor: ReactorState,
		seconds: float) -> Array[String]:
	var heard: Array[String] = mix.follow(mood, walls, position, reactor, seconds)
	if enabled:
		for id: String in mix.gains:
			_set_player(id)
	return heard


## Silences every tone at once, for a new level; its first space fades in.
func reset() -> void:
	mix.reset()
	for player: AudioStreamPlayer in _players.values():
		player.stop()


## The players sounding now; none while disabled.
func playing_count() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _players.values():
		if player.playing:
			count += 1
	return count


func _set_player(id: String) -> void:
	var player: AudioStreamPlayer = _players.get(id) as AudioStreamPlayer
	if mix.gains[id] <= 0.0:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		player = _make_player(id)
	player.volume_db = mix.db(id)
	if not player.playing and player.stream != null and player.is_inside_tree():
		player.play()


func _make_player(id: String) -> AudioStreamPlayer:
	var path: String = table.sounds[id]
	var made: AudioStreamPlayer = AudioStreamPlayer.new()
	made.name = id.to_pascal_case()
	made.bus = AUDIO_BUS
	made.stream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	add_child(made)
	_players[id] = made
	return made
