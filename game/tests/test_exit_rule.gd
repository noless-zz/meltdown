extends RefCounted

## The exit is the entrance (#311, RUN-3, RUN-7, ARC-1, ARC-2): during the
## meltdown a ship that ends a tick inside the exit sphere at its start escapes
## and is out of play; when the countdown runs out a ship still inside is lost;
## before the reactor dies the start is just the start. The outcome joins the
## hash only for levels with a reactor, and replays reproduce it.

const PULSE: String = "res://data/weapons/pulse_cannon.json"
const PINNED_REPLAYS: Array[String] = ["res://tests/replays/basic_flight.replay",
	"res://tests/replays/wall_hit.replay"]
## Five seconds of meltdown, an 8 hull reactor (one pulse shot) and a 3 m exit.
const REACTOR_JSON: String = '{"position": [0, 0, -60], "radius": 2, "hull": 8,' \
	+ ' "meltdown_seconds": 5, "exit_radius": 3}'
const LEVEL_WITHOUT: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []'
const REACTOR_NO_EXIT: String = '{"position": [0, 0, -60], "radius": 2, "hull": 8, "meltdown_seconds": 5}'


func _sim() -> Sim:
	var sim: Sim = Sim.new(311, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	sim.set_reactor(ReactorState.parse_json(REACTOR_JSON))
	return sim


func _input(forward: int, fire: bool = false) -> Array[ShipInput]:
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -forward))
	input.fire_primary = fire
	return [input]


## Steps `ticks` times with `inputs`; returns every event of `kind` seen.
func _run(sim: Sim, inputs: Array[ShipInput], ticks: int, kind: SimEvent.Kind) -> Array[SimEvent]:
	var seen: Array[SimEvent] = []
	for i: int in ticks:
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == kind:
				seen.append(event)
	return seen


## Flies 60 ticks away from the start, then kills the reactor between ticks.
func _out_and_meltdown() -> Sim:
	var sim: Sim = _sim()
	_run(sim, _input(1000), 60, SimEvent.Kind.SHIP_ESCAPED)
	sim.reactor.apply_damage(8.0)
	return sim


func _replay(come_back: bool) -> Replay:
	var replay: Replay = Replay.new(311, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON)
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	for i: int in 60:
		replay.add_tick(_input(1000, i == 0))
	for i: int in 360:
		replay.add_tick(_input(-1000 if come_back else 0))
	return replay


func test_the_level_reads_its_exit_radius_and_hands_it_to_the_reactor() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL_WITHOUT + ', "reactor": ' + REACTOR_NO_EXIT
		+ ', "exit_radius": 6.5}')
	if level.error != "":
		return level.error
	if level.exit_radius_mm != 6500 or level.reactor.exit_radius_mm != 6500:
		return "level %d mm, reactor %d mm" % [level.exit_radius_mm, level.reactor.exit_radius_mm]
	return ""


func test_a_missing_exit_radius_takes_the_default() -> String:
	var default_mm: int = roundi(ExitRule.DEFAULT_RADIUS_M * 1000.0)
	var level: LevelDef = LevelDef.parse_json(LEVEL_WITHOUT + ', "reactor": ' + REACTOR_NO_EXIT + "}")
	if level.error != "":
		return level.error
	if level.exit_radius_mm != default_mm or level.reactor.exit_radius_mm != default_mm:
		return "level %d mm, reactor %d mm" % [level.exit_radius_mm, level.reactor.exit_radius_mm]
	var old_line: ReactorState = ReactorState.parse_json(REACTOR_NO_EXIT)
	if old_line.error != "" or old_line.exit_radius_mm != default_mm:
		return "a reactor line without exit_radius: %s, %d mm" % [old_line.error, old_line.exit_radius_mm]
	return ""


func test_bad_exit_radii_are_rejected_with_the_problem_named() -> String:
	var cases: Dictionary = {
		', "exit_radius": 0}': "exit_radius must be a number above zero",
		', "exit_radius": "big"}': "exit_radius must be a number above zero",
		', "exit_radius": 101}': "exit_radius must be at most 100.0 m",
		', "exit_radius": 0.0001}': "exit_radius must be at least 1 mm",
		', "reactor": ' + REACTOR_JSON + "}":
			"reactor: unknown key \"exit_radius\" (it belongs at the top level)",
	}
	var failures: PackedStringArray = PackedStringArray()
	for tail: String in cases:
		var level: LevelDef = LevelDef.parse_json(LEVEL_WITHOUT + tail)
		if level.error != cases[tail]:
			failures.append("%s: got '%s'" % [tail, level.error])
	return "\n".join(failures)


func test_the_g2_level_names_an_exit_that_holds_the_ship() -> String:
	var level: LevelDef = LevelDef.parse_json(
		FileAccess.get_file_as_string("res://data/levels/g2_level.json"))
	if level.error != "":
		return level.error
	if level.reactor == null or level.reactor.exit_radius() < 1.0:
		return "G2's exit is narrower than the ship"
	return ""


func test_the_exit_radius_survives_the_replay_line() -> String:
	var replay: Replay = _replay(true)
	var read: Replay = Replay.from_text(replay.to_text())
	if read.error != "":
		return read.error
	if read.reactor.exit_radius_mm != 3000:
		return "read back %d mm" % read.reactor.exit_radius_mm
	return ""


func test_the_start_does_nothing_before_the_reactor_dies() -> String:
	var sim: Sim = _sim()
	var escapes: Array[SimEvent] = _run(sim, _input(0), 120, SimEvent.Kind.SHIP_ESCAPED)
	if not escapes.is_empty() or sim.ships[0].escaped:
		return "escaped with the reactor alive"
	if sim.outcome() != ExitRule.Outcome.RUNNING:
		return "outcome %s" % ExitRule.Outcome.keys()[sim.outcome()]
	return ""


