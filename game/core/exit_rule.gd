class_name ExitRule
extends RefCounted

## The level's exit and how a run ends (RUN-3, RUN-7). The exit is the entrance:
## a sphere around each ship's start position, `ReactorState.exit_radius_mm` wide.
## It does nothing until the reactor dies. While the meltdown countdown runs, a
## ship whose centre ends a tick inside it escapes; when the countdown reaches
## zero, every ship still in the level is lost.
##
## Kept out of `Sim`, which is at its size limit. Stateless: the escape is held by
## `ShipState.escaped` and the loss by the ship's hull, so the rule needs no
## state of its own to hash or replay (ARC-1, ARC-2).

enum Outcome {
	## The reactor lives, or the meltdown runs with a ship still in the level.
	RUNNING,
	## At least one ship escaped and none is left flying in the level.
	ESCAPED,
	## No ship escaped and none is left flying: the countdown ran out, or every
	## ship was destroyed during the meltdown.
	LOST,
}

## Exit radius for a level file without `exit_radius`: the ship is 1 m across
## the centre, and the start must be held with 1 m to spare (`LevelDef`), so
## this is a sphere a pilot cannot miss in a tunnel mouth.
const DEFAULT_RADIUS_M: float = 4.0


## Called once at the end of `Sim.step`, after everything has moved, so "ends a
## tick inside" means what the ship's final position for the tick says.
## Appends SHIP_ESCAPED and SHIP_LOST_IN_MELTDOWN events in ship order.
static func apply(sim: Sim, events: Array[SimEvent]) -> void:
	var reactor: ReactorState = sim.reactor
	if reactor == null or not reactor.destroyed:
		return
	var radius: float = reactor.exit_radius()
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.escaped or ship.hull <= 0.0:
			continue
		if reactor.meltdown_ticks_left <= 0:
			ship.hull = 0.0
			events.append(SimEvent.new(SimEvent.Kind.SHIP_LOST_IN_MELTDOWN, i))
		elif ship.position.distance_squared_to(sim.start_positions[i]) <= radius * radius:
			ship.escaped = true
			# Parked where it left, so nothing reading velocity sees it drift.
			ship.velocity = Vector3.ZERO
			events.append(SimEvent.new(SimEvent.Kind.SHIP_ESCAPED, i, 0.0, ship.position))


## How the run stands; see `Outcome`.
static func outcome(sim: Sim) -> Outcome:
	if sim.reactor == null or not sim.reactor.destroyed:
		return Outcome.RUNNING
	var any_escaped: bool = false
	for ship: ShipState in sim.ships:
		if ship.escaped:
			any_escaped = true
		elif ship.hull > 0.0:
			return Outcome.RUNNING
	return Outcome.ESCAPED if any_escaped else Outcome.LOST


## The outcome and every ship's escape, for `Sim.state_hash` to add only when
## the level has a reactor.
static func state_hash(sim: Sim) -> int:
	var parts: Array[int] = [hash("exit"), outcome(sim)]
	for ship: ShipState in sim.ships:
		parts.append(1 if ship.escaped else 0)
	return hash(parts)
