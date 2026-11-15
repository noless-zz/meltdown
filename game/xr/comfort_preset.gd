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
enum CockpitFrame { SOLID_SMALL_WINDOWS, SOLID_WIDE_CANOPY, OPEN_CANOPY, MINIMAL_GLASS }

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

@export_group("Vignette")
## 0 is no vignette, 1 the narrowest field of view the vignette allows.
@export_range(0.0, 1.0) var vignette_strength: float = 0.0
@export var vignette_trigger: VignetteTrigger = VignetteTrigger.NEVER

@export_group("Cockpit")
@export var cockpit_frame: CockpitFrame = CockpitFrame.MINIMAL_GLASS

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


## True when any setting lets the view turn smoothly rather than in snaps.
## Preset 1 must answer false (CMF-3).
func has_smooth_rotation() -> bool:
	return yaw_mode == YawMode.SMOOTH or pitch_mode == PitchMode.SMOOTH \
		or roll_mode != RollMode.OFF_AUTO_LEVEL or hit_spin


## True when no comfort intervention of any kind is on (CMF-2).
func has_no_intervention() -> bool:
	return yaw_mode == YawMode.SMOOTH and pitch_mode == PitchMode.SMOOTH \
		and yaw_rate_cap_deg_per_s == NO_LIMIT and pitch_rate_cap_deg_per_s == NO_LIMIT \
		and pitch_limit_deg == NO_LIMIT and roll_mode == RollMode.FULLY_MANUAL \
		and not auto_level and vignette_strength == 0.0 \
		and vignette_trigger == VignetteTrigger.NEVER and not acceleration_softening
