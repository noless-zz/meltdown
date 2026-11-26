class_name LaunchSound
extends AudioStreamPlayer3D

## The rising engine sound of the pilot's ship leaving the home base (#1396,
## AUD-1, NAM-3): played once from the cradle ship when Launch is chosen, while
## its engine glow rises and the view fades out. The sound is original,
## synthesised by `tools/synth_launch.py`. It sits at the ship, so it is heard
## from where the ship stands; distance attenuation is off, since the ship is a
## few metres from the seat and the file's level is the level heard.
##
## Pure view: it reads and writes no simulation state (ARC-3, MP-2). Without
## an audio device it counts the launches but plays nothing.

const NODE_NAME: String = "LaunchSound"
const SOUND: String = "res://data/audio/launch.wav"
const VOLUME_DB: float = -4.0

## Plays when true; when false only `played` counts, for tests and checks.
var enabled: bool = SoundCues.audio_available()
## Launches sounded since the node was made, for tests and checks.
var played: int = 0


func _init() -> void:
	name = NODE_NAME
	bus = RoomReverb.BUS
	volume_db = VOLUME_DB
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	attenuation_filter_cutoff_hz = 20500.0
	stream = load(SOUND) as AudioStream if ResourceLoader.exists(SOUND) else null


## Sounds the launch once from the start.
func sound() -> void:
	played += 1
	if enabled and stream != null and is_inside_tree():
		play()
