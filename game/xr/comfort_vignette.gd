class_name ComfortVignette
extends RefCounted

## The vignette row of the comfort table (CMF-1): how strongly the edge of
## view is darkened for one player, from that player's preset and the ship's
## motion as shown to them.
##
## Only reads the motion; nothing here writes simulation state, so a preset's
## vignette changes what the player sees and never how the ship flies
## (CMF-6, ARC-3). Preset 4 has trigger `NEVER` and strength 0, so it always
## answers 0 (CMF-2).
##
## Each trigger ramps from 0 at a start threshold to the preset's full
## strength at a full threshold. The ramp, rather than an on/off switch, keeps
## the vignette from popping in and out when the motion hovers at a threshold.

## Turn rate below which turning counts as standing still, radians per second.
## Keeps tracking jitter and residual drift from darkening the view.
const ROTATION_START_RAD_PER_S: float = deg_to_rad(5.0)
## Turn rate at which `ROTATION` and `ALL_MOTION` reach full strength,
## radians per second.
const ROTATION_FULL_RAD_PER_S: float = deg_to_rad(90.0)
## Turn rate at which a turn counts as fast, radians per second. Below it
## `FAST_ROTATION` gives 0.
const FAST_ROTATION_START_RAD_PER_S: float = deg_to_rad(90.0)
## Turn rate at which `FAST_ROTATION` reaches full strength, radians per second.
const FAST_ROTATION_FULL_RAD_PER_S: float = deg_to_rad(180.0)
## Speed below which the ship counts as hovering, metres per second.
const MOTION_START_M_PER_S: float = 0.5
## Speed at which `ALL_MOTION` reaches full strength from travel alone,
## metres per second; the ship's normal top speed (FLT-1).
const MOTION_FULL_M_PER_S: float = 20.0


## Vignette strength in 0..1 for `preset` while the ship turns at
## `angular_speed` (radians per second) and travels at `linear_speed`
## (metres per second). Never exceeds `preset.vignette_strength`.
static func strength(preset: ComfortPreset, angular_speed: float, linear_speed: float) -> float:
	if preset == null:
		return 0.0
	var amount: float = 0.0
	match preset.vignette_trigger:
		ComfortPreset.VignetteTrigger.FAST_ROTATION:
			amount = ramp(absf(angular_speed), FAST_ROTATION_START_RAD_PER_S, FAST_ROTATION_FULL_RAD_PER_S)
		ComfortPreset.VignetteTrigger.ROTATION:
			amount = ramp(absf(angular_speed), ROTATION_START_RAD_PER_S, ROTATION_FULL_RAD_PER_S)
		ComfortPreset.VignetteTrigger.ALL_MOTION:
			amount = maxf(
				ramp(absf(angular_speed), ROTATION_START_RAD_PER_S, ROTATION_FULL_RAD_PER_S),
				ramp(absf(linear_speed), MOTION_START_M_PER_S, MOTION_FULL_M_PER_S))
		_:
			amount = 0.0
	return clampf(preset.vignette_strength, 0.0, 1.0) * amount


## 0 at or below `start`, 1 at or above `full`, linear in between.
static func ramp(value: float, start: float, full: float) -> float:
	if value <= start:
		return 0.0
	if value >= full:
		return 1.0
	return (value - start) / (full - start)
