class_name ReplayInputSource
extends ShipInputSource

## Hands a one-ship replay's recorded inputs to a running session, one per
## tick, in place of the controllers (DEV-6, #165). Indexed by the tick the
## session asks for, so a dropped or doubled frame cannot shift the inputs.
## A looping source (#788, PRF-3) starts again from the replay's first input
## each time the ticks pass its end, so a short flight can fill a long soak.

var _replay: Replay
var _looping: bool = false
## Ticks asked for beyond the end of the replay; each flew no input.
var overrun_ticks: int = 0


func _init(replay: Replay, looping: bool = false) -> void:
	_replay = replay
	_looping = looping


## A fresh session fed by this source, from the replay's own seed, walls,
## tuning, weapons, robots, part catalogue and look-aim values, so it flies exactly the run the replay
## recorded. Every box of a level's walls, its start pose and its reactor are
## taken over, as `LocalSession.for_level` does (#334, #401, #332), and so is
## its debris (#456).
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
	session.use_salvage_rules(_replay.salvage_rules)
	# A replay that aims off the nose turns its guns by these values (CMB-6).
	if _replay.look_aim != null and session.sim.set_look_aim(_replay.look_aim) == "":
		session.replay.look_aim = _replay.look_aim
	session.reset_ship_snapshots()
	# A level's reactor stops shots and counts down, so a replay recorded with
	# one flies differently without it (#332).
	if _replay.reactor != null:
		session.replay.reactor = _replay.reactor.fresh_copy()
		session.sim.set_reactor(_replay.reactor.fresh_copy())
	# Debris that falls in the meltdown bounces the ship and stops shots, so a
	# replay recorded with it misses its hash without it (RUN-4, #456). Separate
	# copies, as in `for_level`, so the live run never moves the recorded one.
	if _replay.debris != null and _replay.debris.size() > 0:
		session.replay.debris = _replay.debris.fresh_copy()
		session.sim.set_debris(_replay.debris.fresh_copy())
	# A run level's component drops and miner rescue (#1028).
	if _replay.component_rules != null and session.sim.set_component_rules(_replay.component_rules) == "":
		session.replay.component_rules = _replay.component_rules
	if _replay.rescue_rules != null and session.sim.set_rescue_rules(_replay.rescue_rules, _replay.miners) == "":
		session.replay.rescue_rules = _replay.rescue_rules
		session.replay.miners = _replay.miners.duplicate()
	return session


func tick_count() -> int:
	return _replay.frames.size()


## Called by the acceptance runner when the step's flight ends; a source
## that changed something for the flight puts it back (#818).
func finish() -> void:
	pass


func next_input(tick: int) -> ShipInput:
	if _looping and tick >= 0 and not _replay.frames.is_empty():
		tick = tick % _replay.frames.size()
	if tick < 0 or tick >= _replay.frames.size():
		overrun_ticks += 1
		return ShipInput.new()
	var frame: Array = _replay.frames[tick]
	var recorded: ShipInput = frame[0]
	# A copy: the session records what it flew, and must not share the replay's object.
	return LatestInputSource._copy(recorded)
