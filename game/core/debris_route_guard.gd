class_name DebrisRouteGuard
extends RefCounted

## Keeps RUN-4's promise that a route to the exit always exists during the
## meltdown, whatever the level file says about debris. Kept out of `Sim`, which
## is at its size limit, and out of `MeltdownDebris`, which knows no ships.
##
## When an entry falls due, the guard asks `KnownRoute`, with every box counted
## as explored, whether each live ship (hull above zero, not escaped) still has
## a route to its exit (its start) with the debris already solid plus this
## entry. If a ship that has a route now would have none, the entry is marked
## skipped and never becomes solid. Entries due on the same tick are checked one
## by one in file order, each with the ones before it that were let fall.
##
## A ship that already has no route is not counted: holding debris back cannot
## give it one, and debris never took it away, since the guard ran for every
## entry before. Open space (no walls) has no openings to close, so nothing is
## checked there. Everything the check reads is whole millimetres and the
## simulation's own state, so the outcome is the same on every device and in
## every replay (ARC-1, ARC-2).


## Advances `sim.debris`'s clock by one tick (see `MeltdownDebris.advance`) and
## holds back any entry falling due on it that would close a ship's last route,
## appending one DEBRIS_HELD event per held entry to `events`.
static func advance(sim: Sim, events: Array[SimEvent]) -> void:
	var debris: MeltdownDebris = sim.debris
	var before: int = debris.elapsed_ticks
	debris.advance(sim.reactor)
	# The clock only moves forward and never skips a value, so the entries
	# falling due now are exactly those waiting for its new value.
	if debris.elapsed_ticks == before or sim.walls == null:
		return
	var explored: Array[int] = []
	for box: int in sim.walls.boxes.size():
		explored.append(box)
	for index: int in debris.size():
		if debris.after_ticks[index] != debris.elapsed_ticks:
			continue
		var losing: int = _ship_losing_route(sim, explored, index)
		if losing >= 0:
			debris.skipped[index] = true
			events.append(SimEvent.new(SimEvent.Kind.DEBRIS_HELD, losing, float(index),
				debris.position(index)))


## The first live ship that has a route now and would have none once entry
## `index` is solid, or -1.
static func _ship_losing_route(sim: Sim, explored: Array[int], index: int) -> int:
	var now: MeltdownDebris = _fallen(sim.debris, index, false)
	var then: MeltdownDebris = _fallen(sim.debris, index, true)
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.hull <= 0.0 or ship.escaped:
			continue
		var exit: Vector3 = sim.start_positions[i]
		if not _has_route(sim, explored, ship, exit, now):
			continue
		if not _has_route(sim, explored, ship, exit, then):
			return i
	return -1


static func _has_route(sim: Sim, explored: Array[int], ship: ShipState, exit: Vector3,
		debris: MeltdownDebris) -> bool:
	var route: KnownRoute = KnownRoute.find(sim.walls, explored, ship.position, exit, debris,
		ship.radius)
	return route.length_mm != EscapePath.UNREACHABLE


## The debris solid before entry `index` was checked, plus that entry when
## `with_entry`: every entry that fell on an earlier tick and was let fall, and
## every entry before `index` in file order that falls on this tick and was let
## fall. Built as a separate list, all solid, so the real one is left untouched.
static func _fallen(debris: MeltdownDebris, index: int, with_entry: bool) -> MeltdownDebris:
	var fallen: MeltdownDebris = MeltdownDebris.new()
	for other: int in debris.size():
		var earlier: bool = debris.after_ticks[other] < debris.elapsed_ticks \
			or debris.after_ticks[other] == debris.elapsed_ticks and other < index
		var counted: bool = earlier and not debris.is_skipped(other)
		if counted or with_entry and other == index:
			fallen.positions_mm.append(debris.positions_mm[other])
			fallen.radii_mm.append(debris.radii_mm[other])
			# A box keeps its size, so a door is tested as a door, not a point.
			fallen.sizes_mm.append(debris.sizes_mm[other] if debris.is_box(other) else Vector3i.ZERO)
			fallen.after_ticks.append(1)
			fallen.skipped.append(false)
	fallen.elapsed_ticks = 1
	return fallen
