extends RefCounted

## The slot popup's choice as recorded input (#1262, decision record 0011;
## SLV-1, CMB-1, ARC-2, MP-2): one test per row of `PartSlotting`'s table,
## the dropped parts, the replay column and determinism.

const WEAPONS: String = "res://data/weapons/%s.json"
const FORWARD: Vector3i = Vector3i(0, 0, -1000)
const BOTH: Array[String] = ["pulse_cannon", "needle_gun"]
const ONE: Array[String] = ["pulse_cannon", ""]


func _weapon(id: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS % id))


## One ship armed with `primaries` ("" for empty), holding `held` ("" for
## nothing), with every weapon in the catalogue.
func _sim(primaries: Array[String], held: String) -> Sim:
	var sim: Sim = Sim.new(5, 1)
	var loadout: ShipLoadout = ShipLoadout.new()
	for slot: int in primaries.size():
		if primaries[slot] != "":
			loadout.set_slot("primary", slot, primaries[slot], _weapon(primaries[slot]))
	sim.equip(loadout)
	var parts: Dictionary = {}
	for id: String in ["pulse_cannon", "needle_gun", "arc_lance"]:
		parts[id] = _weapon(id)
	sim.set_parts(parts)
	if held != "":
		sim.ships[0].hold.append(held)
	return sim


func _input(choice: int, slot: bool = false, thrust: Vector3i = Vector3i.ZERO) -> ShipInput:
	var input: ShipInput = ShipInput.new(thrust, Vector3i.ZERO, false, false, false, slot)
	input.slot_choice = choice
	return input


func _step(sim: Sim, input: ShipInput) -> void:
	var inputs: Array[ShipInput] = [input]
	sim.step(inputs)


## What the slots, hold and floating parts are, for comparing outcomes.
func _outcome(sim: Sim) -> String:
	var floating: PackedStringArray = PackedStringArray()
	for item: SalvageItem in sim.salvage:
		floating.append(item.part_id)
	var ship: ShipState = sim.ships[0]
	return "slots %s, hold %s, floating %s" % [ship.primary_ids, ship.hold, floating]


func _expect(sim: Sim, slots: Array[String], hold: Array[String], floating: Array[String]) -> String:
	var ship: ShipState = sim.ships[0]
	var ids: PackedStringArray = PackedStringArray()
	for item: SalvageItem in sim.salvage:
		ids.append(item.part_id)
	if ship.primary_ids != slots or ship.hold != hold or Array(ids) != Array(floating):
		return "got %s; expected slots %s, hold %s, floating %s" % [_outcome(sim), slots, hold, floating]
	return ""


func test_default_slot_choice_is_none() -> String:
	if ShipInput.new().slot_choice != ShipInput.SLOT_CHOICE_NONE:
		return "a new input has slot choice %d" % ShipInput.new().slot_choice
	return ""


func test_row_no_held_part_does_nothing() -> String:
	for primaries: Array[String] in [BOTH, ONE]:
		for choice: int in range(ShipInput.SLOT_CHOICE_NONE, ShipInput.SLOT_CHOICE_DUMP + 1):
			for slot: bool in [false, true]:
				var sim: Sim = _sim(primaries, "")
				_step(sim, _input(choice, slot))
				var result: String = _expect(sim, primaries, [], [])
				if result != "":
					return "%s, choice %d, click %s: %s" % [primaries, choice, slot, result]
	return ""


func test_row_click_with_one_empty_slots_it() -> String:
	var sim: Sim = _sim(ONE, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_NONE, true))
	return _expect(sim, ["pulse_cannon", "arc_lance"], [], [])


func test_row_click_alone_with_both_full_does_nothing() -> String:
	var sim: Sim = _sim(BOTH, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_NONE, true))
	return _expect(sim, BOTH, ["arc_lance"], [])


func test_row_choice_slot_1_replaces_slot_1() -> String:
	var sim: Sim = _sim(BOTH, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_SLOT_1))
	return _expect(sim, ["arc_lance", "needle_gun"], [], ["pulse_cannon"])


func test_row_choice_slot_2_replaces_slot_2() -> String:
	var sim: Sim = _sim(BOTH, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_SLOT_2))
	var result: String = _expect(sim, ["pulse_cannon", "arc_lance"], [], ["needle_gun"])
	if result != "":
		return result
	var event: SimEvent = null
	for found: SimEvent in sim.last_events:
		if found.kind == SimEvent.Kind.PART_SLOTTED:
			event = found
	if event == null or event.magnitude != 1.0 or not event.dropped:
		return "PART_SLOTTED event %s, expected slot 1 (index) dropped" % event
	return ""


func test_row_dump_with_both_full_drops_the_held_part() -> String:
	var sim: Sim = _sim(BOTH, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_DUMP))
	return _expect(sim, BOTH, [], ["arc_lance"])


func test_row_dump_with_one_empty_does_nothing() -> String:
	var sim: Sim = _sim(ONE, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_DUMP))
	return _expect(sim, ONE, ["arc_lance"], [])


func test_a_slot_choice_with_one_empty_does_nothing() -> String:
	for choice: int in [ShipInput.SLOT_CHOICE_SLOT_1, ShipInput.SLOT_CHOICE_SLOT_2]:
		var sim: Sim = _sim(ONE, "arc_lance")
		_step(sim, _input(choice))
		var result: String = _expect(sim, ONE, ["arc_lance"], [])
		if result != "":
			return "choice %d: %s" % [choice, result]
	return ""


