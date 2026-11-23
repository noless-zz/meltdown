extends RefCounted

## The `sound_cues_in_order` acceptance check (#1290, AUD-1, ARC-1): re-flies
## the step's replay tick by tick, feeds every tick to `SoundCueEvents` as the
## game does, and passes when the cues the shipped table plays include the
## step's expected cues in their order (others may sound in between). The
## expected cues are data, by step id, in `sound_cues.json` beside this file.
##
## It also checks the flight with the cues followed ends on the step's pinned
## hash: reading the simulation for sound must not change it. No audio device
## is needed; the check plays nothing.

const EXPECTED_FILE: String = "res://acceptance/checks/sound_cues.json"
const CHECK: String = "sound_cues_in_order"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var expected: Array[String] = expected_for(step.id)
	if expected.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "%s lists no cues for step %s" % [EXPECTED_FILE, step.id]]
	var table: SoundCueTable = SoundCueTable.load_file()
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the cue table was rejected: %s" % table.error]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Array = fly(replay, table)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	var played: Array[String] = flown[0]
	var hash_value: int = flown[1]
	measurements["sound_cues_played"] = played.size()
	measurements["sound_cue_hash"] = hash_value
	if step.expected_hash != AcceptanceStep.NO_HASH and hash_value != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with the cues followed the hash is %d, not %d"
			% [hash_value, step.expected_hash]]
	var missing: String = first_missing(played, expected)
	if missing != "":
		return [AcceptanceReport.RESULT_FAIL, "%s did not follow the cues before it in %s; %d cues played"
			% [missing, expected, played.size()]]
	return [AcceptanceReport.RESULT_PASS, "%d cues played, %s in order" % [played.size(), expected]]


## [the cues `table` plays over `replay`, in order; the final state hash], or
## empty when the replay cannot start.
static func fly(replay: Replay, table: SoundCueTable) -> Array:
	# `Replay.run` with no frames is the sim set up from the header, before its
	# first tick; the frames are put back at once and stepped here.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return []
	var cue_events: SoundCueEvents = SoundCueEvents.new()
	var played: Array[String] = []
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		for hit: SoundCueHit in cue_events.feed(sim.last_events, sim.projectiles, sim.ships):
			if table.plays(hit):
				played.append(hit.cue)
	return [played, sim.state_hash()]


## The first of `expected` not found in `played` after the ones before it, or "".
static func first_missing(played: Array[String], expected: Array[String]) -> String:
	var from: int = 0
	for cue: String in expected:
		var at: int = played.find(cue, from)
		if at < 0:
			return cue
		from = at + 1
	return ""


## The expected cues for step `id`; empty when the file or the step has none.
static func expected_for(id: String, path: String = EXPECTED_FILE) -> Array[String]:
	var listed: Array[String] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
		if FileAccess.file_exists(path) else null
	if data is Dictionary and (data as Dictionary).get(id) is Array:
		for cue: Variant in (data as Dictionary)[id]:
			listed.append(str(cue))
	return listed
