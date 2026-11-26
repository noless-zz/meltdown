extends RefCounted

## The `room_tones_change` acceptance check (#1399, AUD-1, ARC-1): the G2
## escape flight hears at least two space tones and the switch to the
## meltdown rumble, ends on its pinned hash, and the judge fails each way it
## should.

const CHECK_SCRIPT: String = "res://acceptance/checks/room_tones_check.gd"
const REPLAY: String = "res://acceptance/replays/bot_g2_escape_alarm.replay"
const PINNED_HASH: int = 2803663058


static func _check() -> GDScript:
	return load(CHECK_SCRIPT) as GDScript


static func _flight(spaces: Array, destroyed: bool, meltdown_ticks: int, largest: float) -> Dictionary:
	return {"spaces": spaces, "changes": 3, "reactor_destroyed": destroyed,
		"meltdown_ticks": meltdown_ticks, "pulse_peak": 0.5, "largest_step": largest}


func test_g2_escape_flight_passes_on_its_pinned_hash() -> String:
	var replay: Replay = Replay.load_file(REPLAY)
	if replay.error != "":
		return "the replay was refused: %s" % replay.error
	var table: RoomToneTable = RoomToneTable.load_file()
	var flown: Dictionary = _check().fly(replay, table)
	if flown.is_empty():
		return "the replay did not start"
	if int(flown["hash"]) != PINNED_HASH:
		return "the flight ended on %d, not %d" % [flown["hash"], PINNED_HASH]
	var verdict: Array = _check().judge_flight(flown, _check().largest_step_allowed(table))
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else str(verdict[1])


func test_judge_fails_each_way() -> String:
	var allowed: float = 0.02
	var cases: Dictionary[String, Dictionary] = {
		"at least two": _flight(["tunnel"], true, 60, 0.01),
		"never destroyed": _flight(["tunnel", "room"], false, -1, 0.01),
		"took over -1": _flight(["tunnel", "room"], true, -1, 0.01),
		"took over 200": _flight(["tunnel", "room"], true, 200, 0.01),
		"jumped": _flight(["tunnel", "room"], true, 60, 0.5),
	}
	for expected: String in cases:
		var verdict: Array = _check().judge_flight(cases[expected], allowed)
		if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains(expected):
			return "expected a failure saying '%s', got %s" % [expected, verdict]
	var good: Array = _check().judge_flight(_flight(["tunnel", "room"], true, 60, 0.01), allowed)
	return "" if good[0] == AcceptanceReport.RESULT_PASS else "a good flight failed: %s" % [good]


func test_check_is_registered() -> String:
	var judges: Dictionary = _check().judges()
	return "" if judges.has("room_tones_change") else "the check is not registered"
