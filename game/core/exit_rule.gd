class_name ExitRule
extends RefCounted

## The level's exit and how a run ends (RUN-3, RUN-7). The exit is the entrance:
## a sphere around each ship's start position, `ReactorState.exit_radius_mm` wide.
## It does nothing until the reactor dies. While the meltdown countdown runs, a
## ship whose centre ends a tick inside it escapes; when the countdown reaches
## zero, every ship still in the level is lost. In any level, with or without a
## reactor, the run is lost once every ship is destroyed (#601).
##
## Kept out of `Sim`, which is at its size limit. Stateless: the escape is held by
## `ShipState.escaped` and the loss by the ship's hull, so the rule needs no
## state of its own to hash or replay (ARC-1, ARC-2).

enum Outcome {
	## The reactor lives, or the meltdown runs with a ship still in the level.
	RUNNING,
	## At least one ship escaped and none is left flying in the level.
	ESCAPED,
	## No ship escaped and none is left flying: every ship was destroyed, at
	## any time and in any level, or the countdown ran out.
	LOST,
}

## Called once at the end of `Sim.step`, after everything has moved, so "ends a
## tick inside" means what the ship's final position for the tick says.
## Appends SHIP_ESCAPED and SHIP_LOST_IN_MELTDOWN events in ship order, then a
## SHIP_DESTROYED for each ship that `live_before` (from `live_ships` at the
## start of the tick) says still had hull and has none now.
static func apply(sim: Sim, events: Array[SimEvent], live_before: Array[bool] = []) -> void:
	_apply_exit(sim, events)
	for i: int in mini(live_before.size(), sim.ships.size()):
		if live_before[i] and sim.ships[i].is_destroyed():
			events.append(SimEvent.new(SimEvent.Kind.SHIP_DESTROYED, i, 0.0, sim.ships[i].position))


## Per ship, whether its hull is above zero, for `apply` to compare with at the
## end of the tick. An escaped ship keeps its hull, so it never reports.
static func live_ships(sim: Sim) -> Array[bool]:
	var live: Array[bool] = []
	for ship: ShipState in sim.ships:
		live.append(not ship.is_destroyed())
	return live


static func _apply_exit(sim: Sim, events: Array[SimEvent]) -> void:
	var reactor: ReactorState = sim.reactor
	if reactor == null or not reactor.destroyed:
		return
	var radius: float = reactor.exit_radius()
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.escaped or ship.is_destroyed():
			continue
		if reactor.meltdown_ticks_left <= 0:
			ship.hull = 0.0
			events.append(SimEvent.new(SimEvent.Kind.SHIP_LOST_IN_MELTDOWN, i))
		elif ship.position.distance_squared_to(sim.start_positions[i]) <= radius * radius:
			ship.escaped = true
			# Parked where it left, so nothing reading velocity sees it drift.
			ship.velocity = Vector3.ZERO
			events.append(SimEvent.new(SimEvent.Kind.SHIP_ESCAPED, i, 0.0, ship.position))


## How the run stands; see `Outcome`. A ship escapes only during the meltdown,
## so before it the only end is every ship destroyed. A sim with no ships is
## running: nothing was lost.
static func outcome(sim: Sim) -> Outcome:
	if sim.ships.is_empty():
		return Outcome.RUNNING
	var any_escaped: bool = false
	for ship: ShipState in sim.ships:
		if ship.escaped:
			any_escaped = true
		elif not ship.is_destroyed():
			return Outcome.RUNNING
	return Outcome.ESCAPED if any_escaped else Outcome.LOST


## The outcome and every ship's escape, for `Sim.state_hash` to add only when
## the level has a reactor.
static func state_hash(sim: Sim) -> int:
	var parts: Array[int] = [hash("exit"), outcome(sim)]
	for ship: ShipState in sim.ships:
		parts.append(1 if ship.escaped else 0)
	return hash(parts)
