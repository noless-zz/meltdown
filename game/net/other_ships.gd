class_name OtherShips
extends RefCounted

## Ships 1 and up of a `LocalSession` that flies more than the local ship
## (#1354, PRF-8): each flown from its own input source with no network, and
## handed to the view as copies after the tick before the latest one and after
## it, as the local ship is, so drawing them cannot write simulation state
## (MP-2). Kept out of `local_session.gd` so that file stays under its size
## limit.

var _sources: Array[ShipInputSource] = []
var _previous: Array[ShipState] = []
var _current: Array[ShipState] = []


## Ship `i + 1` flies `sources[i]`; `sim` gives the poses before the first tick.
func _init(sources: Array[ShipInputSource], sim: Sim) -> void:
	_sources = sources.duplicate()
	take(sim)
	_previous = _current


## Number of ships flown here, the local ship not counted.
func count() -> int:
	return _sources.size()


## Each ship's input for `tick`, ship 1 first.
func inputs_at(tick: int) -> Array[ShipInput]:
	var inputs: Array[ShipInput] = []
	for source: ShipInputSource in _sources:
		inputs.append(source.next_input(tick))
	return inputs


## Copies ships 1 and up of `sim` after a tick; the last copies become the previous ones.
func take(sim: Sim) -> void:
	_previous = _current
	var copies: Array[ShipState] = []
	for index: int in range(1, sim.ships.size()):
		copies.append(SessionSnapshots.ship(sim.ships[index]))
	_current = copies


## Ships 1 and up after the tick before the latest one, ship 1 first. A new
## array of copies: changing it leaves the simulation as it was.
func previous() -> Array[ShipState]:
	return _previous.duplicate()


## Ships 1 and up after the latest tick, like `previous()`.
func current() -> Array[ShipState]:
	return _current.duplicate()
