class_name PartSlotting
extends RefCounted

## Slotting the part in a ship's hold into a primary weapon slot (SLV-1,
## CMB-1, decision record 0011). Kept out of `Sim` so the tick there stays
## short; `Sim.step` calls `apply` for every live ship after it has moved and
## before it fires, so a weapon slotted on a tick can fire on it. Each control
## acts only on the tick it is pressed or changed, not while it stays held
## (#600). A dropped part joins `Sim.salvage` after the tick's items have
## moved, as a robot's drop does, so it floats exactly where it was dropped.
##
## | Held part | Primary slots | Input | Result |
## | --- | --- | --- | --- |
## | none | any | anything | nothing |
## | yes | one empty | `slot_held` | slots into the empty slot |
## | yes | both full | `slot_held` alone | nothing (the popup opens in xr) |
## | yes | both full | `slot_choice` slot 1 or 2 | replaces that slot; the old weapon drops behind the ship |
## | yes | both full | `slot_choice` dump | the held part drops behind the ship; the slots are unchanged |
## | yes | one empty | `slot_choice` dump | nothing (the accepted gap in 0011) |
## | yes | one empty | `slot_choice` slot 1 or 2 | nothing (the popup only opens with both full) |
##
## The choice is read before the click, so a choice and a click on one tick
## act on the slots as they were.


## Applies ship `index`'s slot controls from `input`, appending any dropped
## part to `drops` for `Sim` to add once the tick's items have moved.
static func apply(sim: Sim, index: int, input: ShipInput, drops: Array[SalvageItem]) -> void:
	var ship: ShipState = sim.ships[index]
	if input.slot_choice != ShipInput.SLOT_CHOICE_NONE and input.slot_choice != ship.slot_choice_was:
		choose(sim, index, input.slot_choice, drops)
	ship.slot_choice_was = input.slot_choice
	if input.slot_held and not ship.slot_was_held:
		slot_held(sim, index)
	ship.slot_was_held = input.slot_held


## Moves the part in ship `index`'s hold into its first empty primary slot.
## Does nothing with both slots full (the pilot chooses with `choose`), when
## the hold is empty or the catalogue has no such part: an unknown part stays
## in the hold, and so does any part of a destroyed ship (#601). Adds a
## PART_SLOTTED event when it slots.
static func slot_held(sim: Sim, index: int) -> void:
	var weapon: WeaponDef = _held_weapon(sim, index)
	var ship: ShipState = sim.ships[index]
	var slot: int = ship.primary_slots.find(null)
	if weapon == null or slot < 0:
		return
	_fill(sim, index, slot, weapon, SimEvent.new(SimEvent.Kind.PART_SLOTTED, index))


## Acts on the slot popup's `choice` (a `ShipInput.SLOT_CHOICE_` value) for
## ship `index`, only with a held part and both primary slots full. Slot 1 or
## 2 replaces that slot and drops the weapon it held; dump drops the held part
## and leaves the slots as they are. Either drop moves with the ship,
## `swap_drop_distance` behind it (`SalvageRules`). Adds a PART_SLOTTED event
## on a replace.
static func choose(sim: Sim, index: int, choice: int, drops: Array[SalvageItem]) -> void:
	var weapon: WeaponDef = _held_weapon(sim, index)
	var ship: ShipState = sim.ships[index]
	if weapon == null or ship.primary_slots.has(null):
		return
	if choice == ShipInput.SLOT_CHOICE_DUMP:
		drops.append(_drop_behind(sim, index, ship.hold[0]))
		ship.hold.remove_at(0)
		return
	if choice != ShipInput.SLOT_CHOICE_SLOT_1 and choice != ShipInput.SLOT_CHOICE_SLOT_2:
		return
	var slot: int = choice - ShipInput.SLOT_CHOICE_SLOT_1
	var event: SimEvent = SimEvent.new(SimEvent.Kind.PART_SLOTTED, index)
	var old_id: String = ship.primary_ids[slot]
	# A weapon placed without an id cannot be named as a part, so it has
	# nothing to drop as; every run's weapons come with ids from data.
	if old_id != "":
		var item: SalvageItem = _drop_behind(sim, index, old_id)
		drops.append(item)
		event.dropped = true
		event.vector = item.position
	_fill(sim, index, slot, weapon, event)


## The weapon of the part in ship `index`'s hold, or null when the ship is
## destroyed, its hold is empty or the catalogue has no such part.
static func _held_weapon(sim: Sim, index: int) -> WeaponDef:
	var ship: ShipState = sim.ships[index]
	if ship.is_destroyed() or ship.hold.is_empty():
		return null
	return sim.part(ship.hold[0])


## Part `id` as a free item behind ship `index` (#600), so the pilot sees it
## as another part, moving with the ship.
static func _drop_behind(sim: Sim, index: int, id: String) -> SalvageItem:
	var ship: ShipState = sim.ships[index]
	var behind: Vector3 = ship.orientation.z.normalized() * sim.salvage_rules.swap_drop_distance
	var item: SalvageItem = SalvageItem.new(id, ship.position + behind, ship.velocity)
	# Without this the ship, its hold now empty and the part at its centre,
	# would take it straight back on the next tick's pickup.
	item.ignored_ship = index
	return item


static func _fill(sim: Sim, index: int, slot: int, weapon: WeaponDef, event: SimEvent) -> void:
	var ship: ShipState = sim.ships[index]
	ship.primary_ids[slot] = ship.hold[0]
	ship.hold.remove_at(0)
	ship.primary_slots[slot] = weapon
	event.magnitude = slot
	sim.last_events.append(event)
