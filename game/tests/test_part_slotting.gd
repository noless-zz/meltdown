extends RefCounted

## Slotting the held part into a primary slot (#268, SLV-1, CMB-1, MP-2,
## ARC-2): the input, the event, the dropped weapon and the replay column.

const DRONE: String = "res://data/robots/drone.json"
const WEAPONS: String = "res://data/weapons/%s.json"
const DRONE_AT: Vector3i = Vector3i(0, 0, -30000)
const FORWARD: Vector3i = Vector3i(0, 0, -1000)


func _weapon(id: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS % id))


## A loadout with `ids` in the primary slots, "" for empty.
func _loadout(ids: Array[String]) -> ShipLoadout:
	var loadout: ShipLoadout = ShipLoadout.new()
	for slot: int in ids.size():
		if ids[slot] != "":
			loadout.set_slot("primary", slot, ids[slot], _weapon(ids[slot]))
	return loadout


## One ship holding `held`, armed with `primaries`, catalogue `catalogue`.
func _sim(primaries: Array[String], catalogue: Array[String], held: String) -> Sim:
	var sim: Sim = Sim.new(3, 1)
	sim.equip(_loadout(primaries))
	var parts: Dictionary = {}
	for id: String in catalogue:
		parts[id] = _weapon(id)
	sim.set_parts(parts)
	if held != "":
		sim.ships[0].hold.append(held)
	return sim


func _step(sim: Sim, slot: bool, thrust: Vector3i = Vector3i.ZERO, fire: bool = false) -> void:
	var inputs: Array[ShipInput] = [
		ShipInput.new(thrust, Vector3i.ZERO, false, false, fire, slot)]
	sim.step(inputs)


func _slotted(sim: Sim) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.PART_SLOTTED:
			found.append(event)
	return found


func test_slots_into_the_first_empty_primary() -> String:
	for primaries: Array[String] in [["", ""] as Array[String], ["pulse_cannon", ""] as Array[String]]:
		var sim: Sim = _sim(primaries, ["needle_gun"], "needle_gun")
		var ship: ShipState = sim.ships[0]
		var slot: int = 0 if primaries[0] == "" else 1
		_step(sim, true)
		if not ship.hold.is_empty():
			return "%s: hold still %s" % [primaries, ship.hold]
		if ship.primary_slots[slot] != sim.part("needle_gun") or ship.primary_ids[slot] != "needle_gun":
			return "%s: slot %d holds %s" % [primaries, slot, ship.primary_ids[slot]]
		if slot == 1 and ship.primary_ids[0] != "pulse_cannon":
			return "the filled slot changed to %s" % ship.primary_ids[0]
		if not sim.salvage.is_empty():
			return "%s: dropped %d items into an empty slot" % [primaries, sim.salvage.size()]
		var events: Array[SimEvent] = _slotted(sim)
		var expected: SimEvent = SimEvent.new(SimEvent.Kind.PART_SLOTTED, 0, slot)
		if events.size() != 1 or not events[0].equals(expected):
			return "%s: events %s, expected %s" % [primaries, events, expected]
	return ""


func test_both_full_replaces_the_selected_and_drops_the_old() -> String:
	var sim: Sim = _sim(["pulse_cannon", "needle_gun"], ["arc_lance"], "arc_lance")
	var ship: ShipState = sim.ships[0]
	ship.selected_primary = 1
	ship.velocity = Vector3(1.0, 2.0, -6.0)
	_step(sim, true, FORWARD)
	if ship.primary_ids != (["pulse_cannon", "arc_lance"] as Array[String]):
		return "slots hold %s" % [ship.primary_ids]
	if ship.primary_slots[1] != sim.part("arc_lance"):
		return "slot 2 is not the catalogue's arc lance"
	if sim.salvage.size() != 1:
		return "%d items floating, expected the needle gun" % sim.salvage.size()
	var item: SalvageItem = sim.salvage[0]
	if item.part_id != "needle_gun" or item.position != ship.position or item.velocity != ship.velocity:
		return "dropped %s at %s moving %s; ship at %s moving %s" % [
			item.part_id, item.position, item.velocity, ship.position, ship.velocity]
	var events: Array[SimEvent] = _slotted(sim)
	var expected: SimEvent = SimEvent.new(SimEvent.Kind.PART_SLOTTED, 0, 1, ship.position)
	expected.dropped = true
	if events.size() != 1 or not events[0].equals(expected):
		return "events %s, expected %s dropped" % [events, expected]
	# Coasting on with it, the ship must not take its own drop back.
	for tick: int in 60:
		_step(sim, false)
	if not ship.hold.is_empty() or sim.salvage.size() != 1:
		return "the ship took back the part it dropped: hold %s" % [ship.hold]
	return ""


func test_a_dropped_part_can_be_taken_after_flying_away() -> String:
	var sim: Sim = _sim(["pulse_cannon", "needle_gun"], ["arc_lance"], "arc_lance")
	var ship: ShipState = sim.ships[0]
	_step(sim, true)
	var dropped_at: Vector3 = sim.salvage[0].position
	for tick: int in 60:
		_step(sim, false, FORWARD)
	if sim.salvage[0].ignored_ship != -1:
		return "the item still ignores the ship %f m away" % ship.position.distance_to(dropped_at)
	for tick: int in 240:
		_step(sim, false, -FORWARD)
		if sim.salvage.is_empty():
			break
	if ship.hold != (["pulse_cannon"] as Array[String]):
		return "flying back through it, hold is %s" % [ship.hold]
	return ""


