extends RefCounted

## The `engine_follows_thrust` acceptance check (#1398, AUD-1, ARC-1): the G2
## bot flight hears the engine throughout with its thrust layer louder while
## pushing, ends on its pinned hash, and the judge fails each way it should.

const CHECK_SCRIPT: String = "res://acceptance/checks/engine_sound_check.gd"
const REPLAY: String = "res://acceptance/replays/bot_g2_level.replay"
const PINNED_HASH: int = 802400918


static func _check() -> GDScript:
	return load(CHECK_SCRIPT) as GDScript


static func _flight(silent: int, pushing: int, idle: int, pushing_db: float, idle_db: float) -> Dictionary:
	return {"silent_ticks": silent, "pushing_ticks": pushing, "idle_ticks": idle,
		"pushing_db": pushing_db, "idle_db": idle_db}


func test_g2_flight_passes_on_its_pinned_hash() -> String:
	var replay: Replay = Replay.load_file(REPLAY)
	if replay.error != "":
		return "the replay was refused: %s" % replay.error
	var flown: Dictionary = _check().fly(replay, EngineSoundTable.load_file())
	if flown.is_empty():
		return "the replay did not start"
	if int(flown["hash"]) != PINNED_HASH:
		return "the flight ended on %d, not %d" % [flown["hash"], PINNED_HASH]
	var verdict: Array = _check().judge_flight(flown)
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else str(verdict[1])


func test_judge_fails_each_way() -> String:
	var cases: Dictionary[String, Dictionary] = {
		"silent": _flight(3, 10, 10, -20.0, -30.0),
		"needs ticks": _flight(0, 0, 10, -20.0, -30.0),
		"not above": _flight(0, 10, 10, -30.0, -30.0),
	}
	for expected: String in cases:
		var verdict: Array = _check().judge_flight(cases[expected])
		if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains(expected):
			return "expected a failure saying '%s', got %s" % [expected, verdict]
	var good: Array = _check().judge_flight(_flight(0, 10, 10, -20.0, -30.0))
	return "" if good[0] == AcceptanceReport.RESULT_PASS else "a good flight failed: %s" % [good]


func test_check_is_registered() -> String:
	var judges: Dictionary = _check().judges()
	return "" if judges.has("engine_follows_thrust") else "the check is not registered"
