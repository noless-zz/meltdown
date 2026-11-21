class_name AcceptanceComfortCheck
extends RefCounted

## The `comfort_motion` acceptance check (#687, CMF-1, CMF-3, CMF-8, ARC-3):
## while a step's replay flies, the runner hands it the view's world rotation
## and the tracked head's rotation once per rendered frame. It measures how
## fast the game turned the view (ship, comfort filter and shake: the view
## with the head taken out) about the rig's pitch, yaw and roll axes, and
## measures the head on its own. CMF-1 and CMF-3 limit artificial rotation,
## not the player's neck, so a tester looking around must not fail a step
## (#735); with the head held still, as on Monado and the desktop, nothing
## changes. Unlike `test_comfort_limits.gd`, which tests
## the comfort filter alone, this reads the camera the player sees through,
## so a wiring change that turns the view some other way shows here.
##
## The limits are the active preset's own values (`ComfortPreset`, as
## `ComfortWiring` applies it), never copies: preset 1 fails on any smooth
## rotation, preset 2 on yaw or pitch faster than its caps, presets 3 and 4
## only report. It reads the camera and the preset; it writes nothing.

## A frame turning the view by more than this, in degrees, is rotation the
## player sees (CMF-3); less is numerical noise.
const SMOOTH_FRAME_DEG: float = 0.5
## How far over a preset's rate cap a frame may go before it fails: 5 %.
const CAP_TOLERANCE: float = 0.05
## The preset numbers whose limits are checked; the others only report.
const NO_SMOOTH_PRESET: int = 1
const CAPPED_PRESET: int = 2
## Head turns beyond this, in degrees, are named in the result line, so a
## report read later shows the headset was worn and moved during the step.
const HEAD_TURN_NOTE_DEG: float = 5.0

var preset_number: int = 0
var preset: ComfortPreset = null
## Frames measured, frames that turned smoothly, frames that jumped at once.
var frames: int = 0
var smooth_rotation_frames: int = 0
var snap_frames: int = 0
## Fastest smooth turn about each view axis, in degrees per second. A jump
## (a snap or the reset) is not motion and is counted in `snap_frames` instead.
var max_yaw_deg_s: float = 0.0
var max_pitch_deg_s: float = 0.0
var max_roll_deg_s: float = 0.0
## The first frame that broke the preset's limit, or "".
var first_failure: String = ""
## The head on its own (#735): the largest angle it turned away from where it
## was on the first frame, and its fastest turn, in degrees per second.
var head_turn_deg: float = 0.0
var max_head_deg_s: float = 0.0

var _previous: Basis = Basis.IDENTITY
var _first_head: Basis = Basis.IDENTITY
var _previous_head: Basis = Basis.IDENTITY
var _has_previous: bool = false


func _init(p_preset_number: int, p_preset: ComfortPreset) -> void:
	preset_number = p_preset_number
	preset = p_preset


## A check for `step` reading `main`'s active preset, or null when the step
## does not list `comfort_motion`. Call after the step's preset is set.
static func for_step(step: AcceptanceStep, main: Node) -> AcceptanceComfortCheck:
	if not step.has_check(AcceptanceStep.CHECK_COMFORT_MOTION):
		return null
	var wiring: ComfortWiring = main.get("comfort") as ComfortWiring
	if wiring == null:
		return AcceptanceComfortCheck.new(0, null)
	return AcceptanceComfortCheck.new(wiring.number, wiring.preset)


## Samples the view of `main` after a frame that showed `seconds` of flight:
## the rig's camera, which is the XR camera on the headset and the flat
## camera on a desktop. The camera's own transform under the rig is the
## tracked head pose; nothing in the game writes it.
func sample_main(main: Node, seconds: float) -> void:
	var camera: Node3D = main.get_node_or_null("XRRig/Camera") as Node3D
	if camera != null:
		sample(world_basis(camera), seconds, camera.transform.basis)


## The world rotation of `node`, composed up its parents by hand so it also
## works outside a scene tree, where the runner's tests fly the main scene.
static func world_basis(node: Node3D) -> Basis:
	var basis: Basis = node.transform.basis
	var parent: Node3D = node.get_parent() as Node3D
	while parent != null:
		basis = parent.transform.basis * basis
		parent = parent.get_parent() as Node3D
	return basis.orthonormalized()