## Both drops float behind the ship, ignore it, and stay out of its hold
## while it coasts on, as the old swap's drop did (#600).
func test_dumped_and_replaced_parts_are_not_pulled_straight_back() -> String:
	for choice: int in [ShipInput.SLOT_CHOICE_SLOT_1, ShipInput.SLOT_CHOICE_DUMP]:
		var sim: Sim = _sim(BOTH, "arc_lance")
		var ship: ShipState = sim.ships[0]
		ship.velocity = Vector3(0.5, 0.0, -4.0)
		_step(sim, _input(choice))
		if sim.salvage.size() != 1:
			return "choice %d: %d floating" % [choice, sim.salvage.size()]
		var item: SalvageItem = sim.salvage[0]
		if item.ignored_ship != 0:
			return "choice %d: the drop ignores ship %d" % [choice, item.ignored_ship]
		if item.velocity != ship.velocity:
			return "choice %d: the drop moves %s, the ship %s" % [choice, item.velocity, ship.velocity]
		for tick: int in 60:
			_step(sim, _input(ShipInput.SLOT_CHOICE_NONE))
		if not ship.hold.is_empty() or sim.salvage.size() != 1:
			return "choice %d: took its drop back, hold %s" % [choice, ship.hold]
	return ""


## A choice held over several ticks acts once, like the click (#600): the
## next part flown through is not swapped in by a stuck stick.
func test_a_held_choice_acts_once() -> String:
	var sim: Sim = _sim(BOTH, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_SLOT_2))
	sim.ships[0].hold.append("arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_SLOT_2))
	var result: String = _expect(sim, ["pulse_cannon", "arc_lance"], ["arc_lance"], ["needle_gun"])
	if result != "":
		return "held: " + result
	_step(sim, _input(ShipInput.SLOT_CHOICE_DUMP))
	return _expect(sim, ["pulse_cannon", "arc_lance"], [], ["needle_gun", "arc_lance"])


func test_a_choice_and_a_click_on_one_tick_act_on_the_slots_as_they_were() -> String:
	var sim: Sim = _sim(ONE, "arc_lance")
	_step(sim, _input(ShipInput.SLOT_CHOICE_DUMP, true))
	return _expect(sim, ["pulse_cannon", "arc_lance"], [], [])


func _run(choices: Array[int]) -> Sim:
	var sim: Sim = _sim(BOTH, "arc_lance")
	for tick: int in 90:
		var choice: int = choices[tick] if tick < choices.size() else ShipInput.SLOT_CHOICE_NONE
		_step(sim, _input(choice, false, FORWARD))
	return sim


func test_same_inputs_give_the_same_hash_and_a_choice_changes_it() -> String:
	var choices: Array[int] = [0, 0, ShipInput.SLOT_CHOICE_SLOT_2]
	if _run(choices).state_hash() != _run(choices).state_hash():
		return "two runs with the same choice differ"
	var none: Array[int] = []
	if _run(none).state_hash() == _run(choices).state_hash():
		return "replacing slot 2 left the hash unchanged"
	var dump: Array[int] = [0, 0, ShipInput.SLOT_CHOICE_DUMP]
	if _run(dump).state_hash() == _run(none).state_hash():
		return "dumping left the hash unchanged"
	return ""


func test_replay_round_trips_every_choice() -> String:
	var replay: Replay = Replay.new(5, 1)
	for choice: int in range(ShipInput.SLOT_CHOICE_NONE, ShipInput.SLOT_CHOICE_DUMP + 1):
		for slot: bool in [false, true]:
			var inputs: Array[ShipInput] = [_input(choice, slot)]
			replay.add_tick(inputs)
	var text: String = replay.to_text()
	if not text.begins_with("meltdown-replay %d\n" % ReplayLines.CHOICE_VERSION):
		return "a replay with choices is written as %s" % text.get_slice("\n", 0)
	if not text.contains("\n0 0 0 0 0 0 0 0 0 7\n"):
		return "no dump-and-click column 7 in %s" % text
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	for index: int in replay.frames.size():
		var sent: ShipInput = replay.frames[index][0]
		var read: ShipInput = reread.frames[index][0]
		if sent.slot_choice != read.slot_choice or sent.slot_held != read.slot_held:
			return "tick %d: wrote choice %d click %s, read %d %s" % [index, sent.slot_choice,
				sent.slot_held, read.slot_choice, read.slot_held]
	return ""


func test_a_replay_without_a_choice_is_written_as_before() -> String:
	var replay: Replay = Replay.new(5, 1)
	var inputs: Array[ShipInput] = [_input(ShipInput.SLOT_CHOICE_NONE, true)]
	replay.add_tick(inputs)
	var text: String = replay.to_text()
	if not text.begins_with("meltdown-replay 17\n") or not text.contains("\n0 0 0 0 0 0 0 0 0 1\n"):
		return "written as %s" % text
	return ""


func test_older_replays_read_as_no_choice_and_refuse_one() -> String:
	for version: int in [11, 17, 18]:
		var head: String = "meltdown-replay %d\nseed 1\nships 1\ninputs\n" % version
		var plain: Replay = Replay.from_text(head + "0 0 -1000 0 0 0 0 0 1 1\n")
		if plain.error != "":
			return "version %d: %s" % [version, plain.error]
		var input: ShipInput = plain.frames[0][0]
		if input.slot_choice != ShipInput.SLOT_CHOICE_NONE or not input.slot_held:
			return "version %d read choice %d" % [version, input.slot_choice]
		var chosen: Replay = Replay.from_text(head + "0 0 0 0 0 0 0 0 0 2\n")
		if not chosen.error.contains("slot must be 0 to 1"):
			return "version %d took a choice: '%s'" % [version, chosen.error]
	var too_big: Replay = Replay.from_text(
		"meltdown-replay 19\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 0 0 8\n")
	if not too_big.error.contains("slot must be 0 to 7"):
		return "a slot column of 8 gave '%s'" % too_big.error
	return ""

