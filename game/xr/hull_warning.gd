class_name HullWarning
extends RefCounted

## The low-hull warning tone (#1456, AUD-1, CMB-2): while the ship's hull is at
## or below the table's threshold a short tone repeats from the dash, faster
## below the second threshold, so a pilot whose eyes are on the robots hears
## what the red hull bar and the low-hull pulse already say. It starts on the
## frame the hull falls to the threshold and stops on the frame it rises above
## it (repair, pickup) or the caller silences it.
##
## `DestroyedWiring` feeds it a copy of the hull fraction it already reads for
## the pulses, and silences it on end screens, at the shaft choice and once the
## run has ended; it is not fed at the base. It reads and writes no simulation
## state (MP-2) and no comfort setting (ARC-3). Its clock is the frames' own
## lengths, so the beat holds in the headset and in scripted acceptance runs
## alike; without an audio device it still records what it would play.

const NODE_NAME: String = "HullWarning"
## Where the speaker sits from the head point: low and ahead, on the dash.
const DASH_OFFSET: Vector3 = Vector3(0.0, -0.35, -0.5)
## Most hull fractions `beat_hulls` keeps.
const LOG_LIMIT: int = 64
## Frame lengths add up with rounding; a wait this close to 0 is due.
const EPSILON_S: float = 0.000001

var table: HullWarningTable
## Plays when true; when false only the log grows, for tests and checks.
var enabled: bool = SoundCues.audio_available()
## Tones asked for since the last `reset`, heard or not.
var requested: int = 0
## The hull fraction at each of those tones, oldest first.
var beat_hulls: Array[float] = []
## The speaker, under the rig once `attach` has run; null in tests.
var player: AudioStreamPlayer3D = null

## Seconds until the next tone; below 0 while silent.
var _wait: float = -1.0
var _stream: AudioStream = null


func _init(p_table: HullWarningTable = HullWarningTable.load_file()) -> void:
	table = p_table
	if table.error != "":
		push_warning("hull warning off: %s" % table.error)
		return
	_stream = load(table.sound) as AudioStream if ResourceLoader.exists(table.sound) else null


## Hangs the speaker under `rig`. Calling it again adds nothing.
func attach(rig: Node3D) -> void:
	if rig == null or player != null:
		return
	player = AudioStreamPlayer3D.new()
	player.name = NODE_NAME
	player.bus = RoomReverb.BUS
	# The dash is an arm's length away, so the file's level is the level heard.
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.attenuation_filter_cutoff_hz = 20500.0
	rig.add_child(player)


## One frame `seconds` long with the local ship's hull at `hull_fraction` of
## its maximum. `silenced` holds it quiet whatever the hull. The speaker goes
## to the dash in front of `head_point`. True when a tone was asked for.
func update(hull_fraction: float, seconds: float, silenced: bool, head_point: Transform3D) -> bool:
	if player != null:
		player.transform = head_point * Transform3D(Basis(), DASH_OFFSET)
	if not beat(hull_fraction, seconds, silenced):
		return false
	requested += 1
	beat_hulls.append(hull_fraction)
	if beat_hulls.size() > LOG_LIMIT:
		beat_hulls.pop_front()
	if enabled and _stream != null and player != null and player.is_inside_tree():
		player.stream = _stream
		player.volume_db = table.volume_db
		player.play()
	return true


## The beat alone: true on the frame a tone is due. The first tone sounds on
## the frame the hull reaches the threshold; falling into the faster band
## brings the next tone no later than the faster interval.
func beat(hull_fraction: float, seconds: float, silenced: bool) -> bool:
	var interval: float = 0.0 if silenced else table.interval_for(hull_fraction)
	if interval <= 0.0:
		_wait = -1.0
		return false
	if _wait < 0.0:
		_wait = interval
		return true
	_wait = minf(_wait - maxf(seconds, 0.0), interval)
	if _wait > EPSILON_S:
		return false
	_wait += interval
	if _wait <= EPSILON_S:  # A frame longer than the interval: one tone, not a burst.
		_wait = interval
	return true


## Silent, with an empty log: as at the start of a level.
func reset() -> void:
	_wait = -1.0
	requested = 0
	beat_hulls.clear()
	if player != null:
		player.stop()
