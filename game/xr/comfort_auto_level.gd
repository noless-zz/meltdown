class_name ComfortAutoLevel
extends RefCounted

## Works out the roll that brings a banked ship back to level for comfort
## presets with auto-level on (CMF-1, CMF-3, CMF-5). The roll is an ordinary
## turn input, so the ship itself levels and the view only ever follows the
## ship's simulated motion (CMF-8, ARC-3).
##
## Bank is the angle about the nose between the ship's up axis and the up
## direction a level ship with the same nose would have. With the nose close
## to vertical that direction is undefined (every bank looks the same), so no
## correction is made there rather than one that could flip the ship.

## Nose elevation in degrees beyond which bank is treated as undefined.
const MAX_ELEVATION_DEG: float = 80.0


## True when `orientation`'s bank can be measured.
static func bank_defined(orientation: Basis) -> bool:
	return absf(ComfortInputFilter.nose_elevation(orientation)) \
		<= deg_to_rad(MAX_ELEVATION_DEG)


## Bank in radians about the nose; positive when a positive roll rate would
## make it larger. Only meaningful when `bank_defined` is true.
##
## The right (x) and up (y) axes both lie across the nose, and their heights
## are cos(elevation) times the sine and cosine of the bank, so their ratio
## gives the bank whatever the nose elevation.
static func bank(orientation: Basis) -> float:
	return atan2(orientation.x.normalized().y, orientation.y.normalized().y)


## Roll rate in milliradians per second, as in `ShipInput.turn_q.z`, that
## levels a ship whose orientation after this tick's pitch and yaw is
## `turned`. Rolling is the last turn of a tick and does not move the nose,
## so the roll can be worked out on that orientation.
##
## The rate is truncated towards zero, so it never rolls past level. A snap
## (preset 1) levels in this one tick, whatever the smooth rate cap, and only
## once the bank exceeds the threshold; a smooth correction never exceeds
## `auto_level_rate_deg_per_s`.
static func roll_q(preset: ComfortPreset, turned: Basis) -> int:
	if not bank_defined(turned):
		return 0
	var current: float = bank(turned)
	var level_in_one_tick: int = int(-current / ShipState.TICK_DT * ShipInput.SCALE)
	if preset.auto_level_snap_threshold_deg != ComfortPreset.NO_LIMIT:
		if absf(current) <= deg_to_rad(preset.auto_level_snap_threshold_deg):
			return 0
		return level_in_one_tick
	var cap: int = ComfortInputFilter.cap_q(preset.auto_level_rate_deg_per_s)
	if cap < 0:
		return level_in_one_tick
	return clampi(level_in_one_tick, -cap, cap)
