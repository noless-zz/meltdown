class_name ReplayInputSource
extends ShipInputSource

## Hands a one-ship replay's recorded inputs to a running session, one per
## tick, in place of the controllers (DEV-6, #165). Indexed by the tick the
## session asks for, so a dropped or doubled frame cannot shift the inputs.

var _replay: Replay
## Ticks asked for beyond the end of the replay; each flew no input.
var overrun_ticks: int = 0


func _init(replay: Replay) -> void:
	_replay = replay


## A fresh session fed by this source, from the replay's own seed, walls,
## tuning, weapons, robots and part catalogue, so it flies exactly the run the replay
## recorded. Every box of a level's walls, its start pose and its reactor are
## taken over, as `LocalSession.for_level` does (#334, #401, #332).
func new_session() -> LocalSession:
	var session: LocalSession = LocalSession.new(_replay.run_seed, self, _replay.bounds(), _replay.tuning,
		_replay.robots, _replay.loadout, _replay.parts)
	if _replay.box_mins_mm.size() > 1:
		session.replay.set_boxes(_replay.box_mins_mm, _replay.box_maxs_mm)
		session.sim.set_walls(session.replay.walls())
	# A level that does not start at the origin facing -z flies a different run
	# from the origin (#401). Without a start line the ship stays at the origin.
	for ship: int in _replay.start_positions_mm:
		session.replay.start_positions_mm[ship] = _replay.start_positions_mm[ship]
		session.replay.start_facings_mm[ship] = _replay.start_facings_mm[ship]
	ReplayStartLine.apply(session.replay, session.sim)
	session.reset_ship_snapshots()
	# A level's reactor stops shots and counts down, so a replay recorded with
	# one flies differently without it (#332).
	if _replay.reactor != null:
		session.replay.reactor = _replay.reactor.fresh_copy()
		session.sim.set_reactor(_replay.reactor.fresh_copy())
	return session


func tick_count() -> int:
	return _replay.frames.size()


func next_input(tick: int) -> ShipInput:
	if tick < 0 or tick >= _replay.frames.size():
		overrun_ticks += 1
		return ShipInput.new()
	var frame: Array = _replay.frames[tick]
	var recorded: ShipInput = frame[0]
	# A copy: the session records what it flew, and must not share the replay's object.
	return LatestInputSource._copy(recorded)
