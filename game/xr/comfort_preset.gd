class_name ComfortPreset
extends Resource

## One comfort preset: one field per row of the comfort table in requirements
## section 3 (CMF-1). The four presets are `.tres` files in
## `res://xr/presets/`; a custom preset is a duplicate of any of them with any
## field changed.
##
## A preset describes only how motion is shown to this player. It holds no
## speed, damage or timer and references nothing in `core/`, so it cannot
## change the simulation (CMF-6, ARC-3).
##
## Where a rate or angle has no limit, the field holds `NO_LIMIT`.

const NO_LIMIT: float = 0.0
## `break_reminder_minutes` before a file sets it. Below 0, so a file that
## leaves the field out, or gives it a value that is not a number, fails
## `validation_error()` instead of silently taking a default (CMF-10).
const BREAK_REMINDER_UNSET: float = -1.0

enum YawMode { SNAP, SMOOTH }
enum PitchMode { SNAP, SMOOTH }
enum RollMode {
	## Roll input is ignored and the view levels itself.
	OFF_AUTO_LEVEL,
	## The player rolls; `auto_level` chooses whether the view levels itself.
	MANUAL,
	## The player rolls and nothing levels the view.
	FULLY_MANUAL,
}
enum VignetteTrigger { NEVER, FAST_ROTATION, ROTATION, ALL_MOTION }
## Named `CockpitKind` because `CockpitFrame` is the node that draws it.
enum CockpitKind { SOLID_SMALL_WINDOWS, SOLID_WIDE_CANOPY, OPEN_CANOPY, MINIMAL_GLASS }

@export var display_name: String = ""

@export_group("Yaw")
@export var yaw_mode: YawMode = YawMode.SMOOTH
## Degrees turned by one snap; used when either axis snaps.
@export var snap_angle_deg: float = 30.0
## Degrees per second; `NO_LIMIT` for none. Applies to smooth yaw only.
@export var yaw_rate_cap_deg_per_s: float = NO_LIMIT

@export_group("Pitch")
@export var pitch_mode: PitchMode = PitchMode.SMOOTH
## Degrees per second; `NO_LIMIT` for none. Applies to smooth pitch only.
@export var pitch_rate_cap_deg_per_s: float = NO_LIMIT
## Largest nose angle above or below the horizon, in degrees; `NO_LIMIT` for none.
@export var pitch_limit_deg: float = NO_LIMIT

@export_group("Roll")
@export var roll_mode: RollMode = RollMode.FULLY_MANUAL
## Whether the view levels itself when the player stops rolling.
@export var auto_level: bool = false
## Fastest smooth roll back to level, in degrees per second; `NO_LIMIT` levels
## in one tick. A guess until the headset session; adjust freely.
@export var auto_level_rate_deg_per_s: float = 30.0
## Bank in degrees beyond which the view snaps level in a single tick, and
## below which it is left alone; `NO_LIMIT` levels smoothly instead. A snap
## keeps auto-level free of smooth rotation (CMF-3).
@export var auto_level_snap_threshold_deg: float = NO_LIMIT

@export_group("Vignette")
## 0 is no vignette, 1 the narrowest field of view the vignette allows.
@export_range(0.0, 1.0) var vignette_strength: float = 0.0
@export var vignette_trigger: VignetteTrigger = VignetteTrigger.NEVER

@export_group("Cockpit")
@export var cockpit_frame: CockpitKind = CockpitKind.MINIMAL_GLASS
## The cockpit data file (`CockpitSpec`) that gives `cockpit_frame` its
## shape: window sizes, distance, glass, shapes and colours.
@export_file("*.json") var cockpit_file: String = "res://xr/cockpits/glass.json"

@export_group("Acceleration feel")
## Eases the shown acceleration in and out; the simulated speed is unchanged.
@export var acceleration_softening: bool = false
## Lets the view lag behind sudden changes of velocity, then settle.
@export var inertia_drift: bool = false

@export_group("Hits")
## 0 is no cockpit shake on a hit, 1 the full shake.
@export_range(0.0, 1.0) var hit_shake: float = 0.0
## Whether a hit also spins the view.
@export var hit_spin: bool = false

