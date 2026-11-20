extends RefCounted

## The first-launch flight test session (#699, CMF-4, ARC-3): it steps the
## plan's segments by the time it is handed, waits for an answer after each,
## takes `fine`, `uneasy` or `stop`, and recommends a preset.

const FINE: String = PresetRecommender.FINE
const UNEASY: String = PresetRecommender.UNEASY
const STOP: String = PresetRecommender.STOP


func _plan() -> FlightTestPlan:
	return FlightTestPlan.load_file()


## Flies the current segment to its end and gives `given`.
func _fly_and_answer(session: FlightTestSession, given: String) -> String:
	session.advance(session.seconds_left())
	return session.answer(given)


func test_the_shipped_plan_loads_and_stays_within_two_minutes() -> String:
	var plan: FlightTestPlan = _plan()
	if plan.error != "":
		return "shipped plan rejected: %s" % plan.error
	var session: FlightTestSession = FlightTestSession.new(plan)
	var flown: float = 0.0
	while not session.finished():
		flown += session.seconds_left()
		var error: String = _fly_and_answer(session, FINE)
		if error != "":
			return "a fine answer was refused: %s" % error
	if flown > FlightTestPlan.MAX_TOTAL_S:
		return "the session flies %s s, over %s s" % [flown, FlightTestPlan.MAX_TOTAL_S]
	if absf(flown - plan.total_duration_s()) > 0.001:
		return "the session flew %s s of a %s s plan" % [flown, plan.total_duration_s()]
	return ""


func test_all_fine_recommends_the_last_segments_preset() -> String:
	var plan: FlightTestPlan = _plan()
	var session: FlightTestSession = FlightTestSession.new(plan)
	var presets: Array[int] = []
	while not session.finished():
		presets.append(session.preset_now())
		_fly_and_answer(session, FINE)
	var last: int = plan.segments[plan.segments.size() - 1].preset
	if session.recommended() != last or session.preset_now() != last:
		return "all fine recommends %d, expected %d" % [session.recommended(), last]
	if presets.size() != plan.segments.size() or presets[0] != plan.segments[0].preset:
		return "preset_now() during the test was %s" % [presets]
	if session.current_segment() != null or session.seconds_left() != 0.0:
		return "a finished session still has a segment or time left"
	return ""


func test_uneasy_on_the_second_segment_recommends_the_first_segments_preset() -> String:
	var plan: FlightTestPlan = _plan()
	var session: FlightTestSession = FlightTestSession.new(plan)
	_fly_and_answer(session, FINE)
	_fly_and_answer(session, UNEASY)
	if not session.finished():
		return "the test went on after an uneasy answer"
	if session.recommended() != plan.segments[0].preset:
		return "recommended %d, expected segment 1's %d" % [session.recommended(), plan.segments[0].preset]
	if session.answer(FINE) == "":
		return "an answer was taken after the test ended"
	return ""


func test_stop_on_the_first_segment_gives_preset_1() -> String:
	var session: FlightTestSession = FlightTestSession.new(_plan())
	_fly_and_answer(session, STOP)
	if not session.finished() or session.recommended() != 1:
		return "stop on the first segment gave preset %d, finished %s" % [session.recommended(), session.finished()]
	return ""


func test_an_answer_before_the_segment_ends_is_refused() -> String:
	var plan: FlightTestPlan = _plan()
	var session: FlightTestSession = FlightTestSession.new(plan)
	var duration: float = plan.segments[0].duration_s
	session.advance(duration - 1.0)
	if session.awaiting_answer() or absf(session.seconds_left() - 1.0) > 0.001:
		return "after %s of %s s the segment has %s s left" % [duration - 1.0, duration, session.seconds_left()]
	if session.answer(FINE) == "":
		return "an answer 1 s before the segment ended was taken"
	if session.answers().size() != 0 or session.segment_index() != 0:
		return "a refused answer changed the session"
	session.advance(0.5)
	session.advance(0.5)
	if not session.awaiting_answer() or session.seconds_left() != 0.0:
		return "the segment did not end on its duration"
	session.advance(30.0)
	if session.segment_index() != 0:
		return "time moved the session on without an answer"
	if session.answer("maybe") == "":
		return "an unknown answer was taken"
	if session.answer(FINE) != "" or session.segment_index() != 1:
		return "a fine answer after the segment ended was refused"
	return ""


func test_skip_ends_with_preset_1() -> String:
	var plan: FlightTestPlan = _plan()
	var session: FlightTestSession = FlightTestSession.new(plan)
	_fly_and_answer(session, FINE)
	_fly_and_answer(session, FINE)
	session.skip()
	if not session.finished() or not session.skipped() or session.recommended() != FlightTestSession.SKIP_PRESET:
		return "skip gave preset %d" % session.recommended()
	return ""


func test_a_rejected_plan_is_over_at_once_with_preset_1() -> String:
	var session: FlightTestSession = FlightTestSession.new(FlightTestPlan.parse_json("{}"))
	session.advance(5.0)
	if not session.finished() or session.recommended() != 1 or session.answer(FINE) == "":
		return "a rejected plan did not end at once with preset 1"
	return ""


func test_the_session_reads_no_clock_node_or_input() -> String:
	var code: String = (load("res://xr/flight_test_session.gd") as GDScript).source_code
	for word: String in ["Time.", "Input.", "Node", "get_tree", "OS.", "_process"]:
		if code.contains(word):
			return "flight_test_session.gd mentions %s" % word
	if not FlightTestSession.new(_plan()) is RefCounted:
		return "the session is not a RefCounted"
	return ""
