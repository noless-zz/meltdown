class_name EngineSound
extends Node3D

## The pilot's own engine (#1398, AUD-1): a low idle hum always on in flight,
## a thrust layer whose volume and pitch follow `EngineSoundMix`'s drive, and a
## short burst when the afterburner kicks in.
##
## The node sits at the ship's pose and its players at the table's offset,
## below and behind the seat, so the sound stays put in the cockpit as the
## head turns, as the ship around the pilot does. Distance attenuation is off:
## the pilot never moves away from his own engine, so the table's levels are
## the levels heard. The players use the effects bus, so the room reverb
## (#1291) is on the engine too.
##
## Pure view: it is handed session copies and writes nothing back (ARC-1,
## MP-2). Without an audio device it follows the mix but plays nothing.

const BUS: StringName = RoomReverb.BUS
## The local ship, the one whose engine is heard.
const LOCAL_SHIP: int = 0

## Plays when true; when false the mix is still followed, for tests and checks.
var enabled: bool = SoundCues.audio_available()
var table: EngineSoundTable = null
var mix: EngineSoundMix = null
## Afterburner bursts started since the engine was made, for tests and checks.
var bursts: int = 0

var _idle: AudioStreamPlayer3D = null
var _thrust: AudioStreamPlayer3D = null
var _burst: AudioStreamPlayer3D = null


## An engine for `engine_table`, null meaning the shipped table; a rejected
## table is printed once and the engine stays silent.
func _init(engine_table: EngineSoundTable = null) -> void:
	name = "EngineSound"
	table = engine_table if engine_table != null else EngineSoundTable.load_file()
	if table.error != "":
		print("Meltdown: engine sound off: %s" % table.error)
	mix = EngineSoundMix.new(table)
	_idle = _player("Idle", table.idle_sound)
	_thrust = _player("Thrust", table.thrust_sound)
	_burst = _player("Burst", table.burst_sound)


## Follows the local ship for `seconds`: `before` and `after` are its session
## copies one tick apart, `pose` where it is drawn this frame and `events` the
## last advance's. `flying` is false on end screens and at the base, where the
## engine fades out.
func follow(before: ShipState, after: ShipState, pose: Transform3D, events: Array[SimEvent],
		flying: bool, seconds: float) -> void:
	var on: bool = flying and table.error == "" and after != null
	mix.advance(on, EngineSoundMix.thrust_of(before, after), EngineSoundMix.speed_of(after), seconds)
	transform = pose
	_set_loop(_idle, mix.sounding(), mix.idle_db(), table.idle_pitch)
	_set_loop(_thrust, mix.thrust_sounding(), mix.thrust_db(), mix.thrust_pitch())
	if on and _boosted(events):
		bursts += 1
		_burst.volume_db = table.burst_db
		if enabled and _burst.stream != null and _burst.is_inside_tree():
			_burst.play()


## Silences the engine at once, for a new level; it fades back in as it flies.
func reset() -> void:
	mix.gain = 0.0
	mix.drive = 0.0
	for player: AudioStreamPlayer3D in [_idle, _thrust, _burst]:
		player.stop()


## The players sounding now; none while disabled.
func playing_count() -> int:
	var count: int = 0
	for player: AudioStreamPlayer3D in [_idle, _thrust, _burst]:
		if player.playing:
			count += 1
	return count


## The idle, thrust or burst player, for tests.
func player(which: String) -> AudioStreamPlayer3D:
	return {"idle": _idle, "thrust": _thrust, "burst": _burst}.get(which, null)


func _set_loop(loop: AudioStreamPlayer3D, heard: bool, volume_db: float, pitch: float) -> void:
	loop.volume_db = volume_db
	loop.pitch_scale = pitch
	if not heard:
		if loop.playing:
			loop.stop()
		return
	if enabled and not loop.playing and loop.stream != null and loop.is_inside_tree():
		loop.play()


static func _boosted(events: Array[SimEvent]) -> bool:
	for event: SimEvent in events:
		if event.ship == LOCAL_SHIP and event.kind == SimEvent.Kind.AFTERBURNER_STARTED:
			return true
	return false


func _player(player_name: String, path: String) -> AudioStreamPlayer3D:
	var made: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	made.name = player_name
	made.bus = BUS
	made.position = table.offset
	made.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	made.attenuation_filter_cutoff_hz = 20500.0
	made.stream = load(path) as AudioStream if path != "" and ResourceLoader.exists(path) else null
	add_child(made)
	return made
