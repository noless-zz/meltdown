extends RefCounted

## Parts drift towards a ship that can take them, slotting needs a fresh
## press, and a swapped-out weapon lands behind the ship (#600, SLV-1, ARC-2).

const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const NEEDLE_GUN: String = "res://data/weapons/needle_gun.json"


func _rules() -> SalvageRules:
	return SalvageRules.parse_json(JSON.stringify({"pickup_reach": 2.5, "pull_reach": 9.0,
		"pull_speed": 8.0, "swap_drop_distance": 4.0}))


func _sim(ships: int = 1, rules: SalvageRules = null) -> Sim:
	var sim: Sim = Sim.new(4, ships)
	sim.set_salvage_rules(rules if rules != null else _rules())
	return sim


func _step(sim: Sim, slot: bool = false, choice: int = ShipInput.SLOT_CHOICE_NONE) -> void:
	var inputs: Array[ShipInput] = []
	for i: int in sim.ships.size():
		inputs.append(ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, false, slot))
		inputs[i].slot_choice = choice
	sim.step(inputs)


func _weapon(path: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(path))


func test_a_part_in_pull_reach_drifts_in_and_is_taken() -> String:
	var sim: Sim = _sim()
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3(0.0, 0.0, -8.0)))
	_step(sim)
	var moved: float = 8.0 - sim.salvage[0].position.length()
	if moved <= 0.0:
		return "the part did not move towards the ship"
	for i: int in 120:
		_step(sim)
	if not sim.salvage.is_empty() or sim.ships[0].hold != ["pulse_cannon"]:
		return "after 2 s the hold is %s with %d parts floating" % [sim.ships[0].hold, sim.salvage.size()]
	return ""


func test_a_part_out_of_pull_reach_stays_put() -> String:
	var sim: Sim = _sim()
	var at: Vector3 = Vector3(0.0, 0.0, -10.5)
	sim.salvage.append(SalvageItem.new("pulse_cannon", at))
	for i: int in 60:
		_step(sim)
	if sim.salvage.size() != 1 or sim.salvage[0].position != at:
		return "a part 10.5 m off moved or was taken"
	return ""


func test_without_rules_nothing_is_pulled() -> String:
	var sim: Sim = Sim.new(4, 1)
	var at: Vector3 = Vector3(0.0, 0.0, -4.0)
	sim.salvage.append(SalvageItem.new("pulse_cannon", at))
	for i: int in 60:
		_step(sim)
	if sim.salvage.size() != 1 or sim.salvage[0].position != at:
		return "the default rules pulled a part"
	return ""


func test_a_full_hold_or_a_barred_ship_pulls_nothing() -> String:
	var sim: Sim = _sim()
	sim.ships[0].hold.append("needle_gun")
	var at: Vector3 = Vector3(0.0, 0.0, -6.0)
	sim.salvage.append(SalvageItem.new("pulse_cannon", at))
	var barred: SalvageItem = SalvageItem.new("needle_gun", Vector3(0.0, 0.0, 6.0))
	barred.ignored_ship = 0
	sim.salvage.append(barred)
	_step(sim)
	if sim.salvage[0].position != at:
		return "a ship with a full hold pulled a part"
	sim.ships[0].hold.clear()
	_step(sim)
	if sim.salvage[1].position != Vector3(0.0, 0.0, 6.0):
		return "the ship pulled the part it dropped"
	return ""


func test_the_nearer_ship_pulls() -> String:
	var sim: Sim = _sim(2)
	sim.set_start_pose(0, Vector3(-6.0, 0.0, 0.0), Basis.IDENTITY)
	sim.set_start_pose(1, Vector3(4.0, 0.0, 0.0), Basis.IDENTITY)
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3.ZERO))
	_step(sim)
	if sim.salvage[0].position.x <= 0.0:
		return "the part moved to %s, not towards the nearer ship 1" % sim.salvage[0].position
	return ""


func test_pull_is_deterministic() -> String:
	var hashes: Array[int] = []
	for attempt: int in 2:
		var sim: Sim = _sim()
		sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3(3.0, 2.0, -7.0)))
		for i: int in 20:
			_step(sim)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "two runs hashed %s" % [hashes]
	return ""


## The owner held the stick click while flying through a part: it was taken
## and swapped in on the next tick, so it looked as if nothing was collected.
func test_holding_the_slot_control_through_a_part_does_not_slot_it() -> String:
	var sim: Sim = _sim()
	sim.set_parts({"needle_gun": _weapon(NEEDLE_GUN)})
	# Slot 2 empty, so a press slots at once (decision record 0011).
	sim.ships[0].primary_slots = [_weapon(PULSE_CANNON), null]
	sim.ships[0].primary_ids = ["pulse_cannon", ""]
	_step(sim, true)
	sim.salvage.append(SalvageItem.new("needle_gun", Vector3(0.0, 0.0, -1.0)))
	for i: int in 30:
		_step(sim, true)
	if sim.ships[0].hold != ["needle_gun"]:
		return "with the control held the hold is %s, expected the part kept" % [sim.ships[0].hold]
	_step(sim, false)
	_step(sim, true)
	if not sim.ships[0].hold.is_empty() or sim.ships[0].primary_ids[1] != "needle_gun":
		return "a fresh press did not slot the part: hold %s, slots %s" % [sim.ships[0].hold,
			sim.ships[0].primary_ids]
	return ""


func test_a_swapped_weapon_drops_behind_the_ship() -> String:
	var sim: Sim = _sim()
	sim.set_parts({"needle_gun": _weapon(NEEDLE_GUN)})
	var facing: Basis = Basis(Vector3.UP, 0.7)
	sim.set_start_pose(0, Vector3(1.0, 2.0, 3.0), facing)
	sim.ships[0].primary_slots = [_weapon(PULSE_CANNON), _weapon(PULSE_CANNON)]
	sim.ships[0].primary_ids = ["pulse_cannon", "pulse_cannon"]
	sim.ships[0].hold.append("needle_gun")
	# Both full: the popup's choice swaps, here slot 1 (#1262).
	_step(sim, false, ShipInput.SLOT_CHOICE_SLOT_1)
	if sim.salvage.size() != 1:
		return "%d parts floating after the swap, expected 1" % sim.salvage.size()
	var expected: Vector3 = sim.ships[0].position + facing.z * 4.0
	if sim.salvage[0].position.distance_to(expected) > 1e-4:
		return "dropped at %s, expected 4 m behind at %s" % [sim.salvage[0].position, expected]
	# Not pulled straight back: barred until the ship has left pull reach.
	for i: int in 30:
		_step(sim)
	if sim.salvage.size() != 1 or sim.salvage[0].ignored_ship != 0:
		return "the dropped part came back or was released while the ship stayed by it"
	sim.ships[0].position = expected + Vector3(0.0, 11.0, 0.0)
	_step(sim)
	if sim.salvage.size() != 1 or sim.salvage[0].ignored_ship != -1:
		return "the dropped part is still barred to the ship 11 m away"
	return ""
