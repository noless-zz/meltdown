extends RefCounted

## Ships flown beside the local one (#1354, PRF-8, MP-2, ARC-2, DEV-6): a
## session flies a replay's other ships from their own sources with no
## network, records what it flew so the replay runs to the same hash, and hands
## the view copies only. A replay of several ships flies them all through
## `ReplayInputSource`, as the acceptance runner flies it.

const TICKS: int = 120
const SEED: int = 1354
const STRESS_TICKS: int = 300


class ForwardSource extends ShipInputSource:
	var _turn: int = 0

	func _init(turn: int) -> void:
		_turn = turn

	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -800), Vector3i(0, _turn, 0))


## A three-ship header in a box, the others starting beside ship 0.
static func _header() -> Replay:
	var header: Replay = Replay.new(SEED, 3)
	header.set_box(Vector3i(-50000, -50000, -50000), Vector3i(50000, 50000, 50000))
	header.set_start_pose(1, Vector3(-5, 0, 0), Vector3(0, 0, -1))
	header.set_start_pose(2, Vector3(5, 0, 0), Vector3(1, 0, -1))
	return header


static func _others() -> Array[ShipInputSource]:
	return [ForwardSource.new(200), ForwardSource.new(-300)] as Array[ShipInputSource]


static func _flown() -> LocalSession:
	var session: LocalSession = LocalSession.new(SEED, ForwardSource.new(0))
	var problem: String = session.fly_ships(_header(), _others())
	if problem != "":
		push_error(problem)
	for tick: int in TICKS:
		session.advance(ShipState.TICK_DT)
	return session


func test_the_session_flies_every_ship_from_its_own_source() -> String:
	var session: LocalSession = _flown()
	if session.sim.ships.size() != 3 or session.other_ships == null or session.other_ships.count() != 2:
		return "%d ships simulated" % session.sim.ships.size()
	var starts: Array[Vector3] = [Vector3.ZERO, Vector3(-5, 0, 0), Vector3(5, 0, 0)]
	for index: int in 3:
		var ship: ShipState = session.sim.ships[index]
		if ship.position.distance_to(starts[index]) < 1.0:
			return "ship %d never left its start" % index
	if session.sim.ships[1].orientation.is_equal_approx(session.sim.ships[2].orientation):
		return "ships 1 and 2 turned alike; each should fly its own source"
	return ""


func test_the_recorded_replay_runs_to_the_live_hash() -> String:
	var session: LocalSession = _flown()
	var replay: Replay = session.replay
	if replay.ship_count != 3 or replay.frames.size() != TICKS:
		return "the replay holds %d ships and %d ticks" % [replay.ship_count, replay.frames.size()]
	var rerun: Sim = Replay.from_text(replay.to_text()).run()
	if rerun == null or rerun.state_hash() != session.sim.state_hash():
		return "the replay runs to another hash than the live session"
	return ""


func test_the_view_gets_copies_before_and_after_the_latest_tick() -> String:
	var session: LocalSession = _flown()
	var before: Array[ShipState] = session.previous_others()
	var after: Array[ShipState] = session.current_others()
	if before.size() != 2 or after.size() != 2:
		return "%d and %d other ships handed over" % [before.size(), after.size()]
	for index: int in 2:
		var ship: ShipState = session.sim.ships[index + 1]
		if after[index] == ship or not after[index].position.is_equal_approx(ship.position):
			return "ship %d's copy is the simulation's own or not where it is" % (index + 1)
		if before[index].position.is_equal_approx(after[index].position):
			return "ship %d's previous copy is the latest one" % (index + 1)
	var hash_before: int = session.sim.state_hash()
	after[0].position = Vector3(999, 999, 999)
	after.clear()
	if session.sim.state_hash() != hash_before or session.current_others().size() != 2:
		return "writing a copy changed the simulation"
	return ""


func test_a_one_ship_session_hands_no_other_ships() -> String:
	var session: LocalSession = LocalSession.new(SEED, ForwardSource.new(0))
	session.advance(ShipState.TICK_DT)
	if session.other_ships != null or not session.current_others().is_empty() \
			or not session.previous_others().is_empty():
		return "a one-ship session lists other ships"
	# The main scene hands these to the view every frame, typed as it takes them.
	var view: OtherShipsView = OtherShipsView.new()
	view.show_ships(session.previous_others(), session.current_others(), 0.5)
	var shown: int = view.shown()
	view.free()
	return "" if shown == 0 else "%d ships drawn for a one-ship session" % shown


func test_a_header_with_ticks_or_the_wrong_sources_is_refused() -> String:
	var session: LocalSession = LocalSession.new(SEED, ForwardSource.new(0))
	var one: Array[ShipInputSource] = [ForwardSource.new(0)]
	if session.fly_ships(_header(), one) == "":
		return "two sources for three ships were taken"
	var ticked: Replay = _header()
	ticked.add_tick([ShipInput.new(), ShipInput.new(), ShipInput.new()] as Array[ShipInput])
	if session.fly_ships(ticked, _others()) == "":
		return "a header with a tick was taken"
	if session.other_ships != null or session.sim.ships.size() != 1:
		return "a refused header changed the session"
	return ""


func test_a_several_ship_replay_flies_all_its_ships_to_its_hash() -> String:
	var replay: Replay = StressScene.load_file().replay(STRESS_TICKS)
	var expected: int = replay.run().state_hash()
	var source: ReplayInputSource = ReplayInputSource.new(Replay.from_text(replay.to_text()))
	var session: LocalSession = source.new_session()
	if session.sim.ships.size() != 4 or session.sim.tick != 0:
		return "the source's session flies %d ships from tick %d" % [session.sim.ships.size(), session.sim.tick]
	while session.sim.tick < source.tick_count():
		session.advance(ShipState.TICK_DT)
	if session.sim.state_hash() != expected:
		return "flown through the source: hash %d, the replay runs to %d" % [session.sim.state_hash(), expected]
	if source.overrun_ticks != 0:
		return "the source flew %d ticks past its end" % source.overrun_ticks
	return ""


func test_only_a_plain_replay_step_flies_several_ships() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	if not AcceptanceStepLevel.flies_ships(step):
		return "a plain replay step may not fly several ships"
	step.level_seed = 29
	if AcceptanceStepLevel.flies_ships(step):
		return "a seed step may fly several ships"
	step.level_seed = AcceptanceStep.NO_SEED
	step.controls_path = "res://acceptance/replays/any.controls.json"
	if AcceptanceStepLevel.flies_ships(step):
		return "a controls step may fly several ships"
	return ""
