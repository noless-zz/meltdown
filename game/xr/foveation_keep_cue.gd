class_name FoveationKeepCue
extends Node3D

## The sounds and pulses of `FoveationKeep` (#1523): a short low tone when a
## new foveation setting starts waiting, a rising one when it is kept and a
## falling one when it reverts, each with a pulse on both hands, so the pilot
## knows what happened without reading a picture that may be broken.
##
## It hangs under the rig's camera, so each tone comes from the head. The
## tones are sine sweeps built here from `FoveationKeepSpec.tones`: no sound
## file, nothing from any other game (NAM-3). Processed always, so it is heard
## while the open menu pauses solo play. Pure view: no simulation state (ARC-3).

const NODE_NAME: String = "FoveationKeepCue"
## The OpenXR output action bound to both hands, as `HitHaptics` uses.
const HAPTIC_ACTION: String = "haptic"
const MIX_RATE: int = 22050
## Fade in and out over this long, so a tone starts and ends without a click.
const EDGE_S: float = 0.01

var spec: FoveationKeepSpec
## Plays when true; when false only `played` grows, for tests and the flat build.
var enabled: bool = SoundCues.audio_available()
## Cue names sounded, oldest first, for tests.
var played: Array[String] = []
var left_controller: XRController3D = null
var right_controller: XRController3D = null

var _player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
var _streams: Dictionary[String, AudioStreamWAV] = {}


func _init(p_spec: FoveationKeepSpec) -> void:
	name = NODE_NAME
	spec = p_spec
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.name = "Tone"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_player.attenuation_filter_cutoff_hz = 20500.0
	add_child(_player)
	for cue: String in FoveationKeepSpec.CUES:
		var tone: Dictionary = spec.tones[cue]
		_streams[cue] = sweep(float(tone["from_hz"]), float(tone["to_hz"]), float(tone["duration_s"]))


## Puts a cue for `keep` under `rig`'s camera (the rig itself without one) and
## finds its hands. Returns null without a rig.
static func attach_to(rig: Node3D, keep: FoveationKeep) -> FoveationKeepCue:
	if rig == null or keep == null:
		return null
	var cue: FoveationKeepCue = FoveationKeepCue.new(keep.spec)
	var camera: Node3D = rig.get_node_or_null("Camera") as Node3D
	(camera if camera != null else rig).add_child(cue)
	cue.left_controller = rig.get_node_or_null("LeftHand") as XRController3D
	cue.right_controller = rig.get_node_or_null("RightHand") as XRController3D
	keep.cue_hook = cue.play
	return cue


## A mono 16-bit sine sweeping from `from_hz` to `to_hz` over `duration_s`.
static func sweep(from_hz: float, to_hz: float, duration_s: float) -> AudioStreamWAV:
	var count: int = maxi(int(duration_s * MIX_RATE), 1)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var edge: float = minf(1.0, minf(t, duration_s - t) / EDGE_S)
		bytes.encode_s16(i * 2, int(sin(phase) * maxf(edge, 0.0) * 32000.0))
		phase += TAU * lerpf(from_hz, to_hz, float(i) / count) / MIX_RATE
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## The tone built for `cue`, or null for an unknown one.
func stream_for(cue: String) -> AudioStreamWAV:
	return _streams.get(cue, null)


## Sounds `cue` at the head and pulses both hands.
func play(cue: String) -> void:
	if not _streams.has(cue):
		return
	played.append(cue)
	if enabled and is_inside_tree():
		_player.stream = _streams[cue]
		_player.volume_db = float(spec.tones[cue]["volume_db"])
		_player.play()
	var pulse: Dictionary = spec.pulses[cue]
	var xr: XRInterface = XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		return
	for hand: XRController3D in [left_controller, right_controller]:
		if hand != null:
			hand.trigger_haptic_pulse(HAPTIC_ACTION, float(pulse["frequency_hz"]),
				float(pulse["amplitude"]), float(pulse["duration_s"]), 0.0)
