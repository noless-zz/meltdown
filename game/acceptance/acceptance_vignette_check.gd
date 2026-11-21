class_name AcceptanceVignetteCheck
extends RefCounted

## The `vignette` acceptance check (#850, CMF-1, CMF-2, ARC-3): the comfort
## table's "Vignette" row as the player sees it. Once per rendered frame while
## a step's replay flies, it reads the strength the `Vignette` node under the
## camera shows, with the ship's turn rate and speed as shown that frame, and
## judges it against the active preset's own `vignette_strength` and
## `vignette_trigger`, read through `ComfortWiring.preset_for` for the preset
## number in force, never copied and never from the wiring's live `preset`
## (a wiring fault there would then judge itself).
##
## Per frame: preset 4 (trigger never, or strength 0) shows exactly 0; no
## preset shows more than its strength; while the trigger is met the vignette
## shows; while it is not, the vignette may only fade, and is off once the
## trigger has been unmet for a few easing time constants. The fade is allowed
## because the shown strength is eased (`VignetteFeel`, #931), so it cannot
## drop to 0 on the frame the motion stops.
##
## The speeds are taken as `main.gd` shows them: the turn of the tick on
## screen (none on a snap tick, which the owner excluded, #931) and the speed
## interpolated like the rig's pose. It reads the scene; it writes nothing.

const NODE_PATH: NodePath = ^"XRRig/Camera/Vignette"
## Slack for float rounding in the shader parameter.
const STRENGTH_EPSILON: float = 0.0001
## Shown strength at or below which the vignette counts as off once settled.
const OFF_FLOOR: float = 0.01
## Easing time constants after which an unmet trigger must leave the vignette
## off: e^-5 of full strength is under `OFF_FLOOR`.
const SETTLE_TIME_CONSTANTS: float = 5.0
## Preset 4, which applies no comfort intervention of any kind (CMF-2): it
## shows no vignette whatever its file says.
const UNRESTRICTED_NUMBER: int = 4

## Frames measured, those that showed a vignette, and those whose trigger was met.
var frames: int = 0
var shown_frames: int = 0
var met_frames: int = 0
## The largest strength shown in any frame.
var max_strength: float = 0.0
## The first frame that broke its preset's row, or "".
var first_failure: String = ""
## Every preset flown, in order.
var preset_numbers: Array[int] = []
var _presets: Dictionary[int, ComfortPreset] = {}
## The strength shown last frame; 1 before the first, which may still show
## the fade of an earlier step.
var _last_shown: float = 1.0
var _unmet_seconds: float = 0.0


## A check for `step`, or null when the step does not list `vignette`.
static func for_step(step: AcceptanceStep) -> AcceptanceVignetteCheck:
	if not step.has_check(AcceptanceStep.CHECK_VIGNETTE):
		return null
	return AcceptanceVignetteCheck.new()


## Samples `main` after a frame of `delta` seconds: the shown strength, the
## session's ship as shown and the preset number in force.
func sample_main(main: Node, delta: float) -> void:
	var node: Vignette = main.get_node_or_null(NODE_PATH) as Vignette
	var session: LocalSession = main.get("session") as LocalSession
	var wiring: ComfortWiring = main.get("comfort") as ComfortWiring
	if node == null or session == null or wiring == null or session.paused:
		return
	var number: int = wiring.number
	if not _presets.has(number):
		_presets[number] = wiring.preset_for(number)
	var previous: ShipState = session.previous_ship()
	var current: ShipState = session.current_ship()
	var turn: float = 0.0 if wiring.latest_tick_snapped else turn_rate(previous, current)
	var speed: float = lerpf(previous.velocity.length(), current.velocity.length(),
		clampf(session.interpolation_fraction, 0.0, 1.0))
	sample(number, _presets[number], turn, speed, node.get_strength(), delta, _settle_seconds(main))


