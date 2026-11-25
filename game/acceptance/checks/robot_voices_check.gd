extends RefCounted

## The `robot_voices_heard` acceptance check (#1363, AUD-2, ARC-1): re-flies
## the step's replay tick by tick and chooses the robot voices as the game
## does, with the shipped table and ship 0 as the listener. It passes when:
##
## - every robot type the step expects was heard at some tick, and no type
##   outside that list was (the list is data, by step id, in
##   `robot_voices.json` beside this file);
## - some voice was heard through a wall, and every such voice was quieter
##   than the same robot heard in the open (its row's `muffle_db` below 0);
## - no tick chose more voices than the table's `max_voices`.
##
## It also checks the flight with the voices followed ends on the step's pinned
## hash: listening to the simulation must not change it. No audio device is
## needed; the check plays nothing.

const EXPECTED_FILE: String = "res://acceptance/checks/robot_voices.json"
const CHECK: String = "robot_voices_heard"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var expected: Array[String] = expected_for(step.id)
	if expected.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "%s lists no robot types for step %s" % [EXPECTED_FILE, step.id]]
	var table: RobotVoiceTable = RobotVoiceTable.load_file()
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the robot voice table was rejected: %s" % table.error]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Dictionary = fly(replay, table)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	measurements["robot_voice_types"] = flown["types"]
	measurements["robot_voices_muffled_ticks"] = flown["muffled_ticks"]
	measurements["robot_voices_most_at_once"] = flown["most"]
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with the voices followed the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	return judge_flight(flown, expected, table.max_voices)


## Pass or fail for a flight `fly` returned, as [result, why].
static func judge_flight(flown: Dictionary, expected: Array[String], max_voices: int) -> Array:
	var types: Array[String] = flown["types"]
	for id: String in expected:
		if not types.has(id):
			return [AcceptanceReport.RESULT_FAIL, "no %s voice was heard; heard %s" % [id, types]]
	for id: String in types:
		if not expected.has(id):
			return [AcceptanceReport.RESULT_FAIL, "a %s voice was heard, which %s does not expect" % [id, expected]]
	if int(flown["most"]) > max_voices:
		return [AcceptanceReport.RESULT_FAIL, "%d voices at once; the cap is %d" % [flown["most"], max_voices]]
	if int(flown["muffled_ticks"]) == 0:
		return [AcceptanceReport.RESULT_FAIL, "no voice was heard through a wall"]
	if float(flown["least_muffle_db"]) >= 0.0:
		return [AcceptanceReport.RESULT_FAIL, "a voice through a wall was only %.1f dB quieter than in the open"
			% flown["least_muffle_db"]]
	return [AcceptanceReport.RESULT_PASS, "heard %s, at most %d at once; through a wall on %d ticks, %.1f dB quieter or more"
		% [types, flown["most"], flown["muffled_ticks"], -float(flown["least_muffle_db"])]]


## Flies `replay` with the voices chosen each tick: {"types": robot types heard,
## sorted; "most": most voices at once; "muffled_ticks": ticks with a voice
## heard through a wall; "least_muffle_db": the smallest drop a wall made,
## below 0 when every muffled voice was quieter (0 when none was muffled);
## "hash": the final state hash}, or empty when the replay cannot start.
static func fly(replay: Replay, table: RobotVoiceTable) -> Dictionary:
	# As `sound_cues_check.gd`: `Replay.run` with no frames is the sim before its first tick.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var types: Array[String] = []
	var most: int = 0
	var muffled_ticks: int = 0
	var least_drop: float = -INF
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		# The picker only reads; the pinned hash below shows it changed nothing.
		var mixes: Array[RobotVoiceMix] = RobotVoicePicker.pick(table, sim.robots, sim.ships[0].position, sim.walls)
		most = maxi(most, mixes.size())
		var any_muffled: bool = false
		for mix: RobotVoiceMix in mixes:
			if not types.has(mix.type_id):
				types.append(mix.type_id)
			if mix.muffled:
				any_muffled = true
				least_drop = maxf(least_drop, mix.player_db - table.voice(mix.type_id).volume_db)
		if any_muffled:
			muffled_ticks += 1
	types.sort()
	return {"types": types, "most": most, "muffled_ticks": muffled_ticks,
		"least_muffle_db": least_drop if muffled_ticks > 0 else 0.0, "hash": sim.state_hash()}


## The robot types step `id` expects to hear; empty when the file or the step has none.
static func expected_for(id: String, path: String = EXPECTED_FILE) -> Array[String]:
	var listed: Array[String] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
		if FileAccess.file_exists(path) else null
	if data is Dictionary and (data as Dictionary).get(id) is Array:
		for type_id: Variant in (data as Dictionary)[id]:
			listed.append(str(type_id))
	return listed
