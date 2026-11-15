extends RefCounted

## Shields that recharge from energy and permanent hull damage (CMB-2, #69).

const DT: float = ShipState.TICK_DT


func _idle() -> ShipInput:
	return ShipInput.new()


func test_damage_below_shield_leaves_hull_untouched() -> String:
	var ship: ShipState = ShipState.new()
	ship.apply_damage(30.0)
	if ship.hull != ship.max_hull:
		return "hull %f after 30 damage against a %f shield" % [ship.hull, ship.max_shield]
	if ship.shield != ship.max_shield - 30.0:
		return "shield %f, expected %f" % [ship.shield, ship.max_shield - 30.0]
	return ""


func test_damage_above_shield_reduces_hull_by_the_excess() -> String:
	var ship: ShipState = ShipState.new()
	ship.shield = 20.0
	ship.apply_damage(35.0)
	if ship.shield != 0.0:
		return "shield %f, expected 0" % ship.shield
	if ship.hull != ship.max_hull - 15.0:
		return "hull %f, expected %f" % [ship.hull, ship.max_hull - 15.0]
	return ""


func test_damage_never_drops_below_zero_or_repairs() -> String:
	var ship: ShipState = ShipState.new()
	ship.apply_damage(1000.0)
	if ship.shield != 0.0 or ship.hull != 0.0:
		return "shield %f, hull %f after overkill" % [ship.shield, ship.hull]
	ship.apply_damage(-50.0)
	if ship.shield != 0.0 or ship.hull != 0.0:
		return "negative damage repaired the ship"
	return ""


func test_wall_hit_goes_through_the_shield_first() -> String:
	var ship: ShipState = ShipState.new()
	ship.shield = 4.0
	ship.take_wall_hit(20.0)
	var dealt: float = 20.0 * ship.wall_damage_per_speed
	if ship.shield != 0.0 or not is_equal_approx(ship.hull, ship.max_hull - (dealt - 4.0)):
		return "shield %f, hull %f after a %f hit on a 4 point shield" % [ship.shield, ship.hull, dealt]
	return ""


func test_shield_recharges_and_drains_energy() -> String:
	var ship: ShipState = ShipState.new()
	ship.shield = 40.0
	ship.energy = 50.0
	ship.step(Vector3.ZERO, Vector3.ZERO)
	var gained: float = ship.shield_recharge * DT
	if not is_equal_approx(ship.shield, 40.0 + gained):
		return "shield %f, expected %f" % [ship.shield, 40.0 + gained]
	var expected: float = 50.0 + ship.energy_recharge * DT - gained * ship.shield_energy_cost
	if not is_equal_approx(ship.energy, expected):
		return "energy %f, expected %f" % [ship.energy, expected]
	return ""


func test_full_shield_costs_no_energy() -> String:
	var ship: ShipState = ShipState.new()
	ship.energy = 50.0
	ship.step(Vector3.ZERO, Vector3.ZERO)
	if not is_equal_approx(ship.energy, 50.0 + ship.energy_recharge * DT):
		return "a full shield spent energy: %f" % ship.energy
	if ship.shield != ship.max_shield:
		return "shield moved past its maximum: %f" % ship.shield
	return ""


func test_shield_stops_at_its_maximum() -> String:
	var ship: ShipState = ShipState.new()
	ship.shield = ship.max_shield - 0.01
	ship.energy = 50.0
	ship.step(Vector3.ZERO, Vector3.ZERO)
	if ship.shield != ship.max_shield:
		return "shield %f, expected %f" % [ship.shield, ship.max_shield]
	var expected: float = 50.0 + ship.energy_recharge * DT - 0.01 * ship.shield_energy_cost
	if not is_equal_approx(ship.energy, expected):
		return "topping up 0.01 cost %f energy" % (50.0 + ship.energy_recharge * DT - ship.energy)
	return ""


func test_empty_energy_stops_recharge() -> String:
	var ship: ShipState = ShipState.new()
	ship.energy_recharge = 0.0
	ship.energy = 0.0
	ship.shield = 10.0
	for tick: int in 60:
		ship.step(Vector3.ZERO, Vector3.ZERO)
	if ship.shield != 10.0 or ship.energy != 0.0:
		return "shield %f, energy %f with an empty pool" % [ship.shield, ship.energy]
	return ""


