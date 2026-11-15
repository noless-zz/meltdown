class_name Sim
extends RefCounted

## The authoritative simulation: owns every ship and advances them together,
## one fixed tick at a time, from one input per ship (MP-2).
##
## No nodes, devices, clock or unseeded randomness (ARC-1). Identical seed and
## inputs give an identical `state_hash()` (ARC-2), which is what replay tests
## and, later, network desync checks compare.

## Seed of this run. Nothing draws random numbers yet; it is part of the state
## so that replays recorded now stay valid once the generator and robots do.
var run_seed: int = 0
## Number of ticks simulated so far.
var tick: int = 0
var ships: Array[ShipState] = []
## Walls the ships fly inside, or null for open space. Not part of the hash:
## it is fixed for the run, like the seed's mine will be.
var bounds: BoxBounds = null
## What happened on the last tick only, in ship order and, per ship, in the
## order of `SimEvent.Kind`. Derived output for haptics, shake and sound
## (PLT-6): not part of the hash, replaced by every call to `step`.
var last_events: Array[SimEvent] = []


func _init(p_run_seed: int = 0, ship_count: int = 1, p_bounds: BoxBounds = null) -> void:
	run_seed = p_run_seed
	bounds = p_bounds
	for i: int in ship_count:
		ships.append(ShipState.new())


## Advances every ship by one tick. `inputs[i]` drives `ships[i]`.
## Returns false and changes no state if there is not exactly one input per
## ship: guessing a missing input would silently fork the simulation. A refused
## step still empties `last_events`, because no tick happened.
func step(inputs: Array[ShipInput]) -> bool:
	last_events = []
	if inputs.size() != ships.size():
		return false
	for i: int in ships.size():
		var ship: ShipState = ships[i]
		var was_active: bool = ship.afterburner_active
		var was_locked: bool = ship.afterburner_locked
		ship.step(inputs[i].thrust(), inputs[i].turn(), inputs[i].afterburner)
		if ship.afterburner_active and not was_active:
			last_events.append(SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, i))
		elif was_active and not ship.afterburner_active:
			last_events.append(SimEvent.new(SimEvent.Kind.AFTERBURNER_STOPPED, i))
		if ship.afterburner_locked and not was_locked:
			last_events.append(SimEvent.new(SimEvent.Kind.ENERGY_DEPLETED, i))
		if bounds != null:
			var impact: Vector3 = bounds.contain_impact(ship)
			if impact != Vector3.ZERO:
				last_events.append(SimEvent.new(
					SimEvent.Kind.WALL_IMPACT, i, impact.length(), -impact.normalized()))
	tick += 1
	return true


## Hash of the whole simulation state.
func state_hash() -> int:
	var parts: Array[int] = [run_seed, tick]
	for ship: ShipState in ships:
		parts.append(ship.state_hash())
	return hash(parts)
