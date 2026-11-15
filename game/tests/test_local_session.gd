extends RefCounted


## Flies a varying, tick-dependent input so that a replay recorded with the
## wrong input on any tick would end at a different hash.
class ScriptedSource extends ShipInputSource:
	var calls: int = 0

	func next_input(tick: int) -> ShipInput:
		calls += 1
		var turn: int = 300 if (tick / 30) % 2 == 0 else -500
		return ShipInput.new(Vector3i(tick % 7 * 100, -200, -1000), Vector3i(turn, 150, 0))


func _run_frames(session: LocalSession, frame_rate: int, frames: int) -> int:
	var ticks: int = 0
	for i: int in frames:
		ticks += session.advance(1.0 / frame_rate)
	return ticks


func test_one_second_at_90_hz_runs_60_ticks() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	var ticks: int = _run_frames(session, 90, 90)
	if ticks != 60 or session.sim.tick != 60:
		return "expected 60 ticks, ran %d (sim tick %d)" % [ticks, session.sim.tick]
	return ""


func test_one_second_at_72_hz_runs_60_ticks() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	var ticks: int = _run_frames(session, 72, 72)
	if ticks != 60 or session.sim.tick != 60:
		return "expected 60 ticks, ran %d (sim tick %d)" % [ticks, session.sim.tick]
	return ""


func test_many_seconds_at_90_hz_lose_no_tick() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	var ticks: int = _run_frames(session, 90, 90 * 60)
	if ticks != 3600:
		return "a minute at 90 Hz ran %d ticks, expected 3600" % ticks
	if session.dropped_seconds != 0.0:
		return "steady frames dropped %f s" % session.dropped_seconds
	return ""


func test_uneven_frames_sum_to_whole_ticks() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	# 0.5 s in total, split unevenly, each frame short of the tick cap:
	# exactly 30 ticks.
	var pattern: Array[float] = [0.003, 0.021, 0.0117, 0.0, 0.05, 0.0083, 0.07, 0.006]
	var total: float = 0.0
	var ticks: int = 0
	var index: int = 0
	while total + pattern[index % pattern.size()] < 0.5:
		var frame: float = pattern[index % pattern.size()]
		ticks += session.advance(frame)
		total += frame
		index += 1
	ticks += session.advance(0.5 - total)
	if ticks != 30:
		return "0.5 s of uneven frames ran %d ticks, expected 30" % ticks
	if session.sim.tick != 30:
		return "sim tick %d, expected 30" % session.sim.tick
	return ""


func test_partial_tick_waits_for_more_time() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	if session.advance(0.01) != 0:
		return "0.01 s ran a tick"
	if session.advance(0.01) != 1:
		return "0.02 s in total did not run exactly one tick"
	return ""


func test_hitch_runs_capped_ticks_and_reports_dropped_time() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	var ticks: int = session.advance(2.0)
	if ticks != LocalSession.MAX_TICKS_PER_ADVANCE:
		return "a 2 s hitch ran %d ticks, cap is %d" % [ticks, LocalSession.MAX_TICKS_PER_ADVANCE]
	var expected: float = 2.0 - LocalSession.MAX_TICKS_PER_ADVANCE * ShipState.TICK_DT
	if absf(session.dropped_seconds - expected) > 1.0e-6:
		return "dropped %f s, expected %f s" % [session.dropped_seconds, expected]
	# The next normal frame must not catch up on the dropped time.
	if session.advance(1.0 / 60.0) != 1:
		return "the frame after the hitch did not run exactly one tick"
	return ""


func test_interpolation_fraction_stays_in_range() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	var frames: Array[float] = [0.004, 0.011, 1.0 / 90.0, 0.03, 0.0, 2.5, 0.0166, 0.001, -0.5, NAN]
	for frame: float in frames:
		session.advance(frame)
		var f: float = session.interpolation_fraction
		if not (f >= 0.0 and f <= 1.0):
			return "fraction %f after a frame of %f s" % [f, frame]
	session = LocalSession.new(1, ScriptedSource.new())
	session.advance(ShipState.TICK_DT * 1.5)
	if absf(session.interpolation_fraction - 0.5) > 1.0e-6:
		return "1.5 ticks of time left fraction %f, expected 0.5" % session.interpolation_fraction
	return ""


func test_bad_frame_times_run_nothing() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	if session.advance(-1.0) != 0 or session.advance(NAN) != 0 or session.advance(INF) != 0:
		return "a negative or non-finite frame time ran a tick"
	if session.advance(1.0 / 60.0) != 1:
		return "a bad frame time poisoned the accumulator"
	return ""


func test_one_input_is_read_per_tick() -> String:
	var source: ScriptedSource = ScriptedSource.new()
	var session: LocalSession = LocalSession.new(1, source)
	_run_frames(session, 90, 45)
	if source.calls != 30 or session.replay.frames.size() != 30:
		return "30 ticks read %d inputs and recorded %d" % [source.calls, session.replay.frames.size()]
	return ""


func test_previous_and_current_ship_follow_the_ticks() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	_run_frames(session, 60, 10)
	var before: ShipState = session.current_ship()
	session.advance(1.0 / 60.0)
	if session.previous_ship() != before:
		return "previous ship is not the state of the tick before"
	if session.current_ship().state_hash() != session.sim.ships[0].state_hash():
		return "current ship does not match the simulation"
	if session.previous_ship().position == session.current_ship().position:
		return "previous and current ship are the same pose while moving"
	return ""


func test_exposed_ships_are_copies() -> String:
	var session: LocalSession = LocalSession.new(1, ScriptedSource.new())
	_run_frames(session, 60, 5)
	var hash_before: int = session.sim.state_hash()
	session.current_ship().position = Vector3(99.0, 99.0, 99.0)
	session.previous_ship().velocity = Vector3(5.0, 5.0, 5.0)
	if session.sim.state_hash() != hash_before:
		return "writing to the exposed ship changed the simulation"
	return ""


func test_recorded_replay_reproduces_live_hash() -> String:
	var session: LocalSession = LocalSession.new(20261115, ScriptedSource.new())
	var frames: Array[float] = [1.0 / 90.0, 1.0 / 72.0, 0.002, 0.05, 1.5, 0.013]
	for i: int in 200:
		session.advance(frames[i % frames.size()])
	var replayed: Sim = session.replay.run()
	if replayed == null:
		return "replay did not run: %s" % session.replay.run_error
	if replayed.tick != session.sim.tick:
		return "replay ran %d ticks, live ran %d" % [replayed.tick, session.sim.tick]
	if replayed.state_hash() != session.sim.state_hash():
		return "replay hash differs from the live session"
	# Also through the text format, as a saved replay would be.
	var reloaded: Replay = Replay.from_text(session.replay.to_text())
	var from_text: Sim = reloaded.run()
	if from_text == null or from_text.state_hash() != session.sim.state_hash():
		return "the saved replay does not reproduce the live hash"
	return ""
