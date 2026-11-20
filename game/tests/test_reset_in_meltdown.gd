extends RefCounted

## Reset to start does nothing during the meltdown (#354, RUN-3, ARC-1, ARC-2):
## the start is the exit then, so a reset would be an instant escape instead of
## the flight back. Before the reactor dies, after the countdown, and in levels
## without a reactor, reset works as before; the rest of the tick's input still
## applies; replays reproduce it.

const PULSE: String = "res://data/weapons/pulse_cannon.json"
## Five seconds of meltdown, an 8 hull reactor (one pulse shot) and a 3 m exit,
## as in `test_exit_rule.gd`.
const REACTOR_JSON: String = '{"position": [0, 0, -60], "radius": 2, "hull": 8,' \
	+ ' "meltdown_seconds": 5, "exit_radius": 3}'
const AWAY_TICKS: int = 60


func _sim(with_reactor: bool = true) -> Sim:
	var sim: Sim = Sim.new(354, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	if with_reactor:
		sim.set_reactor(ReactorState.parse_json(REACTOR_JSON))
	return sim


func _forward(speed: int, reset: bool = false) -> Array[ShipInput]:
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -speed), Vector3i(0, 200, 0), false, reset)
	return [input]


func _reset_only() -> Array[ShipInput]:
	var input: ShipInput = ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, true)
	return [input]


func _fly(sim: Sim, inputs: Array[ShipInput], ticks: int) -> void:
	for i: int in ticks:
		sim.step(inputs)


## Flies away from the start, then kills the reactor between ticks.
func _away_in_meltdown() -> Sim:
	var sim: Sim = _sim()
	_fly(sim, _forward(1000), AWAY_TICKS)
	sim.reactor.apply_damage(8.0)
	return sim


func _at_start(sim: Sim) -> bool:
	var ship: ShipState = sim.ships[0]
	return ship.position == sim.start_positions[0] and ship.velocity == Vector3.ZERO \
		and ship.orientation == sim.start_orientations[0]


func test_reset_works_before_the_reactor_dies() -> String:
	var sim: Sim = _sim()
	_fly(sim, _forward(1000), AWAY_TICKS)
	sim.step(_reset_only())
	if not _at_start(sim):
		return "the ship is at %s, not its start" % sim.ships[0].position
	if sim.reactor.destroyed:
		return "the reactor died during the test"
	return ""


func test_reset_is_ignored_during_the_countdown_and_the_rest_applies() -> String:
	var sim: Sim = _away_in_meltdown()
	var twin: Sim = _away_in_meltdown()
	var before: Vector3 = sim.ships[0].position
	var velocity_before: Vector3 = sim.ships[0].velocity
	sim.step(_forward(-1000, true))
	twin.step(_forward(-1000))
	var ship: ShipState = sim.ships[0]
	if ship.position != twin.ships[0].position or ship.velocity != twin.ships[0].velocity \
			or ship.orientation != twin.ships[0].orientation:
		return "the reset changed the ship: %s against %s" % [ship.position, twin.ships[0].position]
	if sim.state_hash() != twin.state_hash():
		return "the reset changed the state hash"
	if ship.position.distance_to(sim.start_positions[0]) < 10.0:
		return "the ship is back near its start at %s" % ship.position
	if ship.velocity == velocity_before or ship.position == before:
		return "the thrust and turn of the reset tick were not applied"
	if sim.reactor.meltdown_ticks_left <= 0:
		return "the countdown was not running"
	return ""


func test_a_ship_cannot_escape_on_the_tick_it_asks_for_a_reset() -> String:
	var sim: Sim = _away_in_meltdown()
	sim.step(_reset_only())
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.SHIP_ESCAPED:
			return "the ship escaped on its reset tick"
	if sim.ships[0].escaped or sim.outcome() != ExitRule.Outcome.RUNNING:
		return "outcome %s after a reset" % ExitRule.Outcome.keys()[sim.outcome()]
	return ""


func test_reset_works_again_after_the_countdown_ends() -> String:
	var sim: Sim = _sim()
	_fly(sim, _forward(1000), AWAY_TICKS)
	sim.reactor.apply_damage(8.0)
	sim.reactor.meltdown_ticks_left = 0
	if not ShipReset.allowed(sim.reactor):
		return "a finished countdown still refuses the reset"
	var outside: Sim = _away_in_meltdown()
	if ShipReset.allowed(outside.reactor):
		return "a running countdown allows the reset"
	return ""


func test_a_level_without_a_reactor_still_resets() -> String:
	var sim: Sim = _sim(false)
	_fly(sim, _forward(1000), AWAY_TICKS)
	if sim.ships[0].position == sim.start_positions[0]:
		return "the ship did not fly away"
	sim.step(_reset_only())
	if not _at_start(sim):
		return "the ship is at %s, not its start" % sim.ships[0].position
	return ""


func test_m1_and_m2_suite_replays_end_on_their_pinned_hashes() -> String:
	var failures: PackedStringArray = PackedStringArray()
	for suite_name: String in ["m1", "m2"]:
		var loaded: Array[AcceptanceSuite] = AcceptanceSuite.load_named(suite_name)
		if loaded.size() != 1 or loaded[0].error != "" or loaded[0].steps.is_empty():
			return "suite %s did not load" % suite_name
		var suite: AcceptanceSuite = loaded[0]
		for step: AcceptanceStep in suite.steps:
			if step.replay_path == "":
				continue  # A headset-only step such as m1's refresh_rate (#598) flies nothing.
			if not step.has_check(AcceptanceStep.CHECK_FINAL_HASH):
				continue  # m1's frame_budget flight (#643) is timed on the headset, not pinned.
			var replay: Replay = Replay.from_text(FileAccess.get_file_as_string(step.replay_path))
			var sim: Sim = null if replay.error != "" else replay.run()
			if sim == null:
				failures.append("%s did not run: %s %s" % [step.id, replay.error, replay.run_error])
			elif sim.state_hash() != step.expected_hash:
				failures.append("%s ends on %d, pinned %d" % [step.id, sim.state_hash(), step.expected_hash])
	return "\n".join(failures)


## Fires at the reactor on the way out, waits, then asks for a reset while the
## countdown runs.
func _recorded() -> Replay:
	var replay: Replay = Replay.new(354, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON)
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	for i: int in AWAY_TICKS:
		var input: ShipInput = ShipInput.new(Vector3i(0, 0, -1000))
		input.fire_primary = i == 0
		replay.add_tick([input])
	for i: int in 90:
		replay.add_tick([ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, i == 60)])
	return replay


func test_a_replay_with_a_reset_in_the_countdown_reproduces_its_hash_from_text() -> String:
	var replay: Replay = _recorded()
	var first: Sim = replay.run()
	if first == null:
		return replay.run_error
	if not first.reactor.destroyed or first.reactor.meltdown_ticks_left <= 0:
		return "the replay did not end inside the countdown"
	if first.ships[0].position.distance_to(first.start_positions[0]) < 10.0 or first.ships[0].escaped:
		return "the reset in the countdown took the ship home"
	var read: Replay = Replay.from_text(replay.to_text())
	if read.error != "":
		return read.error
	var again: Sim = read.run()
	if again == null or again.state_hash() != first.state_hash():
		return "the replay read back from text ends elsewhere"
	if not (read.frames[AWAY_TICKS + 60][0] as ShipInput).reset_to_start:
		return "the reset flag was lost from the text"
	return ""
