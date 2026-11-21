class_name FireBurnCheck
extends RefCounted

## The `fire_burned` acceptance check (#517, RUN-4, CMB-2, DEV-6, decision
## record 0005): on at least one tick of a step's replay the ship's centre was
## inside a burning entry and its shield or hull went down on that tick. An
## escape that only flew past fire, or a change that stops fire burning, fails.
##
## The runner only hands checks the state a replay ended in, and a burn leaves
## no trace there, so the check flies the session's own recording again, one
## tick at a time, from the level it recorded before the first tick. The
## recording ends on the same hash as the live run or the check fails, so it
## cannot pass on a different flight. The seed picker (`m3_seed_pick.gd`) uses
## `burnt_this_tick` too, so both judge a burn the same way.


## Whether the first ship of `sim` was burnt on the tick just flown: its shield
## or hull is below what it was before the tick and its centre is inside a
## burning entry, where `MeltdownFire.burn` found it.
static func burnt_this_tick(sim: Sim, shield_before: float, hull_before: float) -> bool:
	if sim.debris == null or sim.ships.is_empty():
		return false
	var ship: ShipState = sim.ships[0]
	if ship.shield >= shield_before and ship.hull >= hull_before:
		return false
	for index: int in sim.debris.size():
		if sim.debris.is_burning(index) and MeltdownFire.contains(sim.debris, index, ship.position):
			return true
	return false


## [result, message] for the check on the session a step flew, adding the
## number of fire entries and of ticks the ship was burnt on. Failures name
## `step_id`, since a suite may fly several generated seeds.
static func run(step_id: String, session: LocalSession, measurements: Dictionary) -> Array:
	var source: ReplayInputSource = ReplayInputSource.new(session.replay)
	var again: LocalSession = source.new_session()
	var sim: Sim = again.sim
	var burnt: int = 0
	while sim.tick < source.tick_count():
		var shield: float = sim.ships[0].shield
		var hull: float = sim.ships[0].hull
		if again.advance(ShipState.TICK_DT) == 0:
			break
		if burnt_this_tick(sim, shield, hull):
			burnt += 1
	var fires: int = 0
	if sim.debris != null:
		for index: int in sim.debris.size():
			if sim.debris.is_fire(index):
				fires += 1
	measurements["fires"] = fires
	measurements["burnt_ticks"] = burnt
	if sim.state_hash() != session.sim.state_hash():
		return [AcceptanceReport.RESULT_FAIL, "step %s: flying the recording again ended on hash %d, not %d" % [
			step_id, sim.state_hash(), session.sim.state_hash()]]
	if burnt == 0:
		return [AcceptanceReport.RESULT_FAIL, "step %s: the ship was never burnt by any of %d fires" % [
			step_id, fires]]
	return [AcceptanceReport.RESULT_PASS, "burnt on %d ticks by %d fires" % [burnt, fires]]