@export_group("Display")
## Headset refresh rate in Hz.
@export var refresh_rate_hz: int = 90
## Whether the player may switch the headset to 120 Hz.
@export var allow_120_hz: bool = false

@export_group("Breaks")
## Minutes of flying before the "take a break" prompt (CMF-10); 0 is off.
@export var break_reminder_minutes: float = BREAK_REMINDER_UNSET

@export_group("Aim")
## Look-aim (CMB-6, CMB-8, decision record 0010): the guns aim where the head
## looks, within the core's cone. On at preset 1, on by default at preset 2
## (the pilot's option), off at 3 and 4 until a crafted module exists. Read by
## `LookAimHead`; it changes only the aim the player asks for, never the cone,
## the gimbal rate or the damage (CMF-6). The custom file cannot set it.
@export var look_aim: bool = false

@export_group("Swivel chair")
## Swivel-chair mode (CMF-7): turning the body in a real chair turns the ship.
## Off on every shipped preset; the custom file can switch it on. Read by
## `SwivelYaw`. The tuning below is a guess for a headset session.
@export var swivel_enabled: bool = false
## Head yaw either side of forward that turns nothing, degrees.
@export_range(0.0, 90.0) var swivel_dead_zone_deg: float = 30.0
## Stick yaw per degree past the dead zone.
@export_range(0.0, 1.0) var swivel_gain_per_deg: float = 0.03
## Largest stick yaw the swivel may give.
@export_range(0.0, 1.0) var swivel_max_input: float = 1.0
## How fast forward follows the body, degrees per second; 0 never follows.
@export_range(0.0, 180.0) var swivel_follow_deg_per_s: float = 5.0

## Allowed range of each swivel number, inclusive: [minimum, maximum]. Keep in
## step with the `@export_range` hints above, which the custom file checks.
const SWIVEL_RANGES: Dictionary[String, Array] = {
	"swivel_dead_zone_deg": [0.0, 90.0],
	"swivel_gain_per_deg": [0.0, 1.0],
	"swivel_max_input": [0.0, 1.0],
	"swivel_follow_deg_per_s": [0.0, 180.0],
}


## Empty when the preset's values can be used; otherwise names the bad field.
## Only fields with a rule of their own are checked; the rest are typed.
func validation_error() -> String:
	if not is_finite(break_reminder_minutes) or break_reminder_minutes < 0.0:
		return "break_reminder_minutes is %s, must be a number of at least 0" \
			% str(break_reminder_minutes)
	for field: String in SWIVEL_RANGES:
		var value: float = get(field)
		var low: float = SWIVEL_RANGES[field][0]
		var high: float = SWIVEL_RANGES[field][1]
		if not is_finite(value) or value < low or value > high:
			return "%s is %s, must be within %s..%s" % [field, str(value), low, high]
	return ""


## True when any setting lets the view turn smoothly rather than in snaps.
## Preset 1 must answer false (CMF-3).
func has_smooth_rotation() -> bool:
	return yaw_mode == YawMode.SMOOTH or pitch_mode == PitchMode.SMOOTH \
		or roll_mode != RollMode.OFF_AUTO_LEVEL or hit_spin \
		or (levels_roll() and auto_level_snap_threshold_deg == NO_LIMIT)


## True when the view levels itself once the player stops rolling. A fully
## manual roll never levels, whatever `auto_level` says (CMF-2).
func levels_roll() -> bool:
	return auto_level and roll_mode != RollMode.FULLY_MANUAL


## True when no comfort intervention of any kind is on (CMF-2).
func has_no_intervention() -> bool:
	return yaw_mode == YawMode.SMOOTH and pitch_mode == PitchMode.SMOOTH \
		and yaw_rate_cap_deg_per_s == NO_LIMIT and pitch_rate_cap_deg_per_s == NO_LIMIT \
		and pitch_limit_deg == NO_LIMIT and roll_mode == RollMode.FULLY_MANUAL \
		and not auto_level and vignette_strength == 0.0 \
		and vignette_trigger == VignetteTrigger.NEVER and not acceleration_softening
