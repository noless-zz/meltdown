class_name AcceptanceWallCheck
extends RefCounted

## The `wall_bounced` acceptance check (#686, FLT-3): re-flies a replay tick by
## tick and passes only if ship 0 hit a wall, the hits cost it hull or shield
## (minor damage; the shield takes every hit first, CMB-2, so a couple of
## boost-speed hits leave the hull whole), and it was still moving on the tick of every wall contact
## and on the two ticks after it: walls bounce the ship back, they never stop
## it dead. The final state cannot show either, so like `no_hidden_hits` this
## flies the replay again; the hash check pins the flight itself. Kept apart
## from `AcceptanceStateChecks` for that file's size.

## Ticks after a wall contact on which the ship must still be moving.
const TICKS_AFTER_CONTACT: int = 2
## Below this speed, in metres per second, the ship counts as stopped. A
## bounce keeps at least `ShipState.MIN_WALL_RESTITUTION` of the speed into
## the wall, so a real bounce is far above it.
const STOPPED_SPEED: float = 0.01


## [result, message] for `replay`, adding its measurements.
static func run(replay: Replay, measurements: Dictionary) -> Array:
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
	var ship: ShipState = sim.ships[0]
	var start_hull: float = ship.hull
	var start_shield: float = ship.shield
	var min_hull: float = start_hull
	var min_shield: float = start_shield
	var contacts: int = 0
	var fastest: float = 0.0
	var slowest_after: float = INF
	# Ticks still to watch after the latest contact; -1 when none is pending.
	var watch_left: int = -1
	var watch_from: int = -1
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		var tick: int = sim.tick
		sim.step(inputs)
		min_hull = minf(min_hull, ship.hull)
		min_shield = minf(min_shield, ship.shield)
		var hit: float = _impact(sim.last_events)
		if hit > 0.0:
			contacts += 1
			fastest = maxf(fastest, hit)
			watch_left = TICKS_AFTER_CONTACT
			watch_from = tick
		elif watch_left > 0:
			watch_left -= 1
		else:
			watch_left = -1
		# A held reset puts the ship at rest at its start on purpose (#81).
		if watch_left >= 0 and not inputs[0].reset_to_start:
			var speed: float = ship.velocity.length()
			slowest_after = minf(slowest_after, speed)
			if speed < STOPPED_SPEED:
				return [AcceptanceReport.RESULT_FAIL, "tick %d: the ship stopped (%.3f m/s) within %d ticks of a wall contact on tick %d" % [
					tick, speed, TICKS_AFTER_CONTACT, watch_from]]
	measurements["wall_contacts"] = contacts
	measurements["fastest_impact"] = fastest
	measurements["slowest_after_contact"] = slowest_after if contacts > 0 else 0.0
	measurements["start_hull"] = start_hull
	measurements["min_hull"] = min_hull
	measurements["start_shield"] = start_shield
	measurements["min_shield"] = min_shield
	if contacts == 0:
		return [AcceptanceReport.RESULT_FAIL, "the ship never touched a wall"]
	if min_hull >= start_hull and min_shield >= start_shield:
		return [AcceptanceReport.RESULT_FAIL, "%d wall contacts, fastest %.1f m/s, cost neither hull nor shield" % [
			contacts, fastest]]
	return [AcceptanceReport.RESULT_PASS, "%d wall contacts, fastest %.1f m/s; hull %.1f to %.1f, shield %.1f to %.1f; never stopped" % [
		contacts, fastest, start_hull, min_hull, start_shield, min_shield]]


## The fastest WALL_IMPACT of ship 0 among `events`, or 0.0 for none.
static func _impact(events: Array[SimEvent]) -> float:
	var fastest: float = 0.0
	for event: SimEvent in events:
		if event.kind == SimEvent.Kind.WALL_IMPACT and event.ship == 0:
			fastest = maxf(fastest, event.magnitude)
	return fastest
