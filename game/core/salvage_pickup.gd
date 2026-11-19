class_name SalvagePickup
extends RefCounted

## Taking floating parts into a ship's hold (SLV-1). Kept out of `Sim` so the
## tick there stays short; `Sim.step` calls `collect` once per tick.

## How far beyond its own `radius` a ship's centre may pass from an item and
## still take it, in metres. Generous, because a part is small and the pilot
## aims with the whole ship.
const PICKUP_RADIUS: float = 1.5


## Lets every live ship with room in its hold take the floating items its
## centre passed within `radius + PICKUP_RADIUS` of on the segment from
## `from[i]` to where it is now, so a fast pass that never ends a tick near an
## item still takes it. Ships go in index order, so on a tie the lower index
## gets the item; each ship takes the item it reached first along its path,
## then the next while it has room. Items are tested where they floated at
## the start of the tick. Taken items leave `sim.salvage`, keeping the order of
## the rest, and each adds a SALVAGE_COLLECTED event to `sim.last_events`.
## An item's `ignored_ship` cannot take it; once that ship's centre ends a tick
## out of pickup range of the item, the item forgets it.
static func collect(sim: Sim, from: Array[Vector3]) -> void:
	_take(sim, from)
	_release_ignored(sim)


static func _take(sim: Sim, from: Array[Vector3]) -> void:
	if sim.salvage.is_empty():
		return
	var taken: Array[bool] = []
	taken.resize(sim.salvage.size())
	taken.fill(false)
	var any: bool = false
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.hull <= 0.0 or ship.escaped:
			continue
		while ship.hold_has_room():
			var best: int = _first_reached(sim.salvage, taken, from[i], ship, i)
			if best < 0:
				break
			var item: SalvageItem = sim.salvage[best]
			taken[best] = true
			any = true
			ship.hold.append(item.part_id)
			sim.last_events.append(SimEvent.new(SimEvent.Kind.SALVAGE_COLLECTED, i,
				best, item.position))
	if not any:
		return
	var kept: Array[SalvageItem] = []
	for k: int in sim.salvage.size():
		if not taken[k]:
			kept.append(sim.salvage[k])
	sim.salvage = kept


## Index of the untaken item `ship`'s path from `start` reaches first, or -1.
## Only a strictly earlier entry replaces the best, so ties go to the lower
## item index.
static func _first_reached(salvage: Array[SalvageItem], taken: Array[bool],
		start: Vector3, ship: ShipState, ship_index: int) -> int:
	var best: int = -1
	var best_t: float = INF
	for k: int in salvage.size():
		if taken[k] or salvage[k].ignored_ship == ship_index:
			continue
		var t: float = Projectile.segment_entry(start, ship.position, salvage[k].position,
			ship.radius + PICKUP_RADIUS)
		if t >= 0.0 and t < best_t:
			best = k
			best_t = t
	return best


## Clears `ignored_ship` on every item whose ship is now out of pickup range.
## Done after the pickups of the tick, so the path that leaves range cannot
## take the part either: the dropping ship has to fly away and come back.
static func _release_ignored(sim: Sim) -> void:
	for item: SalvageItem in sim.salvage:
		if item.ignored_ship < 0 or item.ignored_ship >= sim.ships.size():
			continue
		var ship: ShipState = sim.ships[item.ignored_ship]
		if item.position.distance_to(ship.position) > ship.radius + PICKUP_RADIUS:
			item.ignored_ship = -1
