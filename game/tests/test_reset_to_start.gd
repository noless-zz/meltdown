extends RefCounted

## The reset-to-start input (#81): a pilot who has left the mine gets back to
## where the run began, through the simulation and nothing else (ARC-3, MP-2).

const AWAY_TICKS: int = 120


func _away() -> ShipInput:
	return ShipInput.new(Vector3i(300, 200, -1000), Vector3i(400, -300, 200), true)


func _reset() -> ShipInput:
	return ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, true)


func _fly(sim: Sim, inputs: Array[ShipInput], ticks: int) -> void:
	for i: int in ticks:
		sim.step(inputs)


func test_input_defaults_to_no_reset() -> String:
	if ShipInput.new().reset_to_start:
		return "a new input asks for a reset"
	if ShipInput.from_floats(Vector3.ONE, Vector3.ONE, true).reset_to_start:
		return "from_floats asks for a reset"
	return ""


func test_reset_returns_to_start_pose_at_rest() -> String:
	var sim: Sim = Sim.new(1, 1)
	_fly(sim, [_away()], AWAY_TICKS)
	var ship: ShipState = sim.ships[0]
	if ship.position == Vector3.ZERO or ship.velocity == Vector3.ZERO:
		return "the ship did not fly away"
	sim.step([_reset()])
	if ship.position != Vector3.ZERO:
		return "position after reset is %s" % ship.position
	if ship.orientation != Basis.IDENTITY:
		return "orientation after reset is %s" % ship.orientation
	if ship.velocity != Vector3.ZERO:
		return "velocity after reset is %s" % ship.velocity
	return ""


func test_reset_keeps_hull_and_energy() -> String:
	var sim: Sim = Sim.new(1, 1)
	_fly(sim, [_away()], AWAY_TICKS)
	var ship: ShipState = sim.ships[0]
	ship.hull = 70.0
	var energy_before: float = ship.energy
	if energy_before >= ship.max_energy:
		return "the afterburner did not drain energy"
	sim.step([_reset()])
	if ship.hull != 70.0:
		return "hull changed to %s" % ship.hull
	# The reset tick still recharges like any tick without the afterburner.
	var expected: float = minf(energy_before + ship.energy_recharge * ShipState.TICK_DT, ship.max_energy)
	if ship.energy != expected:
		return "energy is %s, expected %s" % [ship.energy, expected]
	return ""


func test_reset_happens_before_thrust() -> String:
	var sim: Sim = Sim.new(1, 1)
	_fly(sim, [_away()], AWAY_TICKS)
	var both: ShipInput = ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO, false, true)
	sim.step([both])
	var alone: ShipState = ShipState.new()
	alone.step(Vector3(0.0, 0.0, -1.0), Vector3.ZERO)
	if sim.ships[0].position != alone.position or sim.ships[0].velocity != alone.velocity:
		return "a reset with thrust did not match one tick of thrust from the start"
	return ""


func test_reset_leaves_other_ships_alone() -> String:
	var sim: Sim = Sim.new(1, 2)
	_fly(sim, [_away(), _away()], AWAY_TICKS)
	sim.step([_reset(), _away()])
	var reference: ShipState = ShipState.new()
	for i: int in AWAY_TICKS + 1:
		reference.step(_away().thrust(), _away().turn(), true)
	if sim.ships[1].state_hash() != reference.state_hash():
		return "the second ship was changed by the first ship's reset"
	if sim.ships[0].position != Vector3.ZERO:
		return "the first ship was not reset"
	return ""


func test_set_start_pose_is_used() -> String:
	var sim: Sim = Sim.new(1, 1)
	var start: Vector3 = Vector3(2.0, -1.0, 30.0)
	var facing: Basis = Basis(Vector3.UP, PI / 2.0)
	sim.set_start_pose(0, start, facing)
	if sim.ships[0].position != start:
		return "set_start_pose before the first tick did not place the ship"
	_fly(sim, [_away()], AWAY_TICKS)
	sim.step([_reset()])
	if sim.ships[0].position != start or sim.ships[0].orientation != facing:
		return "reset went to %s, not the set start" % sim.ships[0].position
	return ""


func test_pose_placed_before_first_tick_is_the_start() -> String:
	var sim: Sim = Sim.new(1, 1)
	var start: Vector3 = Vector3(0.0, 1.0, -5.0)
	sim.ships[0].position = start
	_fly(sim, [_away()], AWAY_TICKS)
	sim.step([_reset()])
	if sim.ships[0].position != start:
		return "reset went to %s, not where the ship was placed" % sim.ships[0].position
	return ""


func test_moving_the_ship_after_the_first_tick_does_not_move_the_start() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.step([ShipInput.new()])
	sim.ships[0].position = Vector3(9.0, 9.0, 9.0)
	sim.step([_reset()])
	if sim.ships[0].position != Vector3.ZERO:
		return "the start moved with the ship after the run began"
	return ""


func _recorded() -> Replay:
	var replay: Replay = Replay.new(42, 2)
	for i: int in 90:
		var reset: bool = i == 60
		replay.add_tick([
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 250, 0), i < 30, reset),
			ShipInput.new(Vector3i(500, 0, -1000), Vector3i.ZERO, false, false)])
	return replay


func test_replay_round_trips_reset() -> String:
	var replay: Replay = _recorded()
	var text: String = replay.to_text()
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return "reload failed: %s" % loaded.error
	if loaded.to_text() != text:
		return "text changed on a round trip"
	var frame: Array = loaded.frames[60]
	if not (frame[0] as ShipInput).reset_to_start or (frame[1] as ShipInput).reset_to_start:
		return "the reset flag did not survive the round trip"
	if (loaded.frames[59][0] as ShipInput).reset_to_start:
		return "a tick without a reset loaded as a reset"
	if loaded.run().state_hash() != replay.run().state_hash():
		return "the reloaded replay gave a different hash"
	return ""


func test_same_inputs_give_same_hash() -> String:
	var a: Sim = _recorded().run()
	var b: Sim = _recorded().run()
	if a == null or b == null:
		return "a replay did not run"
	if a.state_hash() != b.state_hash():
		return "two runs of the same inputs disagree"
	var without: Replay = _recorded()
	(without.frames[60][0] as ShipInput).reset_to_start = false
	if without.run().state_hash() == a.state_hash():
		return "the reset did not change the outcome"
	return ""


func test_old_versions_load_without_reset() -> String:
	var v3: Replay = Replay.from_text("meltdown-replay 3\nseed 1\nships 1\ninputs\n0 0 -1000 0 0 0 1\n")
	if v3.error != "":
		return "version 3 failed to load: %s" % v3.error
	if (v3.frames[0][0] as ShipInput).reset_to_start:
		return "version 3 read with a reset"
	return ""


func test_bad_reset_values_are_rejected() -> String:
	var cases: Dictionary[String, String] = {
		"v4 without reset": "meltdown-replay 4\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0\n",
		"v3 with reset": "meltdown-replay 3\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 1\n",
		"reset not 0 or 1": "meltdown-replay 4\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 2\n",
	}
	for name: String in cases:
		if Replay.from_text(cases[name]).error == "":
			return "%s was accepted" % name
	return ""
