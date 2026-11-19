class_name PartSlotting
extends RefCounted

## Slotting the part in a ship's hold into a primary weapon slot (SLV-1,
## CMB-1). Kept out of `Sim` so the tick there stays short; `Sim.step` calls
## `slot_held` for a ship whose input has `slot_held` set, after the ship has
## moved and before it fires, so a weapon slotted on a tick can fire on it.
## A replaced weapon joins `Sim.salvage` after the tick's items have moved, as
## a robot's drop does, so it floats exactly where the ship was.


## Moves the part in ship `index`'s hold into its first empty primary slot,
## or, with both full, into the selected one. The weapon it replaces is
## dropped as a `SalvageItem` at the ship's position and velocity, appended
## to `drops` for `Sim` to add once the tick's items have moved. Does
## nothing when the hold is empty or the catalogue has no such part: an
## unknown part stays in the hold, and so does any part of a destroyed ship
## (#601). Adds a PART_SLOTTED event when it slots.
static func slot_held(sim: Sim, index: int, drops: Array[SalvageItem]) -> void:
	var ship: ShipState = sim.ships[index]
	if ship.is_destroyed() or ship.hold.is_empty():
		return
	var id: String = ship.hold[0]
	var weapon: WeaponDef = sim.part(id)
	if weapon == null:
		return
	var slot: int = ship.primary_slots.find(null)
	var event: SimEvent = SimEvent.new(SimEvent.Kind.PART_SLOTTED, index)
	if slot < 0:
		slot = ship.selected_primary
		var old_id: String = ship.primary_ids[slot]
		# A weapon placed without an id cannot be named as a part, so it has
		# nothing to drop as; every run's weapons come with ids from data.
		if old_id != "":
			var item: SalvageItem = SalvageItem.new(old_id, ship.position, ship.velocity)
			# Without this the ship, its hold now empty and the part at its
			# centre, would take it straight back on the next tick's pickup.
			item.ignored_ship = index
			drops.append(item)
			event.dropped = true
			event.vector = item.position
	ship.hold.remove_at(0)
	ship.primary_slots[slot] = weapon
	ship.primary_ids[slot] = id
	event.magnitude = slot
	sim.last_events.append(event)
