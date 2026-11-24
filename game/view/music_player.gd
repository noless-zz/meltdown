class_name MusicPlayer
extends Node

## Plays the adaptive music (#1303, AUD-3): one looping, non-positional player
## per layer of the `MusicTable`, at the volumes `MusicMix` gives. A layer
## starts when its gain leaves 0, at the music clock's place in its loop, so
## the layers stay on the beat together, and stops when its gain is back at 0.
##
## The music plays on Master, not on the effects bus, so the room reverb is
## not applied to it (#1291). Pure view: it is handed a mood and an alarm
## level read from session copies and writes nothing back (ARC-1, MP-2).
## Without an audio device (headless, the dummy driver) it plays nothing, though
## the mix is still followed.

const AUDIO_BUS: StringName = &"Master"

## Plays when true; the mix is followed either way.
var enabled: bool = SoundCues.audio_available()
var table: MusicTable = null
var mix: MusicMix = null

var _players: Dictionary[String, AudioStreamPlayer] = {}
## Seconds of music played, for where a joining layer starts in its loop.
var _clock: float = 0.0


## A player for `music_table`, null meaning the shipped table; a rejected
## table is printed once and plays nothing.
func _init(music_table: MusicTable = null) -> void:
	name = "MusicPlayer"
	table = music_table if music_table != null else MusicTable.load_file()
	if table.error != "":
		print("Meltdown: music off: %s" % table.error)
	mix = MusicMix.new(table)


## Moves the mix `seconds` on in `mood` at `alarm` and sets the players.
## Returns the ids of the layers sounding.
func follow(mood: MusicMix.Mood, alarm: float, seconds: float) -> Array[String]:
	mix.advance(mood, alarm, seconds)
	_clock += maxf(0.0, seconds)
	if enabled:
		for layer: MusicLayer in table.layers:
			_set_player(layer, mix.gains[layer.id])
	return mix.sounding()


## The players sounding now; none while disabled.
func playing_count() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _players.values():
		if player.playing:
			count += 1
	return count


func _set_player(layer: MusicLayer, gain: float) -> void:
	var player: AudioStreamPlayer = _players.get(layer.id) as AudioStreamPlayer
	if gain <= 0.0:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		var stream: AudioStream = load(layer.sound) as AudioStream if ResourceLoader.exists(layer.sound) else null
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.bus = AUDIO_BUS
		player.stream = stream
		add_child(player)
		_players[layer.id] = player
	player.volume_db = mix.volume_db(layer, gain)
	if not player.playing and player.is_inside_tree():
		var length: float = player.stream.get_length()
		player.play(fmod(_clock, length) if length > 0.0 else 0.0)
