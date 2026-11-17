class_name ShipReset
extends RefCounted

## The reset-to-start input's bookkeeping, kept out of `Sim` for its size: where
## each ship returns, and whether it may return now (RUN-3).
##
## Fixed for the run once the first tick starts, like the walls, so not part of
## the hash. Pure data and arithmetic (ARC-1, ARC-2).

## Start position and orientation of each ship, by ship index. `Sim` exposes
## these as `start_positions` and `start_orientations`; the exit rule and the
## escape path read them, since the exit is the entrance.
var positions: Array[Vector3] = []
var orientations: Array[Basis] = []


## Takes every ship's current pose as its start. Called when the ships are
## created and again just before the first tick, so a caller that places a ship
## before flying is honoured.
func record(ships: Array[ShipState]) -> void:
	positions.clear()
	orientations.clear()
	for ship: ShipState in ships:
		positions.append(ship.position)
		orientations.append(ship.orientation)


func set_pose(index: int, position: Vector3, orientation: Basis) -> void:
	positions[index] = position
	orientations[index] = orientation


## False only while the meltdown countdown runs: the start is then the exit, so
## a reset would be an instant escape instead of the flight back RUN-3 asks for.
static func allowed(reactor: ReactorState) -> bool:
	return reactor == null or not reactor.destroyed or reactor.meltdown_ticks_left <= 0


## Moves `ship` (index `index`) to its start at rest, unless `reactor` is in its
## meltdown. Pose and velocity only: hull, shield and energy are kept, so a
## reset is a way home and not a free repair. Returns whether the ship moved.
func apply(ship: ShipState, index: int, reactor: ReactorState) -> bool:
	if not allowed(reactor):
		return false
	ship.position = positions[index]
	ship.orientation = orientations[index]
	ship.velocity = Vector3.ZERO
	return true
