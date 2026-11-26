class_name EngineSoundMix
extends RefCounted

## The levels of the pilot's engine (#1398, AUD-1), kept apart from the players
## so they can be tested without an audio device.
##
## The engine has a `gain` that fades in while the ship flies and out on end
## screens and at the base, and a `drive` from 0 to 1 that the thrust layer's
## volume and pitch follow: mostly how hard the ship is pushing, partly how
## fast it is going, so coasting at speed still sounds like movement. The
## drive is smoothed so a single bumpy tick does not make the layer jump.
##
## Thrust is read back from two consecutive ship copies (MP-2): the change in
## velocity over one tick, with the tick's damping added back, is what the
## engine pushed. It is never read from the input, which the view does not see.

## The table this mix follows.
var table: EngineSoundTable = null
## The whole engine's level, 0 silent to 1 full.
var gain: float = 0.0
## The thrust layer's smoothed drive, 0 to 1.
var drive: float = 0.0

## The volume of a silent layer, in dB; a player is never set below it.
const SILENT_DB: float = -80.0


func _init(engine_table: EngineSoundTable) -> void:
	table = engine_table


## Moves the mix `seconds` on: towards full while `flying`, towards silence
## otherwise; the drive towards what `thrust` and `speed` (both 0 to 1) give.
func advance(flying: bool, thrust: float, speed: float, seconds: float) -> void:
	var step: float = maxf(0.0, seconds)
	gain = move_toward(gain, 1.0 if flying else 0.0, step / table.fade_seconds)
	var target: float = drive_for(thrust, speed)
	drive = lerpf(drive, target, minf(1.0, step / table.smoothing_seconds))
	if absf(drive - target) < 0.0005:
		drive = target


## The drive for `thrust` and `speed`, each 0 to 1, weighted by the table.
func drive_for(thrust: float, speed: float) -> float:
	var weight: float = table.thrust_weight
	return clampf(weight * clampf(thrust, 0.0, 1.0) + (1.0 - weight) * clampf(speed, 0.0, 1.0), 0.0, 1.0)


## Whether any of the engine is heard.
func sounding() -> bool:
	return gain > 0.0


## Whether the thrust layer is heard: the engine is on and the ship is
## pushing or moving. A ship at rest hears only the idle.
func thrust_sounding() -> bool:
	return sounding() and drive > 0.001


## The idle's volume in dB at the current gain.
func idle_db() -> float:
	return maxf(table.idle_db + linear_to_db(gain), SILENT_DB)


## The thrust layer's volume in dB at the current drive and gain.
func thrust_db() -> float:
	return maxf(lerpf(table.thrust_min_db, table.thrust_max_db, drive) + linear_to_db(gain), SILENT_DB)


## The thrust layer's pitch at the current drive.
func thrust_pitch() -> float:
	return lerpf(table.thrust_pitch_min, table.thrust_pitch_max, drive)


## How hard `after` pushed on the tick from `before`, 0 to 1 of its
## acceleration (two session copies one tick apart). Full on the afterburner;
## nothing for a wrecked ship or without a tick before.
static func thrust_of(before: ShipState, after: ShipState) -> float:
	if after == null or after.is_destroyed():
		return 0.0
	if after.afterburner_active:
		return 1.0
	if before == null or after.acceleration <= 0.0:
		return 0.0
	# `ShipState.step` adds the push, then takes off damping; undo the damping.
	var kept: float = 1.0 - minf(after.damping * ShipState.TICK_DT, 1.0)
	if kept <= 0.0:
		return 0.0
	var pushed: Vector3 = (after.velocity / kept - before.velocity) / ShipState.TICK_DT
	return clampf(pushed.length() / after.acceleration, 0.0, 1.0)


## How fast `ship` goes, 0 to 1 of its afterburner top speed, so a boost is
## heard above cruising.
static func speed_of(ship: ShipState) -> float:
	if ship == null:
		return 0.0
	return clampf(ship.velocity.length() / maxf(ship.afterburner_max_speed, 0.001), 0.0, 1.0)
