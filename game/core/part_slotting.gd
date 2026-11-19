class_name PartSlotting
extends RefCounted

## Slotting the part in a ship's hold into a primary weapon slot (SLV-1,
## CMB-1). Kept out of `Sim` so the tick there stays short; `Sim.step` calls
## `slot_held` for a ship whose input newly has `slot_held` set, after the ship has
## moved and before it fires, so a weapon slotted on a tick can fire on it.
## Only on the tick the control is pressed, not while it stays held (#600).
## A replaced weapon joins `Sim.salvage` after the tick's items have moved, as
## a robot's drop does, so it floats exactly where it was dropped.


## Moves the part in ship `index`'s hold into its first empty primary slot,
## or, with both full, into the selected one. The weapon it replaces is
## dropped as a `SalvageItem` moving with the ship, `swap_drop_distance` behind
## it (`SalvageRules`), appended
## to `drops` for `Sim` to add once the tick's items have moved. Does
## nothing when the hold is empty or the catalogue has no such part: an
## unknown part stays in the hold. Adds a PART_SLOTTED event when it slots.
static func slot_held(sim: Sim, index: int, drops: Array[SalvageItem]) -> void:
	var ship: ShipState = sim.ships[index]
	if ship.hold.is_empty():
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
			# Behind the ship (#600), so the pilot sees it as another part.
			var behind: Vector3 = ship.orientation.z.normalized() * sim.salvage_rules.swap_drop_distance
			var item: SalvageItem = SalvageItem.new(old_id, ship.position + behind, ship.velocity)
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