func test_flying_back_to_the_start_inside_the_timer_escapes() -> String:
	var sim: Sim = _out_and_meltdown()
	if sim.outcome() != ExitRule.Outcome.RUNNING:
		return "outcome %s before reaching the exit" % ExitRule.Outcome.keys()[sim.outcome()]
	var escapes: Array[SimEvent] = []
	for i: int in 300:
		escapes.append_array(_run(sim, _input(-1000), 1, SimEvent.Kind.SHIP_ESCAPED))
		if not escapes.is_empty():
			break
	if escapes.size() != 1 or escapes[0].ship != 0 or not sim.ships[0].escaped:
		return "escape events %s" % str(escapes)
	if sim.reactor.meltdown_ticks_left <= 0:
		return "escaped after the countdown ended"
	if sim.ships[0].position.length() > 3.0 or escapes[0].vector != sim.ships[0].position:
		return "escaped at %s, outside the 3 m exit" % sim.ships[0].position
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "outcome %s" % ExitRule.Outcome.keys()[sim.outcome()]
	return ""


func test_an_escaped_ship_takes_no_input_no_damage_and_does_not_move() -> String:
	var sim: Sim = _out_and_meltdown()
	sim.ships[0].position = Vector3(0, 0, -1)
	sim.ships[0].velocity = Vector3(0, 0, 5)
	sim.step(_input(0))
	if not sim.ships[0].escaped or sim.ships[0].velocity != Vector3.ZERO:
		return "not escaped and parked: %s" % sim.ships[0].velocity
	var pose: Vector3 = sim.ships[0].position
	var hull: float = sim.ships[0].hull
	sim.projectiles.append(Projectile.new(pose + Vector3(0, 0, -6), Vector3(0, 0, 60),
		Projectile.robot_owner(0), 60, 30.0))
	var events: Array[SimEvent] = []
	for i: int in 400:
		var input: ShipInput = ShipInput.new(Vector3i(1000, 0, -1000), Vector3i(500, 0, 0), true, true, true)
		sim.step([input])
		events.append_array(sim.last_events)
	if sim.ships[0].position != pose or sim.ships[0].hull != hull:
		return "moved to %s or hull %s" % [sim.ships[0].position, sim.ships[0].hull]
	if not events.is_empty():
		return "events after escaping: %s" % str(events)
	if sim.nearest_live_ship(pose) != null:
		return "robots still see the escaped ship"
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "outcome %s once the countdown ended" % ExitRule.Outcome.keys()[sim.outcome()]
	return ""


func test_the_countdown_running_out_loses_the_ship() -> String:
	var sim: Sim = _out_and_meltdown()
	var losses: Array[SimEvent] = _run(sim, _input(0), 299, SimEvent.Kind.SHIP_LOST_IN_MELTDOWN)
	if not losses.is_empty() or sim.outcome() != ExitRule.Outcome.RUNNING:
		return "lost a tick early"
	losses = _run(sim, _input(0), 1, SimEvent.Kind.SHIP_LOST_IN_MELTDOWN)
	if sim.reactor.meltdown_ticks_left != 0:
		return "%d ticks left after 300" % sim.reactor.meltdown_ticks_left
	if losses.size() != 1 or losses[0].ship != 0 or sim.ships[0].hull != 0.0:
		return "losses %s, hull %s" % [str(losses), sim.ships[0].hull]
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "outcome %s" % ExitRule.Outcome.keys()[sim.outcome()]
	losses = _run(sim, _input(-1000), 400, SimEvent.Kind.SHIP_LOST_IN_MELTDOWN)
	var escapes: Array[SimEvent] = _run(sim, _input(-1000), 1, SimEvent.Kind.SHIP_ESCAPED)
	if not losses.is_empty() or not escapes.is_empty() or sim.ships[0].escaped:
		return "a lost ship was lost again or escaped"
	return ""


func test_the_replay_reproduces_the_outcome() -> String:
	var failures: PackedStringArray = PackedStringArray()
	for come_back: bool in [true, false]:
		var replay: Replay = _replay(come_back)
		var first: Sim = replay.run()
		if first == null:
			return replay.run_error
		var expected: ExitRule.Outcome = ExitRule.Outcome.ESCAPED if come_back else ExitRule.Outcome.LOST
		if first.outcome() != expected:
			failures.append("come back %s: outcome %s" % [come_back,
				ExitRule.Outcome.keys()[first.outcome()]])
			continue
		var read: Replay = Replay.from_text(replay.to_text())
		var again: Sim = null if read.error != "" else read.run()
		if again == null or again.outcome() != expected or again.state_hash() != first.state_hash():
			failures.append("come back %s: the replay read back from text ends elsewhere" % come_back)
	return "\n".join(failures)


func test_the_outcome_is_in_the_hash_only_with_a_reactor() -> String:
	var with: Sim = _out_and_meltdown()
	var before: int = with.state_hash()
	with.ships[0].escaped = true
	if with.state_hash() == before:
		return "an escape does not change the hash"
	var without: Sim = Sim.new(311, 1)
	before = without.state_hash()
	without.ships[0].escaped = true
	if without.state_hash() != before:
		return "the escape flag is hashed in a level without a reactor"
	for path: String in PINNED_REPLAYS:
		var replay: Replay = Replay.from_text(FileAccess.get_file_as_string(path))
		var sim: Sim = replay.run()
		if sim == null or replay.expected_hash == Replay.NO_HASH \
				or sim.state_hash() != replay.expected_hash:
			return "%s no longer ends on its pinned hash" % path
	return ""
