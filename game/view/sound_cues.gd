class_name SoundCues
extends Node3D

## Plays the sound cues (#1290, AUD-1): each as a positional source at the
## place `SoundCueEvents` gives it, in the simulation's space, so it sits
## where it happened. The listener is the current camera, the XR camera on the
## headset, so the sounds turn with the head.
##
## Pure view: it reads copies the session hands it and writes nothing back;
## the simulation never waits for or hears a sound (ARC-1, MP-2). Without an
## audio device (headless, the dummy driver) it plays nothing.

## The effects bus, where the room reverb is (#1291); Master until it is made.
const AUDIO_BUS: StringName = RoomReverb.BUS
## Players are cut off this far away, metres; the mines are not much longer
## across a room than this.
const MAX_DISTANCE_M: float = 80.0

## Plays cues when true; set false and nothing sounds, though the bolts are
## still followed so turning it back on does not burst every bolt in flight.
var enabled: bool = audio_available()
var table: SoundCueTable = null
var voices: SoundVoices = null
var cue_events: SoundCueEvents = SoundCueEvents.new()
## The cues started by the last `feed`, in order, for tests and the log.
var last_played: Array[String] = []

var _players: Array[AudioStreamPlayer3D] = []
## The voice number each player sounds, -1 when free.
var _player_voices: Array[int] = []
var _streams: Dictionary[String, AudioStream] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## A player for `cue_table`, null meaning the shipped table; a rejected table
## is printed once and plays nothing.
func _init(cue_table: SoundCueTable = null) -> void:
	name = "SoundCues"
	table = cue_table if cue_table != null else SoundCueTable.load_file()
	if table.error != "":
		print("Meltdown: sound cues off: %s" % table.error)
	voices = SoundVoices.new(table.max_voices, table.quiet_db)
	_rng.randomize()  # Pitch variety only; never the simulation's generator.


## Whether the engine has a real audio output; the dummy driver plays nothing.
static func audio_available() -> bool:
	return AudioServer.get_driver_name() != "Dummy"


## Takes in one advance: its `events`, the bolts after it and the ships after
## it (session copies), and plays the cues due. Returns the cues started.
func feed(events: Array[SimEvent], projectiles: Array[Projectile], ships: Array[ShipState]) -> Array[String]:
	var hits: Array[SoundCueHit] = cue_events.feed(events, projectiles, ships)
	last_played = []
	if not enabled:
		return last_played
	for hit: SoundCueHit in hits:
		if play(hit):
			last_played.append(hit.cue)
	return last_played


## Plays `hit`; false when its cue is silent, unknown, too small for its
## `min_magnitude` or its sound cannot be read.
func play(hit: SoundCueHit) -> bool:
	var cue: SoundCue = table.cue(hit.cue)
	if cue == null or not cue.sounds_at(hit.magnitude):
		return false
	var stream: AudioStream = _stream(cue.sound)
	if stream == null:
		return false
	var started: Array[int] = voices.start(cue.volume_db)
	var index: int = _player_for(started[1])
	var player: AudioStreamPlayer3D = _players[index]
	player.stop()
	_player_voices[index] = started[0]
	player.stream = stream
	player.volume_db = cue.volume_db
	player.pitch_scale = cue.pitch(_rng.randf())
	player.position = hit.position
	if player.is_inside_tree():
		player.play()
	return true


## Number of players in the pool, sounding or free.
func player_count() -> int:
	return _players.size()


## Forgets the bolts in flight, for a new level.
func reset() -> void:
	cue_events.reset()


## The player sounding voice `dropped`, else a free one, else a new one.
func _player_for(dropped: int) -> int:
	if dropped >= 0:
		var sounding: int = _player_voices.find(dropped)
		if sounding >= 0:
			return sounding
	var free: int = _player_voices.find(-1)
	if free >= 0:
		return free
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.bus = AUDIO_BUS
	player.max_distance = MAX_DISTANCE_M
	player.finished.connect(_on_finished.bind(_players.size()))
	add_child(player)
	_players.append(player)
	_player_voices.append(-1)
	return _players.size() - 1


func _on_finished(index: int) -> void:
	voices.finish(_player_voices[index])
	_player_voices[index] = -1


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[path]
