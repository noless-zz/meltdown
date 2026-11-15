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
## Where each ship returns on a `reset_to_start` input. Recorded when the ship
## is created and again just before the first tick, so a caller that places a
## ship before flying (for example inside the test tunnel) is honoured. Fixed
## for the run like `bounds`, so not part of the hash.
var start_positions: Array[Vector3] = []
var start_orientations: Array[Basis] = []


func _init(p_run_seed: int = 0, ship_count: int = 1, p_bounds: BoxBounds = null) -> void:
	run_seed = p_run_seed
	bounds = p_bounds
	for i: int in ship_count:
		ships.append(ShipState.new())
	_record_start_poses()


## Advances every ship by one tick. `inputs[i]` drives `ships[i]`.
## Returns false and changes no state if there is not exactly one input per
## ship: guessing a missing input would silently fork the simulation. A refused
## step still empties `last_events`, because no tick happened.
func step(inputs: Array[ShipInput]) -> bool:
	last_events = []
	if inputs.size() != ships.size():
		return false
	if tick == 0:
		_record_start_poses()
	for i: int in ships.size():
		var ship: ShipState = ships[i]
		if inputs[i].reset_to_start:
			_reset_to_start(i)
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


## Sets where ship `index` returns on a reset. Before the first tick it also
## moves the ship there, so the run starts where it would reset to.
func set_start_pose(index: int, position: Vector3, orientation: Basis) -> void:
	start_positions[index] = position
	start_orientations[index] = orientation
	if tick == 0:
		ships[index].position = position
		ships[index].orientation = orientation


func _record_start_poses() -> void:
	start_positions.clear()
	start_orientations.clear()
	for ship: ShipState in ships:
		start_positions.append(ship.position)
		start_orientations.append(ship.orientation)


## Pose and velocity only: hull, shield and energy are kept, so a reset is a
## way home and not a free repair.
func _reset_to_start(index: int) -> void:
	var ship: ShipState = ships[index]
	ship.position = start_positions[index]
	ship.orientation = start_orientations[index]
	ship.velocity = Vector3.ZERO


## Hash of the whole simulation state.
func state_hash() -> int:
	var parts: Array[int] = [run_seed, tick]
	for ship: ShipState in ships:
		parts.append(ship.state_hash())
	return hash(parts)
