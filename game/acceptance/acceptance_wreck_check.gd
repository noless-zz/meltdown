class_name AcceptanceWreckCheck
extends RefCounted

## The `ship_destroyed_inert` acceptance check (#601, RUN-7): re-flies a replay
## tick by tick and passes only if ship 0 is destroyed on it, exactly one
## SHIP_DESTROYED event says so, and from then on the ship fires nothing and,
## from the tick after, does not move, although the replay keeps sending
## thrust and fire. The final state alone cannot show either, so like
## `no_hidden_hits` this flies the replay again; the hash check pins the
## flight itself. Kept apart from `AcceptanceStateChecks` for that file's size.

## The replay must go on sending input for at least this many ticks after the
## ship is destroyed, so the check has something to refuse: one second.
const MIN_TICKS_AFTER: int = 60


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
	var destroyed_tick: int = -1
	var events: int = 0
	var inputs_after: int = 0
	var rest: Vector3 = Vector3.ZERO
	var known: Dictionary[Projectile, bool] = {}
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		var tick: int = sim.tick
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_DESTROYED and event.ship == 0:
				events += 1
				destroyed_tick = tick
		var fired: bool = false
		for projectile: Projectile in sim.projectiles:
			if not known.has(projectile):
				known[projectile] = true
				fired = fired or (not projectile.is_robot_owned() and projectile.owner_index == 0)
		if destroyed_tick < 0 or tick == destroyed_tick:
			continue
		if fired:
			return [AcceptanceReport.RESULT_FAIL, "tick %d: the destroyed ship fired" % tick]
		if _sends_input(inputs[0]):
			inputs_after += 1
		if tick == destroyed_tick + 1:
			rest = sim.ships[0].position
		elif sim.ships[0].position != rest:
			return [AcceptanceReport.RESULT_FAIL, "tick %d: the destroyed ship moved" % tick]
	measurements["destroyed_tick"] = destroyed_tick
	measurements["destroyed_events"] = events
	measurements["inputs_after_destroyed"] = inputs_after
	if destroyed_tick < 0:
		return [AcceptanceReport.RESULT_FAIL, "the ship was never destroyed (hull %.1f)" % sim.ships[0].hull]
	if events != 1:
		return [AcceptanceReport.RESULT_FAIL, "%d SHIP_DESTROYED events, expected 1" % events]
	if inputs_after < MIN_TICKS_AFTER:
		return [AcceptanceReport.RESULT_FAIL, "only %d ticks of thrust or fire after the ship was destroyed, expected %d" % [
			inputs_after, MIN_TICKS_AFTER]]
	return [AcceptanceReport.RESULT_PASS, "destroyed on tick %d; %d ticks of thrust and fire after it moved and fired nothing" % [
		destroyed_tick, inputs_after]]


static func _sends_input(input: ShipInput) -> bool:
	return input.fire_primary or input.thrust_q != Vector3i.ZERO or input.afterburner
