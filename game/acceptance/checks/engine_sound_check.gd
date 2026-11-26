extends RefCounted

## The `engine_follows_thrust` acceptance check (#1398, AUD-1, ARC-1): re-flies
## the step's replay tick by tick and follows the pilot's engine mix as the
## game does, with the shipped table, from ship 0's copies one tick apart. It
## passes when:
##
## - once faded in, the engine sounds on every tick of the flight;
## - the thrust layer rises with thrust: its mean level on ticks the pilot
##   holds at least half thrust is above its mean on ticks with none, and the
##   flight has some of each.
##
## It also checks the flight with the engine followed ends on the step's pinned
## hash: listening to the ship must not change it. No audio device is needed;
## the check plays nothing.

const CHECK: String = "engine_follows_thrust"
## Input thrust at or above this share counts as pushing.
const PUSHING: float = 0.5


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var table: EngineSoundTable = EngineSoundTable.load_file()
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the engine table was rejected: %s" % table.error]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Dictionary = fly(replay, table)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	for key: String in ["silent_ticks", "pushing_ticks", "idle_ticks", "pushing_db", "idle_db"]:
		measurements["engine_" + key] = flown[key]
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with the engine followed the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	return judge_flight(flown)


## Pass or fail for a flight `fly` returned, as [result, why].
static func judge_flight(flown: Dictionary) -> Array:
	if int(flown["silent_ticks"]) > 0:
		return [AcceptanceReport.RESULT_FAIL, "the engine was silent on %d ticks of flight" % flown["silent_ticks"]]
	if int(flown["pushing_ticks"]) == 0 or int(flown["idle_ticks"]) == 0:
		return [AcceptanceReport.RESULT_FAIL, "the flight needs ticks with and without thrust; %d pushing, %d not"
			% [flown["pushing_ticks"], flown["idle_ticks"]]]
	if float(flown["pushing_db"]) <= float(flown["idle_db"]):
		return [AcceptanceReport.RESULT_FAIL, "the thrust layer averaged %.1f dB while pushing, not above %.1f dB without"
			% [flown["pushing_db"], flown["idle_db"]]]
	return [AcceptanceReport.RESULT_PASS, "the engine sounded throughout; the thrust layer averaged %.1f dB over %d pushing ticks, %.1f dB over %d without"
		% [flown["pushing_db"], flown["pushing_ticks"], flown["idle_db"], flown["idle_ticks"]]]


## Flies `replay` with the engine mix followed each tick: {"silent_ticks":
## ticks of flight, after the fade-in, with the engine silent; "pushing_ticks"
## and "idle_ticks": ticks with ship 0's input thrust at least `PUSHING` and at
## 0; "pushing_db" and "idle_db": the thrust layer's mean level over each;
## "hash": the final state hash}, or empty when the replay cannot start.
static func fly(replay: Replay, table: EngineSoundTable) -> Dictionary:
	# As `robot_voices_check.gd`: `Replay.run` with no frames is the sim before its first tick.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var mix: EngineSoundMix = EngineSoundMix.new(table)
	var fade_ticks: int = ceili(table.fade_seconds / ShipState.TICK_DT)
	var silent: int = 0
	var sums: Dictionary[String, float] = {"pushing": 0.0, "idle": 0.0}
	var counts: Dictionary[String, int] = {"pushing": 0, "idle": 0}
	var after: ShipState = SessionSnapshots.ship(sim.ships[0])
	for index: int in frames.size():
		var inputs: Array[ShipInput] = []
		inputs.assign(frames[index])
		var before: ShipState = after
		sim.step(inputs)
		# The mix only reads copies; the pinned hash below shows it changed nothing.
		after = SessionSnapshots.ship(sim.ships[0])
		var flying: bool = sim.outcome() == ExitRule.Outcome.RUNNING
		mix.advance(flying, EngineSoundMix.thrust_of(before, after), EngineSoundMix.speed_of(after),
			ShipState.TICK_DT)
		if not flying:
			continue
		if index >= fade_ticks and not mix.sounding():
			silent += 1
		var pushed: float = inputs[0].thrust().length() if not inputs.is_empty() else 0.0
		var kind: String = "pushing" if pushed >= PUSHING else ("idle" if pushed == 0.0 else "")
		if kind != "" and index >= fade_ticks:
			sums[kind] += mix.thrust_db()
			counts[kind] += 1
	return {"silent_ticks": silent, "pushing_ticks": counts["pushing"], "idle_ticks": counts["idle"],
		"pushing_db": sums["pushing"] / maxi(counts["pushing"], 1),
		"idle_db": sums["idle"] / maxi(counts["idle"], 1), "hash": sim.state_hash()}