## One rendered frame: the view's world rotation `view` after `seconds` of
## flight, and `head`, the tracked head's rotation inside the rig, which is
## part of `view`. Only the rest, what the game did, is judged.
func sample(view: Basis, seconds: float, head: Basis = Basis.IDENTITY) -> void:
	var head_now: Basis = head.orthonormalized()
	var current: Basis = (view.orthonormalized() * head_now.inverse()).orthonormalized()
	if not _has_previous or seconds <= 0.0:
		if not _has_previous:
			_first_head = head_now
		_previous = current
		_previous_head = head_now
		_has_previous = true
		return
	frames += 1
	_measure_head(head_now, seconds)
	# The game's turn between frames in the rig's own axes: x pitch, y yaw, z roll.
	var turn: Quaternion = (_previous.inverse() * current).get_rotation_quaternion()
	_previous = current
	var angle: float = rad_to_deg(turn.get_angle())
	if angle <= SMOOTH_FRAME_DEG:
		return
	if angle >= snap_floor_deg():
		snap_frames += 1
		return
	smooth_rotation_frames += 1
	var axis_deg: Vector3 = turn.get_axis().normalized() * angle
	var yaw: float = absf(axis_deg.y) / seconds
	var pitch: float = absf(axis_deg.x) / seconds
	max_yaw_deg_s = maxf(max_yaw_deg_s, yaw)
	max_pitch_deg_s = maxf(max_pitch_deg_s, pitch)
	max_roll_deg_s = maxf(max_roll_deg_s, absf(axis_deg.z) / seconds)
	if first_failure == "":
		first_failure = _frame_failure(angle, yaw, pitch)


static func _angle_deg(from: Basis, to: Basis) -> float:
	return rad_to_deg((from.inverse() * to).get_rotation_quaternion().get_angle())


func _measure_head(head_now: Basis, seconds: float) -> void:
	head_turn_deg = maxf(head_turn_deg, _angle_deg(_first_head, head_now))
	max_head_deg_s = maxf(max_head_deg_s, _angle_deg(_previous_head, head_now) / seconds)
	_previous_head = head_now


## The smallest turn, in degrees, shown in a single frame that counts as a
## jump rather than motion: the preset's snap angle, or its auto-level snap
## threshold when that is smaller (an auto-level snap may be just over it).
## Nothing smooth a preset allows turns this far in one frame.
func snap_floor_deg() -> float:
	if preset == null:
		return INF
	var floor_deg: float = preset.snap_angle_deg
	if preset.levels_roll() and preset.auto_level_snap_threshold_deg > ComfortPreset.NO_LIMIT:
		floor_deg = minf(floor_deg, preset.auto_level_snap_threshold_deg)
	return floor_deg


## Why one smooth frame breaks the preset's limit, or "".
func _frame_failure(angle: float, yaw: float, pitch: float) -> String:
	if preset_number == NO_SMOOTH_PRESET:
		return "frame %d turned the view %.2f° smoothly (CMF-3 allows none)" % [frames, angle]
	if preset_number != CAPPED_PRESET:
		return ""
	var yaw_cap: float = preset.yaw_rate_cap_deg_per_s
	if yaw_cap > ComfortPreset.NO_LIMIT and yaw > yaw_cap * (1.0 + CAP_TOLERANCE):
		return "frame %d yawed %.1f°/s, cap %.1f°/s" % [frames, yaw, yaw_cap]
	var pitch_cap: float = preset.pitch_rate_cap_deg_per_s
	if pitch_cap > ComfortPreset.NO_LIMIT and pitch > pitch_cap * (1.0 + CAP_TOLERANCE):
		return "frame %d pitched %.1f°/s, cap %.1f°/s" % [frames, pitch, pitch_cap]
	return ""


## [result, message] once the replay has flown, adding the measurements.
func run(measurements: Dictionary) -> Array:
	measurements["comfort_preset"] = preset_number
	measurements["max_yaw_deg_s"] = max_yaw_deg_s
	measurements["max_pitch_deg_s"] = max_pitch_deg_s
	measurements["max_roll_deg_s"] = max_roll_deg_s
	measurements["smooth_rotation_frames"] = smooth_rotation_frames
	measurements["snap_frames"] = snap_frames
	measurements["comfort_frames"] = frames
	measurements["head_turn_deg"] = head_turn_deg
	measurements["max_head_deg_s"] = max_head_deg_s
	if preset == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no comfort preset to read"]
	if frames == 0:
		return [AcceptanceReport.RESULT_FAIL, "no frame of the view was measured"]
	var summary: String = "preset %d, %d frames: yaw %.1f°/s, pitch %.1f°/s, roll %.1f°/s at most; %d smooth, %d jumps" % [
		preset_number, frames, max_yaw_deg_s, max_pitch_deg_s, max_roll_deg_s, smooth_rotation_frames, snap_frames]
	if head_turn_deg > HEAD_TURN_NOTE_DEG:
		summary += "; the head turned up to %.0f° (%.0f°/s at most), not counted" % [head_turn_deg, max_head_deg_s]
	if first_failure != "":
		return [AcceptanceReport.RESULT_FAIL, "%s; %s" % [first_failure, summary]]
	return [AcceptanceReport.RESULT_PASS, summary]
