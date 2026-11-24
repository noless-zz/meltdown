extends RefCounted

## The `music_follows_alarm` acceptance check (#1303, AUD-3, RUN-2, ARC-1):
## re-flies the step's replay tick by tick and follows the music's mix as the
## game does, with the shipped table and no audio device. It passes when:
##
## - the moments the step expects happen in their order (others may come in
##   between): a layer's id when it first reaches full, `faded` when an end
##   screen has faded every layer out. The expected moments are data, by step
##   id, in `music.json` beside this file;
## - once the reactor is destroyed, the meltdown track is full and every other
##   layer silent within one second;
## - no layer's gain moved in one tick by more than its quickest fade allows,
##   so nothing was cut;
## - the flight with the music followed ends on the step's pinned hash.

const CHECK: String = "music_follows_alarm"
## Its moment order and expected-file reading are the sound cues' (#1290).
const CUES_CHECK: GDScript = preload("res://acceptance/checks/sound_cues_check.gd")
const EXPECTED_FILE: String = "res://acceptance/checks/music.json"
const FADED: String = "faded"
## The meltdown switch must be complete within this many ticks of the reactor's end.
const MELTDOWN_TICKS_MAX: int = 60


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var expected: Array[String] = expected_for(step.id)
	if expected.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "%s lists no moments for step %s" % [EXPECTED_FILE, step.id]]
	var table: MusicTable = MusicTable.load_file()
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the music table was rejected: %s" % table.error]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Dictionary = fly(replay, table)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	measurements["music_moments"] = flown["moments"].size()
	measurements["music_meltdown_ticks"] = flown["meltdown_ticks"]
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with the music followed the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	return judge_flight(flown, expected, largest_step_allowed(table))


## Pass or fail for a flight `fly` returned, as [result, why].
static func judge_flight(flown: Dictionary, expected: Array[String], step_allowed: float) -> Array:
	var moments: Array[String] = flown["moments"]
	var missing: String = CUES_CHECK.first_missing(moments, expected)
	if missing != "":
		return [AcceptanceReport.RESULT_FAIL, "%s did not follow the moments before it in %s; heard %s"
			% [missing, expected, moments]]
	if flown["reactor_destroyed"]:
		var ticks: int = flown["meltdown_ticks"]
		if ticks < 0 or ticks > MELTDOWN_TICKS_MAX:
			return [AcceptanceReport.RESULT_FAIL, "the meltdown track took over %d ticks after the reactor; at most %d"
				% [ticks, MELTDOWN_TICKS_MAX]]
	if flown["largest_step"] > step_allowed:
		return [AcceptanceReport.RESULT_FAIL, "a layer jumped %.3f in one tick; a fade moves %.3f at most"
			% [flown["largest_step"], step_allowed]]
	return [AcceptanceReport.RESULT_PASS, "heard %s; the meltdown took over in %d ticks; at most %.3f a tick"
		% [moments, flown["meltdown_ticks"], flown["largest_step"]]]


## The most a layer's gain may move in one tick: one tick of the quickest fade.
static func largest_step_allowed(table: MusicTable) -> float:
	var quickest: float = minf(table.crossfade_seconds, minf(table.meltdown_seconds, table.end_fade_seconds))
	return ShipState.TICK_DT / quickest + 0.0001


## The moments the step `id` expects, in order, from `EXPECTED_FILE`; empty
## when it lists none.
static func expected_for(id: String) -> Array[String]:
	return CUES_CHECK.expected_for(id, EXPECTED_FILE)


## Flies `replay` with the music's mix followed each tick: {"moments": the
## moments in order, "reactor_destroyed": whether it was, "meltdown_ticks":
## ticks from the reactor's end until the meltdown track was full and the
## others silent (-1 if never), "largest_step": the most a gain moved in one
## tick, "hash": the final state hash}, or empty when the replay cannot start.
## After the last frame the end screen stays up, the simulation stands still,
## and the mix runs on for the end fade, as the game's frames would.
static func fly(replay: Replay, table: MusicTable) -> Dictionary:
	# As `room_reverb_check.gd`: `Replay.run` with no frames is the sim before its first tick.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var heard: Dictionary = {"mix": MusicMix.new(table), "moments": [] as Array[String],
		"largest_step": 0.0, "destroyed_at": -1, "meltdown_ticks": -1}
	var tail: int = ceili(table.end_fade_seconds * ShipState.TICK_RATE) + 1
	for tick: int in frames.size() + tail:
		if tick < frames.size():
			var inputs: Array[ShipInput] = []
			inputs.assign(frames[tick])
			sim.step(inputs)
		_hear_tick(heard, table, tick, sim.outcome(), SessionSnapshots.reactor(sim.reactor))
	return {"moments": heard["moments"], "reactor_destroyed": heard["destroyed_at"] >= 0,
		"meltdown_ticks": heard["meltdown_ticks"], "largest_step": heard["largest_step"],
		"hash": sim.state_hash()}


## Moves `heard`'s mix one tick on for `outcome` and `reactor` (a copy) and
## notes what changed.
static func _hear_tick(heard: Dictionary, table: MusicTable, tick: int, outcome: ExitRule.Outcome,
		reactor: ReactorState) -> void:
	var mix: MusicMix = heard["mix"]
	var moments: Array[String] = heard["moments"]
	if heard["destroyed_at"] < 0 and reactor != null and reactor.destroyed:
		heard["destroyed_at"] = tick
	var before: Dictionary[String, float] = mix.gains.duplicate()
	var gains: Dictionary[String, float] = mix.advance(MusicWiring.mood_of(outcome, reactor), 0.0,
		ShipState.TICK_DT)
	for id: String in gains:
		heard["largest_step"] = maxf(heard["largest_step"], absf(gains[id] - before[id]))
		if gains[id] >= 1.0 and before[id] < 1.0 and not moments.has(id):
			moments.append(id)
	if heard["destroyed_at"] >= 0 and heard["meltdown_ticks"] < 0 and _meltdown_full(table, gains):
		heard["meltdown_ticks"] = tick - int(heard["destroyed_at"])
	if mix.mood == MusicMix.Mood.ENDED and mix.sounding().is_empty() and not moments.has(FADED):
		moments.append(FADED)


static func _meltdown_full(table: MusicTable, gains: Dictionary[String, float]) -> bool:
	for layer: MusicLayer in table.layers:
		var want: float = 1.0 if layer.plays == MusicLayer.MELTDOWN else 0.0
		if gains[layer.id] != want:
			return false
	return true
