class_name ComfortWiring
extends RefCounted

## Joins this player's comfort preset to the input the session flies (CMF-1,
## CMF-3, CMF-6, ARC-3): the active preset and its filter, the development
## preset switch, and the bookkeeping that makes a snap or a reset fly in
## exactly one tick.
##
## It sits beside `main.gd` rather than in `xr/` because it writes the
## `net/` input source, which `xr/` may not depend on. It only ever hands
## inputs to that source; it never writes `ShipState` or `Sim` (ARC-3, MP-2).
##
## Every input it hands on is a whole copy of another input with only the
## fields it means to change set, so a field added to `ShipInput` later (as
## `reset_to_start` and `fire_primary` were) cannot be dropped here (#99).

## Number (1..4) of the active comfort preset; change it with `set_preset`.
var number: int = ComfortPresetFiles.START_NUMBER
var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
## Every frame's mapped input passes through this before the ship flies it.
var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
## True from the frame an input that must fly exactly once (a snap, or the
## reset) is set until a tick has flown it. A frame at 90 Hz runs no tick
## about one time in three, and a hitch runs several.
var one_tick_pending: bool = false

var _input_source: LatestInputSource
## Read for which hand carries the preset button.
var _mapping: ThumbstickMapping
## The preset switch acts once per press, not once per frame it is held.
var _preset_button_held: bool = false


func _init(p_input_source: LatestInputSource, p_mapping: ThumbstickMapping) -> void:
	_input_source = p_input_source
	_mapping = p_mapping


## Makes preset `p_number` (1..4) the active one with a fresh filter. Only
## this player's input handling changes; the ship is not touched (CMF-6).
func set_preset(p_number: int) -> void:
	number = p_number
	preset = ComfortPresetFiles.load_number(p_number)
	filter = ComfortInputFilter.new(preset)
	one_tick_pending = false
	print("Meltdown: comfort preset %d %s" % [p_number, preset.display_name])


## The development preset switch: the upper face button of the hand that does
## not turn (Y, or B when left-handed). Read here rather than bound in the
## mapping, since it is not a flight control and a settings menu replaces it.
func preset_button() -> String:
	return "right_button_upper" if _mapping.left_handed else "left_button_upper"


## Moves to the next preset on the frame the preset button goes down.
func read_preset_button(buttons: Dictionary) -> void:
	var pressed: bool = bool(buttons.get(preset_button(), false))
	if pressed and not _preset_button_held:
		set_preset(ComfortPresetFiles.next_number(number))
	_preset_button_held = pressed


## Hands this frame's mapped `input` to the session's input source.
## `orientation` is the ship's, read only, for the pitch limit and auto-level.
## `reset_due` replaces the input with a still reset tick.
func hand_input(input: ShipInput, orientation: Basis, reset_due: bool) -> void:
	if one_tick_pending:
		var held: ShipInput = _input_source.latest_input()
		if held.reset_to_start:
			return  # A pending reset flies whole.
		# No tick has flown the snap yet: keep its turn, take everything else new.
		var next: ShipInput = ComfortInputFilter.copy_input(input)
		next.turn_q = held.turn_q
		_input_source.set_input(next)
		return
	var filtered: ShipInput = filter.filter(input, orientation)
	if reset_due:
		# Still and not firing, so the reset tick ends exactly at the start pose.
		filtered.thrust_q = Vector3i.ZERO
		filtered.turn_q = Vector3i.ZERO
		filtered.afterburner = false
		filtered.fire_primary = false
		filtered.reset_to_start = true
	one_tick_pending = carries_snap(filtered) or filtered.reset_to_start
	_input_source.set_input(filtered)


## True when `input` turns the ship by a snap on an axis the preset snaps.
func carries_snap(input: ShipInput) -> bool:
	return (preset.yaw_mode == ComfortPreset.YawMode.SNAP and input.turn_q.y != 0) \
		or (preset.pitch_mode == ComfortPreset.PitchMode.SNAP and input.turn_q.x != 0)


## Call after the session advanced `ticks` ticks. Once a tick has flown a snap
## or the reset, later ticks before the next sample must not repeat it; the
## filter keeps a snapped axis at zero until the stick returns. Returns true
## when the flown input was the reset, so the caller can fade back in.
func end_one_tick_if_flown(ticks: int) -> bool:
	if not one_tick_pending or ticks == 0:
		return false
	one_tick_pending = false
	var flown: ShipInput = ComfortInputFilter.copy_input(_input_source.latest_input())
	if flown.reset_to_start:
		# Nothing is held until the next sample.
		_input_source.set_input(ShipInput.new())
		return true
	if preset.pitch_mode == ComfortPreset.PitchMode.SNAP:
		flown.turn_q.x = 0
	if preset.yaw_mode == ComfortPreset.YawMode.SNAP:
		flown.turn_q.y = 0
	_input_source.set_input(flown)
	return false


## Radians a tick must turn to be shown as a snap: half a snap while the
## preset snaps yaw or pitch, 0 (never) otherwise.
func snap_show_angle() -> float:
	var snaps: bool = preset.yaw_mode == ComfortPreset.YawMode.SNAP \
		or preset.pitch_mode == ComfortPreset.PitchMode.SNAP
	return deg_to_rad(preset.snap_angle_deg) * 0.5 if snaps else 0.0


## The ship's pose `fraction` of the way from `previous` to `current`:
## position lerped, rotation slerped. Frames fall between ticks, so showing
## either tick's pose alone would judder at 72 or 90 Hz against a 60 Hz sim.
## A turn of at least `snap_angle` (when above 0) is a snap and is shown at
## once: slerping it would show a snap as smooth rotation (CMF-3).
static func interpolated_pose(previous: ShipState, current: ShipState, fraction: float,
		snap_angle: float = 0.0) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	var from_rotation: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to_rotation: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	var rotation: Quaternion = from_rotation.slerp(to_rotation, weight)
	if snap_angle > 0.0 and from_rotation.angle_to(to_rotation) >= snap_angle:
		rotation = to_rotation
	return Transform3D(Basis(rotation), previous.position.lerp(current.position, weight))
