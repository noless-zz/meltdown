class_name AcceptanceHitMotionCheck
extends RefCounted

## The `hit_view_motion` acceptance check (#849, CMF-1, CMF-6, ARC-3): the
## comfort table's "Hits" row as the player sees it. Once per rendered frame
## while a step's replay flies, it takes the camera the player sees through,
## removes the tracked head, the recentre offset and the ship's own pose for
## the frame (as `main.gd` places the rig from the simulation), and keeps what
## is left: the view motion nothing in the simulation or the head explains.
## The hit effect (`HitShake`) is the only thing that adds such motion, so the
## remainder splits into shake (how far the eye moved, metres) and spin (how
## far the view rolled, degrees).
##
## It judges against the active preset's own `hit_shake` and `hit_spin`, read
## through `ComfortWiring.preset_for` for the preset number in force, the way
## `set_preset` loads them, never copied. Not from the wiring's live `preset`:
## a wiring fault that puts other values there would then judge itself. A preset
## with `hit_shake` 0 may show no shake frame and one above 0 must show some;
## a preset with `hit_spin` off may show no spin frame and one with it on must
## show some. So a wiring change that drops hit motion from presets 2 to 4, or
## adds spin to 2 or 3, fails here. It reads the scene; it writes nothing.

## Eye movement, in metres, above which a frame counts as shaken. Preset 2's
## light shake reaches 6 mm at full strength; float noise on a pose some way
## from the origin stays well under this.
const SHAKE_FLOOR_M: float = 0.0005
## View roll, in degrees, above which a frame counts as spun. Preset 4's spin
## reaches 6° at full strength.
const SPIN_FLOOR_DEG: float = 0.05

## Frames measured, and those that showed shake or spin.
var frames: int = 0
var shake_frames: int = 0
var spin_frames: int = 0
## The largest shake (metres) and spin (degrees) seen in any frame.
var max_shake_m: float = 0.0
var max_spin_deg: float = 0.0
## The first frame that showed motion its preset does not allow, or "".
var first_failure: String = ""
## Every preset flown, in order, with each one's ComfortPreset and its
## [shake frames, spin frames], keyed by preset number.
var preset_numbers: Array[int] = []
var _presets: Dictionary[int, ComfortPreset] = {}
var _counts: Dictionary[int, Array] = {}


## A check for `step`, or null when the step does not list `hit_view_motion`.
static func for_step(step: AcceptanceStep) -> AcceptanceHitMotionCheck:
	if not step.has_check(AcceptanceStep.CHECK_HIT_VIEW_MOTION):
		return null
	return AcceptanceHitMotionCheck.new()


## Samples the view of `main` after a frame: its rig camera, session, head
## recentre and comfort wiring, read the way `main.gd` places the rig.
func sample_main(main: Node) -> void:
	var camera: Node3D = main.get_node_or_null("XRRig/Camera") as Node3D
	var session: LocalSession = main.get("session") as LocalSession
	var recentre: HeadRecentre = main.get("head_recentre") as HeadRecentre
	var wiring: ComfortWiring = main.get("comfort") as ComfortWiring
	if camera == null or session == null or recentre == null or wiring == null:
		return
	var pose: Transform3D = ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction, wiring.latest_tick_snapped)
	var rig_world: Transform3D = world_transform(camera) * camera.transform.affine_inverse()
	var number: int = wiring.number
	var preset: ComfortPreset = _presets.get(number) if _presets.has(number) else wiring.preset_for(number)
	sample(unexplained(pose, rig_world, recentre.offset), number, preset)


## The part of the rig's world transform `rig_world` that neither the ship's
## pose `pose` nor the recentre offset `offset` explains, in the cockpit's own
## frame: `main.gd` sets the rig to pose × hit offset × recentre offset.
static func unexplained(pose: Transform3D, rig_world: Transform3D, offset: Transform3D) -> Transform3D:
	return pose.affine_inverse() * rig_world * offset.affine_inverse()


## The world transform of `node`, composed up its parents by hand so it also
## works outside a scene tree, where the tests fly the main scene.
static func world_transform(node: Node3D) -> Transform3D:
	var transform: Transform3D = node.transform
	var parent: Node3D = node.get_parent() as Node3D
	while parent != null:
		transform = parent.transform * transform
		parent = parent.get_parent() as Node3D
	return transform


## One frame's unexplained view motion `motion`, flown under preset `number`,
## whose values are `preset`.
func sample(motion: Transform3D, number: int, preset: ComfortPreset) -> void:
	if preset == null:
		return
	frames += 1
	if not _presets.has(number):
		preset_numbers.append(number)
		_presets[number] = preset
		_counts[number] = [0, 0]
	var shake: float = motion.origin.length()
	var spin: float = rad_to_deg(motion.basis.orthonormalized().get_rotation_quaternion().get_angle())
	max_shake_m = maxf(max_shake_m, shake)
	max_spin_deg = maxf(max_spin_deg, spin)
	if shake > SHAKE_FLOOR_M:
		shake_frames += 1
		_counts[number][0] += 1
		if preset.hit_shake <= 0.0 and first_failure == "":
			first_failure = "preset %d frame %d: the view shook %.1f mm, but hit_shake is 0" % [
				number, frames, shake * 1000.0]
	if spin > SPIN_FLOOR_DEG:
		spin_frames += 1
		_counts[number][1] += 1
		if not preset.hit_spin and first_failure == "":
			first_failure = "preset %d frame %d: the view spun %.2f°, but hit_spin is off" % [
				number, frames, spin]


## [result, message] once the replay has flown, adding the measurements.
func run(measurements: Dictionary) -> Array:
	measurements["hit_motion_frames"] = frames
	measurements["hit_shake_frames"] = shake_frames
	measurements["hit_spin_frames"] = spin_frames
	measurements["max_hit_shake_mm"] = max_shake_m * 1000.0
	measurements["max_hit_spin_deg"] = max_spin_deg
	if not preset_numbers.is_empty():
		measurements["hit_motion_preset"] = preset_numbers[0]
	if frames == 0:
		return [AcceptanceReport.RESULT_FAIL, "no frame of the view was measured"]
	var summary: String = "%d frames: shake on %d (up to %.1f mm), spin on %d (up to %.2f°)" % [
		frames, shake_frames, max_shake_m * 1000.0, spin_frames, max_spin_deg]
	var failure: String = first_failure if first_failure != "" else _missing()
	if failure != "":
		return [AcceptanceReport.RESULT_FAIL, "%s; %s" % [failure, summary]]
	return [AcceptanceReport.RESULT_PASS, "preset %s, %s" % [_presets_text(), summary]]


## Why a preset flown did not show the motion its hits row asks for, or "".
func _missing() -> String:
	for number: int in preset_numbers:
		var preset: ComfortPreset = _presets[number]
		if preset.hit_shake > 0.0 and int(_counts[number][0]) == 0:
			return "preset %d: no frame shook the view, but hit_shake is %.2f" % [number, preset.hit_shake]
		if preset.hit_spin and int(_counts[number][1]) == 0:
			return "preset %d: no frame spun the view, but hit_spin is on" % number
	return ""


func _presets_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for number: int in preset_numbers:
		parts.append(str(number))
	return "→".join(parts)
