extends RefCounted

## The `room_tones_change` acceptance check (#1399, AUD-1, ARC-1): re-flies
## the step's replay tick by tick and follows the room tones' mix as the game
## does, with the shipped table, from session copies of ship 0 and the
## reactor. It passes when:
##
## - at least two different space tones reach full over the flight;
## - once the reactor is destroyed, the meltdown rumble reaches full, and
##   every space tone is silent, within `MELTDOWN_TICKS_MAX`;
## - no layer's gain moved in one tick by more than the table's fade allows,
##   so no tone jumped.
##
## It also checks the flight with the tones followed ends on the step's pinned
## hash: listening to the mine must not change it. No audio device is needed;
## the check plays nothing.

const CHECK: String = "room_tones_change"
## The meltdown rumble must have taken over within this many ticks of the reactor's end.
const MELTDOWN_TICKS_MAX: int = 90


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var table: RoomToneTable = RoomToneTable.load_file()
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the room tone table was rejected: %s" % table.error]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Dictionary = fly(replay, table)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	measurements["room_tones_spaces"] = (flown["spaces"] as Array).size()
	measurements["room_tones_changes"] = flown["changes"]
	measurements["room_tones_meltdown_ticks"] = flown["meltdown_ticks"]
	measurements["room_tones_pulse_peak"] = flown["pulse_peak"]
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with the room tones followed the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	return judge_flight(flown, largest_step_allowed(table))


## Pass or fail for a flight `fly` returned, as [result, why].
static func judge_flight(flown: Dictionary, step_allowed: float) -> Array:
	var spaces: Array = flown["spaces"]
	if spaces.size() < 2:
		return [AcceptanceReport.RESULT_FAIL, "only %s reached full; at least two space tones should" % [spaces]]
	if not flown["reactor_destroyed"]:
		return [AcceptanceReport.RESULT_FAIL, "the reactor was never destroyed, so no switch to meltdown was heard"]
	var ticks: int = flown["meltdown_ticks"]
	if ticks < 0 or ticks > MELTDOWN_TICKS_MAX:
		return [AcceptanceReport.RESULT_FAIL, "the meltdown rumble took over %d ticks after the reactor; at most %d"
			% [ticks, MELTDOWN_TICKS_MAX]]
	if flown["largest_step"] > step_allowed:
		return [AcceptanceReport.RESULT_FAIL, "a tone jumped %.3f in one tick; a fade moves %.3f at most"
			% [flown["largest_step"], step_allowed]]
	return [AcceptanceReport.RESULT_PASS, "heard %s over %d changes; the meltdown took over in %d ticks; at most %.3f a tick"
		% [spaces, flown["changes"], ticks, flown["largest_step"]]]


## The most a tone's gain may move in one tick: one tick of the table's fade.
static func largest_step_allowed(table: RoomToneTable) -> float:
	return ShipState.TICK_DT / table.fade_seconds + 0.0001


## Flies `replay` with the room tones' mix followed each tick: {"spaces": the
## space tones that reached full, in the order they first did; "changes": how
## many times the bed changed; "reactor_destroyed": whether it was;
## "meltdown_ticks": ticks from the reactor's end until the meltdown rumble was
## full and every space silent (-1 if never); "pulse_peak": the reactor
## pulse's highest gain; "largest_step": the most a gain moved in one tick;
## "hash": the final state hash}, or empty when the replay cannot start.
static func fly(replay: Replay, table: RoomToneTable) -> Dictionary:
	# As `music_check.gd`: `Replay.run` with no frames is the sim before its first tick.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var mix: RoomToneMix = RoomToneMix.new(table)
	var spaces: Array[String] = []
	var heard: Dictionary = {"changes": 0, "destroyed_at": -1, "meltdown_ticks": -1, "pulse_peak": 0.0,
		"largest_step": 0.0}
	var bed: String = ""
	for tick: int in frames.size():
		var inputs: Array[ShipInput] = []
		inputs.assign(frames[tick])
		sim.step(inputs)
		# The mix only reads copies; the pinned hash below shows it changed nothing.
		var reactor: ReactorState = SessionSnapshots.reactor(sim.reactor)
		var before: Dictionary[String, float] = mix.gains.duplicate()
		mix.follow(MusicWiring.mood_of(sim.outcome(), reactor), sim.walls,
			SessionSnapshots.ship(sim.ships[0]).position, reactor, ShipState.TICK_DT)
		_note_tick(heard, spaces, mix, before, tick, reactor)
		if mix.bed != bed:
			if bed != "":
				heard["changes"] += 1
			bed = mix.bed
	heard["spaces"] = spaces
	heard["reactor_destroyed"] = heard["destroyed_at"] >= 0
	heard["hash"] = sim.state_hash()
	return heard


static func _note_tick(heard: Dictionary, spaces: Array[String], mix: RoomToneMix,
		before: Dictionary[String, float], tick: int, reactor: ReactorState) -> void:
	for id: String in mix.gains:
		heard["largest_step"] = maxf(heard["largest_step"], absf(mix.gains[id] - before[id]))
		if mix.table.space_ids.has(id) and mix.gains[id] >= 1.0 and not spaces.has(id):
			spaces.append(id)
	heard["pulse_peak"] = maxf(heard["pulse_peak"], mix.gains.get(RoomToneTable.REACTOR, 0.0))
	if heard["destroyed_at"] < 0 and reactor != null and reactor.destroyed:
		heard["destroyed_at"] = tick
	if heard["destroyed_at"] >= 0 and heard["meltdown_ticks"] < 0 and _meltdown_full(mix):
		heard["meltdown_ticks"] = tick - int(heard["destroyed_at"])


static func _meltdown_full(mix: RoomToneMix) -> bool:
	if mix.gains.get(RoomToneTable.MELTDOWN, 0.0) < 1.0:
		return false
	for id: String in mix.table.space_ids:
		if mix.gains[id] > 0.0:
			return false
	return true
