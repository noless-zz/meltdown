class_name AcceptanceBoostCheck
extends RefCounted

## The `afterburner` acceptance check (#775, FLT-2, umbrella #153): re-flies a
## replay tick by tick and records ship 0's top speed before the afterburner is
## first used and while it boosts. It passes when the boost clearly beats
## normal flight (by at least half the gap between `max_speed` and
## `afterburner_max_speed`), never runs past `afterburner_max_speed`, and the
## speed drops back under `max_speed` within SETTLE_LIMIT_TICKS of every
## release. The limits come from the ship file's tuning handed in, never from
## constants here, so a tuning change moves them. The final state cannot show
## any of this, so like `AcceptanceWreckCheck` this flies the replay again; the
## hash check pins the flight itself.

## Speeds may run this far over a limit (1 %) before the check calls it
## exceeded: the cap is applied in floats, and a limit hit exactly must pass.
const SPEED_TOLERANCE: float = 1.01
## Seconds, as ticks, within which the speed must be back under the normal cap.
const SETTLE_LIMIT_TICKS: int = 180
## The boosted top speed must reach `max_speed` plus this share of the gap to
## `afterburner_max_speed`.
const GAP_SHARE: float = 0.5


## The speed the boost must reach under `tuning`.
static func threshold(tuning: ShipTuning) -> float:
	return tuning.max_speed + (tuning.afterburner_max_speed - tuning.max_speed) * GAP_SHARE


## [result, message] for `replay` against the ship file's `tuning`, adding its
## measurements.
static func run(replay: Replay, tuning: ShipTuning, measurements: Dictionary) -> Array:
	# `Replay.run` with no frames is the sim set up from the header, before its
	# first tick; the frames are put back at once and stepped here.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	if sim.ships.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay has no ship"]
	var needed: float = threshold(tuning)
	var ceiling: float = tuning.afterburner_max_speed * SPEED_TOLERANCE
	var normal: float = tuning.max_speed * SPEED_TOLERANCE
	var plain_top: float = 0.0
	var boosted_top: float = 0.0
	var boosted_once: bool = false
	var was_boosting: bool = false
	# Tick of the last release still above the normal cap, or -1.
	var released_tick: int = -1
	var settle_ticks: int = 0
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		var ship: ShipState = sim.ships[0]
		var speed: float = ship.velocity.length()
		var boosting: bool = ship.afterburner_active
		if speed > ceiling:
			return [AcceptanceReport.RESULT_FAIL, "tick %d: speed %.2f m/s, over the afterburner's %.2f" % [
				sim.tick, speed, tuning.afterburner_max_speed]]
		if boosting:
			boosted_once = true
			boosted_top = maxf(boosted_top, speed)
			released_tick = -1
		elif not boosted_once:
			plain_top = maxf(plain_top, speed)
		if was_boosting and not boosting:
			released_tick = sim.tick
		if released_tick >= 0 and speed <= normal:
			settle_ticks = maxi(settle_ticks, sim.tick - released_tick)
			released_tick = -1
		if released_tick >= 0 and sim.tick - released_tick > SETTLE_LIMIT_TICKS:
			return [AcceptanceReport.RESULT_FAIL, "speed still %.2f m/s %.1f s after the afterburner was let go" % [
				speed, SETTLE_LIMIT_TICKS * ShipState.TICK_DT]]
		was_boosting = boosting
	measurements["plain_top_speed"] = snappedf(plain_top, 0.01)
	measurements["boosted_top_speed"] = snappedf(boosted_top, 0.01)
	measurements["boost_threshold"] = snappedf(needed, 0.01)
	measurements["energy_end"] = snappedf(sim.ships[0].energy, 0.01)
	measurements["settle_seconds"] = snappedf(settle_ticks * ShipState.TICK_DT, 0.01)
	if boosted_top < needed:
		return [AcceptanceReport.RESULT_FAIL, "boosted top speed %.2f m/s, needs at least %.2f" % [boosted_top, needed]]
	if was_boosting or released_tick >= 0:
		return [AcceptanceReport.RESULT_FAIL, "the replay ends before the speed is back under %.2f m/s" % tuning.max_speed]
	return [AcceptanceReport.RESULT_PASS, "boosted top speed %.2f m/s (normal %.2f), back under %.2f m/s in %.2f s" % [
		boosted_top, plain_top, tuning.max_speed, settle_ticks * ShipState.TICK_DT]]