func test_recharge_spends_only_the_energy_there_is() -> String:
	var ship: ShipState = ShipState.new()
	ship.energy_recharge = 0.0
	ship.shield_energy_cost = 2.0
	ship.energy = 0.02
	ship.shield = 10.0
	ship.step(Vector3.ZERO, Vector3.ZERO)
	if ship.energy != 0.0 or not is_equal_approx(ship.shield, 10.01):
		return "shield %f, energy %f; expected 10.01 and 0" % [ship.shield, ship.energy]
	return ""


## Within a tick the afterburner draws first and the shield gets what is left.
func test_afterburner_draws_before_the_shield() -> String:
	var boost_cost: float = ShipState.new().afterburner_drain * DT
	var ship: ShipState = ShipState.new()
	ship.energy = boost_cost
	ship.shield = 10.0
	ship.step(Vector3(0.0, 0.0, -1.0), Vector3.ZERO, true)
	if not ship.afterburner_active:
		return "the afterburner lost its tick to the shield"
	if ship.energy != 0.0 or ship.shield != 10.0:
		return "shield %f, energy %f; the shield should get nothing" % [ship.shield, ship.energy]
	var rest: ShipState = ShipState.new()
	rest.energy = boost_cost * 2.0
	rest.shield = 10.0
	rest.step(Vector3(0.0, 0.0, -1.0), Vector3.ZERO, true)
	if not rest.afterburner_active or rest.shield <= 10.0:
		return "the shield did not get the energy left after the boost"
	if not is_equal_approx(rest.energy, boost_cost - rest.shield_recharge * DT * rest.shield_energy_cost):
		return "energy %f after boost and shield" % rest.energy
	return ""


func test_hull_stays_reduced_over_600_ticks() -> String:
	var sim: Sim = Sim.new(5, 1)
	var ship: ShipState = sim.ships[0]
	ship.apply_damage(ship.max_shield + 20.0)
	var hull_after: float = ship.hull
	for tick: int in 600:
		var inputs: Array[ShipInput] = [_idle()]
		sim.step(inputs)
		if ship.hull != hull_after:
			return "tick %d: hull changed from %f to %f" % [tick, hull_after, ship.hull]
	if ship.shield <= 0.0:
		return "the shield did not recharge in 600 ticks"
	return ""


func test_shield_is_part_of_the_hash() -> String:
	var ship: ShipState = ShipState.new()
	var before: int = ship.state_hash()
	ship.shield -= 1.0
	if ship.state_hash() == before:
		return "losing shield did not change the hash"
	return ""


## A full shield leaves the hash as it was before shields existed, so
## replays that never take damage keep their recorded hashes.
func test_full_shield_keeps_the_old_hash() -> String:
	var ship: ShipState = ShipState.new()
	var old: int = hash([ship.position, ship.velocity, ship.orientation, ship.energy,
		ship.afterburner_locked])
	if ship.state_hash() != old:
		return "a full shield changed the hash"
	return ""


func _damaged_flight() -> Sim:
	var sim: Sim = Sim.new(17, 2, BoxBounds.new(Vector3(-5.0, -5.0, -40.0), Vector3(5.0, 5.0, 5.0)))
	for tick: int in 600:
		var inputs: Array[ShipInput] = [
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO, tick % 90 < 30),
			ShipInput.new(Vector3i(600, -300, -900), Vector3i(0, 200, 0), tick % 50 < 10)]
		sim.step(inputs)
	return sim


func test_same_inputs_give_the_same_shield_and_hash() -> String:
	var first: Sim = _damaged_flight()
	var second: Sim = _damaged_flight()
	if first.state_hash() != second.state_hash():
		return "two identical runs gave different hashes"
	for i: int in first.ships.size():
		if first.ships[i].shield != second.ships[i].shield or first.ships[i].hull != second.ships[i].hull:
			return "ship %d: shield or hull differ between identical runs" % i
	return ""


func test_tuning_fills_the_shield() -> String:
	var tuning: ShipTuning = ShipTuning.new()
	tuning.max_shield = 80.0
	tuning.shield_recharge = 7.0
	tuning.shield_energy_cost = 0.5
	var ship: ShipState = ShipState.new()
	ship.shield = 3.0
	tuning.apply_to(ship)
	if ship.max_shield != 80.0 or ship.shield != 80.0:
		return "shield %f of %f after apply_to" % [ship.shield, ship.max_shield]
	if ship.shield_recharge != 7.0 or ship.shield_energy_cost != 0.5:
		return "recharge or cost not applied"
	return ""
