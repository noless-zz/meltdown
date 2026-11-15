extends RefCounted


func _forward() -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO)


func test_sim_owns_one_ship_state_per_ship() -> String:
	var sim: Sim = Sim.new(7, 3)
	if sim.ships.size() != 3:
		return "expected 3 ships, got %d" % sim.ships.size()
	if sim.ships[0] == sim.ships[1]:
		return "ships share one state object"
	return ""


func test_step_advances_each_ship_by_its_own_input() -> String:
	var sim: Sim = Sim.new(7, 2)
	var idle: ShipInput = ShipInput.new()
	for i: int in 60:
		if not sim.step([_forward(), idle]):
			return "step refused a valid input list"
	if sim.tick != 60:
		return "expected tick 60, got %d" % sim.tick
	if sim.ships[0].position.z >= 0.0:
		return "ship 0 did not move forward"
	if sim.ships[1].position != Vector3.ZERO:
		return "ship 1 moved without input"
	return ""


func test_step_matches_ship_state_step() -> String:
	var sim: Sim = Sim.new(0, 1)
	var alone: ShipState = ShipState.new()
	var input: ShipInput = ShipInput.new(Vector3i(300, -200, -1000), Vector3i(400, -700, 200))
	for i: int in 120:
		sim.step([input])
		alone.step(Vector3(0.3, -0.2, -1.0), Vector3(0.4, -0.7, 0.2))
	if sim.ships[0].state_hash() != alone.state_hash():
		return "Sim.step and ShipState.step disagree"
	return ""


func test_step_rejects_wrong_input_count() -> String:
	var sim: Sim = Sim.new(7, 2)
	var before: int = sim.state_hash()
	if sim.step([_forward()]):
		return "step accepted one input for two ships"
	if sim.state_hash() != before or sim.tick != 0:
		return "a rejected step changed the state"
	return ""


func test_hash_depends_on_seed_and_tick() -> String:
	if Sim.new(1, 1).state_hash() == Sim.new(2, 1).state_hash():
		return "different seeds gave the same hash"
	var sim: Sim = Sim.new(1, 1)
	var before: int = sim.state_hash()
	sim.step([ShipInput.new()])
	if sim.state_hash() == before:
		return "an idle tick did not change the hash"
	return ""


func test_input_from_floats_rounds_to_thousandths() -> String:
	var input: ShipInput = ShipInput.from_floats(Vector3(0.25049, -1.0, 0.0), Vector3(0.0, 1.5708, -0.0004))
	if input.thrust_q != Vector3i(250, -1000, 0):
		return "thrust rounded to %s" % input.thrust_q
	if input.turn_q != Vector3i(0, 1571, 0):
		return "turn rounded to %s" % input.turn_q
	if not input.thrust().is_equal_approx(Vector3(0.25, -1.0, 0.0)):
		return "thrust() returned %s" % input.thrust()
	return ""
