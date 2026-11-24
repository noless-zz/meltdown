extends RefCounted

## The `room_reverb_changed` acceptance check (#1291, AUD-1, ARC-1): re-flies
## the step's replay tick by tick and follows the reverb as the game does,
## with the shipped table. It passes when the reverb heard moved from the
## start's by at least `MIN_CHANGE` (the flight went from a tunnel into a
## room) and never moved by more in one tick than a blend allows (it blended,
## it did not jump). No audio device is needed; the check plays nothing.
##
## It also checks the flight with the reverb followed ends on the step's pinned
## hash: reading the simulation for sound must not change it.

const CHECK: String = "room_reverb_changed"
## Least change of any reverb value, 0..1, that counts as a different room.
const MIN_CHANGE: float = 0.1


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var table: RoomReverbTable = RoomReverbTable.load_file()
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the reverb table was rejected: %s" % table.error]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Dictionary = fly(replay, table)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	measurements["room_reverb_change"] = flown["change"]
	measurements["room_reverb_largest_step"] = flown["largest_step"]
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with the reverb followed the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	return judge_flight(flown, largest_step_allowed(table))


## Pass or fail for a flight `fly` returned, as [result, why].
static func judge_flight(flown: Dictionary, step_allowed: float) -> Array:
	if flown["change"] < MIN_CHANGE:
		return [AcceptanceReport.RESULT_FAIL, "the reverb moved at most %.3f from %s; a room is %.2f"
			% [flown["change"], flown["start"], MIN_CHANGE]]
	if flown["largest_step"] > step_allowed:
		return [AcceptanceReport.RESULT_FAIL, "the reverb jumped %.3f in one tick; a blend moves %.3f at most"
			% [flown["largest_step"], step_allowed]]
	return [AcceptanceReport.RESULT_PASS, "from %s the reverb moved up to %.3f, at most %.3f a tick"
		% [flown["start"], flown["change"], flown["largest_step"]]]


## The most any reverb value may move in one tick while blending: the widest
## gap in the table spread over the blend's ticks.
static func largest_step_allowed(table: RoomReverbTable) -> float:
	var widest: float = 0.0
	for a: ReverbSetting in table.settings:
		for b: ReverbSetting in table.settings:
			widest = maxf(widest, a.distance_to(b))
	var ticks: float = maxf(1.0, table.blend_seconds * ShipState.TICK_RATE)
	return widest / ticks + 0.0001


## Flies `replay` with the reverb followed each tick: {"start": the first
## setting heard, "change": the furthest any later one got from it,
## "largest_step": the most it moved in one tick, "hash": the final state
## hash}, or empty when the replay cannot start.
static func fly(replay: Replay, table: RoomReverbTable) -> Dictionary:
	# As `sound_cues_check.gd`: `Replay.run` with no frames is the sim before its first tick.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var blend: RoomReverbBlend = RoomReverbBlend.new(table.blend_seconds)
	var start: ReverbSetting = blend.advance(table.setting_at(sim.walls, sim.ships[0].position), 0.0)
	var last: ReverbSetting = start
	var change: float = 0.0
	var largest_step: float = 0.0
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		var heard: ReverbSetting = blend.advance(table.setting_at(sim.walls, sim.ships[0].position),
			ShipState.TICK_DT)
		if heard == null:
			continue
		if start == null:
			start = heard
		if last != null:
			largest_step = maxf(largest_step, heard.distance_to(last))
		change = maxf(change, heard.distance_to(start))
		last = heard
	return {"start": start, "change": change, "largest_step": largest_step, "hash": sim.state_hash()}
