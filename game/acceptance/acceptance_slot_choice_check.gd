class_name AcceptanceSlotChoiceCheck
extends RefCounted

## The `slot_choice_applied` acceptance check (#1262, decision record 0011,
## SLV-1): re-flies a replay tick by tick and, on every tick ship 0's slot
## choice newly names a slot or a dump with a part held and both primary
## slots full, checks the result. A replace must put the held part in the
## chosen slot, leave the other slot alone and drop the old weapon behind the
## ship; a dump must leave both slots alone and drop the held part. Either drop
## must ignore the ship, so it is not pulled straight back in. Passes only if
## the replay replaced at least once and dumped at least once. The final state
## cannot show any of this, so like `wall_bounced` it flies the replay again;
## the hash check pins the flight itself.


## [result, message] for `replay`, adding its measurements.
static func run(replay: Replay, measurements: Dictionary) -> Array:
	# `Replay.run` with no frames is the sim set up from the header, before its
	# first tick; the frames are put back at once and stepped here.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	if sim.ships.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay has no ship"]
	var ship: ShipState = sim.ships[0]
	var replaced: int = 0
	var dumped: int = 0
	var last_choice: int = ShipInput.SLOT_CHOICE_NONE
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		var choice: int = inputs[0].slot_choice
		var acts: bool = choice != ShipInput.SLOT_CHOICE_NONE and choice != last_choice \
			and not ship.hold.is_empty() and not ship.primary_slots.has(null) and not ship.is_destroyed()
		last_choice = choice
		var tick: int = sim.tick
		var slots_before: Array[String] = ship.primary_ids.duplicate()
		var held: String = "" if ship.hold.is_empty() else ship.hold[0]
		var items_before: Array[SalvageItem] = sim.salvage.duplicate()
		sim.step(inputs)
		if not acts:
			continue
		var problem: String = ""
		if choice == ShipInput.SLOT_CHOICE_DUMP:
			problem = _dump_problem(sim, slots_before, held, items_before)
			dumped += 1
		else:
			problem = _replace_problem(sim, choice - ShipInput.SLOT_CHOICE_SLOT_1, slots_before, held,
				items_before)
			replaced += 1
		if problem != "":
			measurements["slot_choice_failed_tick"] = tick
			return [AcceptanceReport.RESULT_FAIL, "tick %d: %s" % [tick, problem]]
	measurements["slot_replaces"] = replaced
	measurements["slot_dumps"] = dumped
	measurements["primary_slots_at_end"] = ship.primary_ids.duplicate()
	if replaced == 0 or dumped == 0:
		return [AcceptanceReport.RESULT_FAIL, "%d replaces and %d dumps; the step needs at least one of each"
			% [replaced, dumped]]
	return [AcceptanceReport.RESULT_PASS, "%d replaced, %d dumped; slots %s" % [replaced, dumped,
		ship.primary_ids]]


static func _replace_problem(sim: Sim, slot: int, slots_before: Array[String], held: String,
		items_before: Array[SalvageItem]) -> String:
	var ship: ShipState = sim.ships[0]
	var expected: Array[String] = slots_before.duplicate()
	expected[slot] = held
	if ship.primary_ids != expected:
		return "replacing slot %d gave slots %s, expected %s" % [slot + 1, ship.primary_ids, expected]
	if not ship.hold.is_empty():
		return "the hold still holds %s after the replace" % [ship.hold]
	if not _dropped(sim, slots_before[slot], items_before):
		return "%s, replaced from slot %d, was not dropped ignoring the ship" % [slots_before[slot], slot + 1]
	return ""


static func _dump_problem(sim: Sim, slots_before: Array[String], held: String,
		items_before: Array[SalvageItem]) -> String:
	var ship: ShipState = sim.ships[0]
	if ship.primary_ids != slots_before:
		return "the dump changed the slots from %s to %s" % [slots_before, ship.primary_ids]
	if not ship.hold.is_empty():
		return "the hold still holds %s after the dump" % [ship.hold]
	if not _dropped(sim, held, items_before):
		return "the dumped %s was not dropped ignoring the ship" % held
	return ""


## Whether a part `id` new on this tick floats ignoring ship 0.
static func _dropped(sim: Sim, id: String, items_before: Array[SalvageItem]) -> bool:
	for item: SalvageItem in sim.salvage:
		if not items_before.has(item) and item.part_id == id and item.ignored_ship == 0:
			return true
	return false
