extends RefCounted

## The right trigger fires every filled primary slot, each on its own interval
## and energy cost (decision record 0011, #1261, CMB-1, SLV-1, ARC-2).

const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const NEEDLE_GUN: String = "res://data/weapons/needle_gun.json"


static func _weapon(path: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(path))


static func _fire() -> ShipInput:
	return ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, true)


## One ship with the pulse cannon in slot 1 and, when `both`, the needle gun
## in slot 2. Energy recharge is off so the pool shows only what shots spent.
static func _sim(both: bool, seed_value: int = 7) -> Sim:
	var sim: Sim = Sim.new(seed_value, 1)
	sim.ships[0].primary_slots[0] = _weapon(PULSE_CANNON)
	if both:
		sim.ships[0].primary_slots[1] = _weapon(NEEDLE_GUN)
	sim.ships[0].energy_recharge = 0.0
	return sim


static func _step(sim: Sim, input: ShipInput) -> void:
	var inputs: Array[ShipInput] = [input]
	sim.step(inputs)


## Shots by slot fired over `ticks` ticks of held fire, and the error message
## of the first tick whose energy drain is not the cost of that tick's shots.
static func _fire_for(sim: Sim, ticks: int) -> Array:
	var counts: Array[int] = [0, 0]
	var problem: String = ""
	var seen: Dictionary[Projectile, bool] = {}
	for tick: int in ticks:
		var energy: float = sim.ships[0].energy
		_step(sim, _fire())
		var cost: float = 0.0
		# By identity: shots that ran out this tick are gone from the list.
		for projectile: Projectile in sim.projectiles:
			if seen.has(projectile):
				continue
			seen[projectile] = true
			counts[projectile.slot] += 1
			cost += sim.ships[0].primary_slots[projectile.slot].energy_cost
		if problem == "" and not is_equal_approx(energy - sim.ships[0].energy, cost):
			problem = "tick %d drained %f energy, its shots cost %f" % [tick, energy - sim.ships[0].energy, cost]
	return [counts, problem]


func test_one_and_two_filled_slots_fire_on_their_own_intervals() -> String:
	var pulse: WeaponDef = _weapon(PULSE_CANNON)
	var needle: WeaponDef = _weapon(NEEDLE_GUN)
	var ticks: int = ShipState.TICK_RATE
	var one: Array = _fire_for(_sim(false), ticks)
	var two: Array = _fire_for(_sim(true), ticks)
	var pulse_shots: int = ceili(float(ticks) / pulse.fire_interval_ticks)
	var needle_shots: int = ceili(float(ticks) / needle.fire_interval_ticks)
	if one[0] != ([pulse_shots, 0] as Array[int]):
		return "one slot filled fired %s shots by slot, expected [%d, 0]" % [one[0], pulse_shots]
	if two[0] != ([pulse_shots, needle_shots] as Array[int]):
		return "two slots filled fired %s shots by slot, expected [%d, %d]" % [two[0], pulse_shots, needle_shots]
	if one[1] != "" or two[1] != "":
		return "one slot: %s; two slots: %s" % [one[1], two[1]]
	return ""


func test_both_slots_fire_on_the_first_tick_slot_1_first() -> String:
	var sim: Sim = _sim(true)
	_step(sim, _fire())
	if sim.projectiles.size() != 2:
		return "%d shots on the first tick, expected 2" % sim.projectiles.size()
	if sim.projectiles[0].slot != 0 or sim.projectiles[1].slot != 1:
		return "shots came from slots %d, %d" % [sim.projectiles[0].slot, sim.projectiles[1].slot]
	var speeds: Array[float] = [sim.projectiles[0].velocity.length(), sim.projectiles[1].velocity.length()]
	if not is_equal_approx(speeds[0], _weapon(PULSE_CANNON).projectile_speed) \
			or not is_equal_approx(speeds[1], _weapon(NEEDLE_GUN).projectile_speed):
		return "shots fly at %s, not each weapon's own speed" % [speeds]
	return ""


func test_a_weapon_in_slot_2_alone_fires() -> String:
	var sim: Sim = Sim.new(7, 1)
	sim.ships[0].primary_slots[1] = _weapon(NEEDLE_GUN)
	_step(sim, _fire())
	if sim.projectiles.size() != 1 or sim.projectiles[0].slot != 1:
		return "with only slot 2 filled: %d shots" % sim.projectiles.size()
	return ""


## The pulse cannon in slot 1 costs more than the pool holds; the cheaper
## needle gun in slot 2 still fires.
func test_a_slot_short_of_energy_does_not_stop_the_other() -> String:
	var sim: Sim = _sim(true)
	sim.ships[0].energy = _weapon(PULSE_CANNON).energy_cost * 0.5
	_step(sim, _fire())
	if sim.projectiles.size() != 1 or sim.projectiles[0].slot != 1:
		return "%d shots with energy for the needle gun only" % sim.projectiles.size()
	if sim.ships[0].fire_cooldowns[0] != 0:
		return "the slot that could not fire started its interval"
	return ""


func test_no_shot_without_the_trigger() -> String:
	var sim: Sim = _sim(true)
	for tick: int in 30:
		_step(sim, ShipInput.new())
	if not sim.projectiles.is_empty() or sim.ships[0].energy != sim.ships[0].max_energy:
		return "fired without the trigger held"
	return ""


static func _scripted(tick: int) -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -400), Vector3i(0, 300, 100), false, false, (tick / 25) % 2 == 0)


static func _run(both: bool, seed_value: int) -> int:
	var sim: Sim = _sim(both, seed_value)
	for tick: int in 180:
		_step(sim, _scripted(tick))
	return sim.state_hash()


func test_same_seed_and_inputs_give_the_same_hash() -> String:
	for both: bool in [false, true]:
		var first: int = _run(both, 21)
		var second: int = _run(both, 21)
		if first != second:
			return "both slots %s: hashes %d and %d" % [both, first, second]
	if _run(false, 21) == _run(true, 21):
		return "a second gun firing does not change the hash"
	return ""


## Slot 2's interval is simulation state; two ships that differ only in it
## must not hash alike, or a desync would hide (MP-2).
func test_slot_2_cooldown_joins_the_hash() -> String:
	var ship: ShipState = ShipState.new()
	ship.primary_slots[1] = _weapon(NEEDLE_GUN)
	var ready: int = ship.state_hash()
	ship.fire_cooldowns[1] = 3
	if ship.state_hash() == ready:
		return "slot 2's cooldown does not change the hash"
	return ""


func test_aim_primary_is_the_longest_reaching_filled_slot() -> String:
	var ship: ShipState = ShipState.new()
	if ship.aim_primary() != null:
		return "an unarmed ship aims with a weapon"
	var needle: WeaponDef = _weapon(NEEDLE_GUN)
	var pulse: WeaponDef = _weapon(PULSE_CANNON)
	ship.primary_slots[1] = needle
	if ship.aim_primary() != needle:
		return "slot 2 alone is not the aim weapon"
	ship.primary_slots[0] = pulse
	var want: WeaponDef = pulse if ShipState.range_of(pulse) >= ShipState.range_of(needle) else needle
	if ship.aim_primary() != want:
		return "with both filled the aim weapon is not the one that reaches further"
	var twin: WeaponDef = _weapon(PULSE_CANNON)
	ship.primary_slots[1] = twin
	if ship.aim_primary() != pulse:
		return "on equal range the aim weapon is not slot 1's"
	return ""