## Radians per second the ship turned over the one tick between `previous` and `current`.
static func turn_rate(previous: ShipState, current: ShipState) -> float:
	var from: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	return from.angle_to(to) / ShipState.TICK_DT


## One frame of `delta` seconds under preset `number`, whose values are
## `preset`: the ship turned at `turn` rad/s and moved at `speed` m/s, and the
## view showed `shown`. An unmet trigger must leave the vignette off after
## `settle_seconds`.
func sample(number: int, preset: ComfortPreset, turn: float, speed: float, shown: float, delta: float,
		settle_seconds: float) -> void:
	if preset == null:
		return
	frames += 1
	if not preset_numbers.has(number):
		preset_numbers.append(number)
	max_strength = maxf(max_strength, shown)
	if shown > 0.0:
		shown_frames += 1
	var met: bool = ComfortVignette.strength(preset, turn, speed) > 0.0
	_unmet_seconds = 0.0 if met else _unmet_seconds + delta
	if met:
		met_frames += 1
	if first_failure == "":
		var problem: String = _problem(number, preset, met, shown, settle_seconds)
		if problem != "":
			first_failure = "preset %d frame %d (turn %.1f°/s, speed %.2f m/s): %s" % [
				number, frames, rad_to_deg(turn), speed, problem]
	_last_shown = shown


## [result, message] once the replay has flown, adding the measurements.
func run(measurements: Dictionary) -> Array:
	measurements["vignette_frames"] = frames
	measurements["vignette_shown_frames"] = shown_frames
	measurements["vignette_met_frames"] = met_frames
	measurements["max_vignette_strength"] = max_strength
	if not preset_numbers.is_empty():
		measurements["vignette_preset"] = preset_numbers[0]
	if frames == 0:
		return [AcceptanceReport.RESULT_FAIL, "no frame of the vignette was measured"]
	var summary: String = "%d frames: trigger met on %d, vignette shown on %d (up to %.2f)" % [
		frames, met_frames, shown_frames, max_strength]
	if first_failure != "":
		return [AcceptanceReport.RESULT_FAIL, "%s; %s" % [first_failure, summary]]
	return [AcceptanceReport.RESULT_PASS, "preset %s, %s" % [_presets_text(), summary]]


## What is wrong with showing `shown` this frame, or "".
func _problem(number: int, preset: ComfortPreset, met: bool, shown: float, settle_seconds: float) -> String:
	var strength: float = clampf(preset.vignette_strength, 0.0, 1.0)
	if number == UNRESTRICTED_NUMBER or preset.vignette_trigger == ComfortPreset.VignetteTrigger.NEVER \
			or strength <= 0.0:
		if shown > 0.0:
			return "vignette shown at %.4f, but the preset never shows one" % shown
		return ""
	if shown > strength + STRENGTH_EPSILON:
		return "vignette shown at %.4f, above the preset's strength %.2f" % [shown, strength]
	if met and shown <= 0.0:
		return "vignette off (0) while the preset's trigger is met"
	if not met and shown > _last_shown + STRENGTH_EPSILON:
		return "vignette rose to %.4f from %.4f while the preset's trigger is not met" % [shown, _last_shown]
	if not met and _unmet_seconds > settle_seconds and shown > OFF_FLOOR:
		return "vignette still shown at %.4f %.2f s after the trigger stopped" % [shown, _unmet_seconds]
	return ""


## Seconds an unmet trigger may take to fade the vignette out, from the scene's
## own easing file so a tuned `vignette_feel.json` does not fail the check.
static func _settle_seconds(main: Node) -> float:
	var wiring: VignetteWiring = main.get("vignette") as VignetteWiring
	var smooth: float = wiring.feel.smooth_seconds if wiring != null and wiring.feel != null \
		else VignetteFeel.new().smooth_seconds
	return smooth * SETTLE_TIME_CONSTANTS


func _presets_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for number: int in preset_numbers:
		parts.append(str(number))
	return "→".join(parts)
