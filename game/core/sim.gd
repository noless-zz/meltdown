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


func _init(p_run_seed: int = 0, ship_count: int = 1) -> void:
	run_seed = p_run_seed
	for i: int in ship_count:
		ships.append(ShipState.new())


## Advances every ship by one tick. `inputs[i]` drives `ships[i]`.
## Returns false and changes nothing if there is not exactly one input per
## ship: guessing a missing input would silently fork the simulation.
func step(inputs: Array[ShipInput]) -> bool:
	if inputs.size() != ships.size():
		return false
	for i: int in ships.size():
		ships[i].step(inputs[i].thrust(), inputs[i].turn())
	tick += 1
	return true


## Hash of the whole simulation state.
func state_hash() -> int:
	var parts: Array[int] = [run_seed, tick]
	for ship: ShipState in ships:
		parts.append(ship.state_hash())
	return hash(parts)
