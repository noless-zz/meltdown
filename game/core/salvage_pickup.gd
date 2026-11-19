class_name SalvagePickup
extends RefCounted

## Taking floating parts into a ship's hold (SLV-1), and moving the parts that
## float. Kept out of `Sim` so the tick there stays short; `Sim.step` calls
## `collect` and then `drift` once per tick. How far a ship reaches and pulls
## comes from `Sim.salvage_rules` (`SalvageRules`, ARC-4, #600).


## Lets every live ship with room in its hold take the floating items its
## centre passed within `radius + pickup_reach` of on the segment from
## `from[i]` to where it is now, so a fast pass that never ends a tick near an
## item still takes it. Ships go in index order, so on a tie the lower index
## gets the item; each ship takes the item it reached first along its path,
## then the next while it has room. Items are tested where they floated at
## the start of the tick. Taken items leave `sim.salvage`, keeping the order of
## the rest, and each adds a SALVAGE_COLLECTED event to `sim.last_events`.
## An item's `ignored_ship` cannot take it; once that ship's centre ends a tick
## out of reach of the item (pickup or pull, whichever is further), the item
## forgets it.
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
			var best: int = _first_reached(sim.salvage, taken, from[i], ship, i,
				sim.salvage_rules.pickup_reach)
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
		start: Vector3, ship: ShipState, ship_index: int, reach: float) -> int:
	var best: int = -1
	var best_t: float = INF
	for k: int in salvage.size():
		if taken[k] or salvage[k].ignored_ship == ship_index:
			continue
		var t: float = Projectile.segment_entry(start, ship.position, salvage[k].position,
			ship.radius + reach)
		if t >= 0.0 and t < best_t:
			best = k
			best_t = t
	return best


## Clears `ignored_ship` on every item whose ship is now out of its reach.
## Done after the pickups of the tick, so the path that leaves range cannot
## take the part either: the dropping ship has to fly away and come back. Pull
## reach counts too, or a swapped-out weapon would be pulled straight back.
## `pull_reach` is never below `pickup_reach`, so it is the further of the two.
static func _release_ignored(sim: Sim) -> void:
	for item: SalvageItem in sim.salvage:
		if item.ignored_ship < 0 or item.ignored_ship >= sim.ships.size():
			continue
		var ship: ShipState = sim.ships[item.ignored_ship]
		if item.position.distance_to(ship.position) > ship.radius + sim.salvage_rules.pull_reach:
			item.ignored_ship = -1


## Moves every floating part one tick, then adds `drops`, the weapons swapped
## out this tick. A part within pull reach of a ship that could take it first
## heads straight for that ship at `pull_speed` (SLV-1 "pulls it into the
## cockpit"); the nearest such ship pulls, ties going to the lower index. Parts
## already floating move before the drops, so a part appears exactly where its
## robot died or where its ship dropped it. Each is held by the box picked
## where it ends up, as ships are, so it can drift through an opening.
static func drift(sim: Sim, drops: Array[SalvageItem]) -> void:
	var rules: SalvageRules = sim.salvage_rules
	for item: SalvageItem in sim.salvage:
		if rules.pulls():
			var ship: ShipState = _puller(sim, item, rules.pull_reach)
			if ship != null:
				# Never past the ship's centre in one tick, so it cannot overshoot.
				var gap: float = item.position.distance_to(ship.position)
				item.velocity = item.position.direction_to(ship.position) \
					* minf(rules.pull_speed, gap / ShipState.TICK_DT)
		item.advance(null)
		if sim.walls != null:
			item.keep_inside(sim.walls.box_for(item.position, SalvageItem.RADIUS))
	sim.salvage.append_array(drops)


## The nearest ship that could take `item` and has it within `reach` of its
## hull, or null. A ship that is dead, gone, full or barred from the item
## pulls nothing: a part stuck to a full ship could never be reached by another.
static func _puller(sim: Sim, item: SalvageItem, reach: float) -> ShipState:
	var best: ShipState = null
	var best_distance: float = INF
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.hull <= 0.0 or ship.escaped or not ship.hold_has_room() \
				or item.ignored_ship == i:
			continue
		var distance: float = item.position.distance_to(ship.position)
		if distance <= ship.radius + reach and distance < best_distance:
			best = ship
			best_distance = distance
	return best