func test_a_part_not_in_the_catalogue_stays_held() -> String:
	var sim: Sim = _sim(["", ""], ["pulse_cannon"], "mystery_part")
	_step(sim, true)
	var ship: ShipState = sim.ships[0]
	if ship.hold != (["mystery_part"] as Array[String]):
		return "hold is %s" % [ship.hold]
	if ship.primary_slots != ([null, null] as Array[WeaponDef]) or not _slotted(sim).is_empty():
		return "an unknown part was slotted"
	return ""


func test_an_empty_hold_does_nothing() -> String:
	var sim: Sim = _sim(["pulse_cannon", "needle_gun"], ["arc_lance"], "")
	var plain: Sim = _sim(["pulse_cannon", "needle_gun"], ["arc_lance"], "")
	for tick: int in 30:
		_step(sim, true, FORWARD, true)
		if not _slotted(sim).is_empty():
			return "tick %d slotted from an empty hold" % tick
		_step(plain, false, FORWARD, true)
	if sim.state_hash() != plain.state_hash() or not sim.salvage.is_empty():
		return "slot_held with an empty hold changed the run"
	return ""


func test_the_slotted_weapon_fires_on_the_same_tick() -> String:
	var sim: Sim = _sim(["", ""], ["needle_gun"], "needle_gun")
	_step(sim, true, Vector3i.ZERO, true)
	if sim.projectiles.size() != 1:
		return "%d projectiles after slotting and firing" % sim.projectiles.size()
	return ""


## Kills a drone, flies through its cannon, slots it over the selected
## primary and flies on; the replay of all that must end on the live hash.
func test_a_replayed_slotting_run_matches_the_live_hash() -> String:
	var replay: Replay = Replay.new(11, 1)
	replay.loadout = _loadout(["pulse_cannon", "needle_gun"])
	var odd: WeaponDef = _weapon("pulse_cannon")
	odd.damage = 3.123456789012  # Not round, so the slotted values must travel exactly.
	replay.parts = {"pulse_cannon": odd}
	replay.robots.append(RobotSpawn.new(
		RobotDef.parse_json(FileAccess.get_file_as_string(DRONE)), DRONE_AT))
	var live: Sim = replay.run()
	var phase: int = 0
	var slotted_at: int = -1
	for tick: int in 900:
		var input: ShipInput = ShipInput.new()
		if phase == 0:
			input.fire_primary = true
			if live.robots.is_empty():
				phase = 1
		elif phase == 1:
			input.thrust_q = FORWARD
			if not live.ships[0].hold.is_empty():
				phase = 2
		elif phase == 2:
			input.slot_held = true
			slotted_at = tick
			phase = 3
		else:
			input.thrust_q = -FORWARD
			input.fire_primary = true
		var inputs: Array[ShipInput] = [input]
		live.step(inputs)
		replay.add_tick(inputs)
		if phase == 3 and tick > slotted_at + 120:
			break
	if slotted_at < 0:
		return "never picked up the drone's cannon (phase %d)" % phase
	var ship: ShipState = live.ships[0]
	if ship.primary_slots[0] != live.part("pulse_cannon") or live.salvage.size() != 1:
		return "the slotting did not happen: slot 1 %s, %d floating" % [
			ship.primary_slots[0], live.salvage.size()]
	var text: String = replay.to_text()
	if not text.contains("\n0 0 0 0 0 0 0 0 0 1\n"):
		return "no slot column in the written replay"
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	var replayed: Sim = reread.run()
	if replayed == null:
		return reread.run_error
	if replayed.state_hash() != live.state_hash():
		return "the replay ends on %d, the live run on %d" % [replayed.state_hash(), live.state_hash()]
	# Without the slot column the run must differ, or the test proves nothing.
	for frame: Array in reread.frames:
		(frame[0] as ShipInput).slot_held = false
	if reread.run().state_hash() == live.state_hash():
		return "dropping the slot input does not change the hash"
	return ""


func test_older_formats_read_slot_as_off() -> String:
	var text: String = "meltdown-replay 10\nseed 1\nships 1\ninputs\n0 0 -1000 0 0 0 0 0 1\n"
	var replay: Replay = Replay.from_text(text)
	if replay.error != "":
		return replay.error
	if (replay.frames[0][0] as ShipInput).slot_held:
		return "a version 10 tick read as slotting"
	var bad: Replay = Replay.from_text(
		"meltdown-replay 11\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 0 0 2\n")
	if not bad.error.contains("slot must be 0 or 1"):
		return "a slot value of 2 gave '%s'" % bad.error
	var short: Replay = Replay.from_text(
		"meltdown-replay 11\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 0 0\n")
	if short.error == "":
		return "a version 11 tick with nine numbers was accepted"
	return ""


func test_net_messages_carry_slot_held_in_the_fourth_bit() -> String:
	if NetMessages.BOOL_FIELDS.find("slot_held") != 3:
		return "slot_held is bit %d" % NetMessages.BOOL_FIELDS.find("slot_held")
	var bytes: PackedByteArray = NetMessages.encode_input(1, 0,
		ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, false, true))
	if bytes[NetMessages.INPUT_SIZE - 1] != 8:
		return "flags byte is %d, expected 8" % bytes[NetMessages.INPUT_SIZE - 1]
	var message: Dictionary = NetMessages.decode(bytes)
	if message.has("error") or not (message["input"] as ShipInput).slot_held:
		return "decoded %s" % message
	return ""
