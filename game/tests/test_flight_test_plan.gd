extends RefCounted

## The first-launch flight test plan and its recommendation (CMF-4, CMF-1,
## ARC-4): the shipped plan fits in two minutes and climbs through the
## presets, a bad plan is rejected with the field named, and the answers turn
## into a preset by the rule in issue #135.


func _segment(id: String, preset: Variant, seconds: Variant = 10, move: String = "smooth_yaw") -> Dictionary:
	return {"id": id, "preset": preset, "duration_s": seconds, "manoeuvre": move}


func _plan_text(segments: Array) -> String:
	return JSON.stringify({"segments": segments})


## A plan with one segment per preset, 1 to 4, in order.
func _four_step_plan() -> FlightTestPlan:
	return FlightTestPlan.parse_json(_plan_text([
		_segment("snap", 1, 10, "snap_yaw"), _segment("capped", 2), _segment("full", 3),
		_segment("roll", 4, 10, "manual_roll"),
	]))


func _answers(values: Array) -> Array[String]:
	var answers: Array[String] = []
	for value: Variant in values:
		answers.append(str(value))
	return answers


func test_shipped_plan_loads_within_two_minutes() -> String:
	var plan: FlightTestPlan = FlightTestPlan.load_file()
	if plan.error != "":
		return plan.error
	if plan.segments.is_empty():
		return "shipped plan has no segments"
	if plan.total_duration_s() > 120.0:
		return "shipped plan lasts %s s" % plan.total_duration_s()
	return ""


func test_shipped_plan_covers_presets_1_to_4_in_order() -> String:
	var plan: FlightTestPlan = FlightTestPlan.load_file()
	if plan.error != "":
		return plan.error
	if plan.segments[0].preset != 1:
		return "first segment is preset %d, not 1" % plan.segments[0].preset
	if plan.segments[-1].preset != 4:
		return "last segment is preset %d, not 4" % plan.segments[-1].preset
	return ""


func test_shipped_plan_all_fine_gives_4() -> String:
	var plan: FlightTestPlan = FlightTestPlan.load_file()
	var answers: Array[String] = []
	for segment: FlightTestSegment in plan.segments:
		answers.append(PresetRecommender.FINE)
	var got: int = PresetRecommender.recommend(plan, answers)
	return "" if got == 4 else "all fine gave %d" % got


func test_segment_fields_are_read() -> String:
	var plan: FlightTestPlan = FlightTestPlan.parse_json(_plan_text([_segment("a", 2, 12.5, "smooth_pitch")]))
	if plan.error != "":
		return plan.error
	var segment: FlightTestSegment = plan.segments[0]
	if segment.id != "a" or segment.preset != 2 or segment.duration_s != 12.5 or segment.manoeuvre != "smooth_pitch":
		return "read %s %d %s %s" % [segment.id, segment.preset, segment.duration_s, segment.manoeuvre]
	return ""


func test_decreasing_preset_is_rejected() -> String:
	var plan: FlightTestPlan = FlightTestPlan.parse_json(_plan_text([
		_segment("a", 1), _segment("b", 3), _segment("c", 2),
	]))
	if plan.error.find("segment 2") < 0 or plan.error.find("\"preset\"") < 0:
		return "decreasing preset gave error \"%s\"" % plan.error
	return "" if plan.segments.is_empty() else "rejected plan kept its segments"


func test_equal_presets_are_allowed() -> String:
	var plan: FlightTestPlan = FlightTestPlan.parse_json(_plan_text([_segment("a", 2), _segment("b", 2)]))
	return plan.error


func test_over_two_minutes_is_rejected() -> String:
	var plan: FlightTestPlan = FlightTestPlan.parse_json(_plan_text([
		_segment("a", 1, 60), _segment("b", 2, 60), _segment("c", 3, 1),
	]))
	if plan.error.find("at most 120") < 0:
		return "121 s plan gave error \"%s\"" % plan.error
	var exact: FlightTestPlan = FlightTestPlan.parse_json(_plan_text([_segment("a", 1, 60), _segment("b", 2, 60)]))
	return exact.error


func test_bad_fields_are_rejected_with_the_field_named() -> String:
	var cases: Array = [
		["{", "invalid JSON"],
		["[]", "top level"],
		["{}", "missing key \"segments\""],
		[JSON.stringify({"segments": []}), "non-empty"],
		[JSON.stringify({"segments": [], "extra": 1}), "unknown key \"extra\""],
		[_plan_text([5]), "segment 0: must be a JSON object"],
		[_plan_text([{"id": "a", "preset": 1, "duration_s": 5}]), "missing key \"manoeuvre\""],
		[_plan_text([{"id": "a", "preset": 1, "duration_s": 5, "manoeuvre": "snap_yaw", "speed": 2}]), "unknown key \"speed\""],
		[_plan_text([_segment("", 1)]), "\"id\""],
		[_plan_text([_segment("a", 1), _segment("a", 2)]), "segment 1: \"id\" \"a\" is used twice"],
		[_plan_text([_segment("a", 0)]), "\"preset\""],
		[_plan_text([_segment("a", 5)]), "\"preset\""],
		[_plan_text([_segment("a", 1.5)]), "\"preset\""],
		[_plan_text([_segment("a", true)]), "\"preset\" must be a number"],
		[_plan_text([_segment("a", 1, 0)]), "\"duration_s\""],
		[_plan_text([_segment("a", 1, -3)]), "\"duration_s\""],
		[_plan_text([_segment("a", 1, 61)]), "\"duration_s\""],
		[_plan_text([_segment("a", 1, "10")]), "\"duration_s\" must be a number"],
		[_plan_text([_segment("a", 1, 10, "barrel_roll")]), "\"manoeuvre\""],
	]
	for case: Array in cases:
		var plan: FlightTestPlan = FlightTestPlan.parse_json(case[0])
		if plan.error.find(case[1]) < 0:
			return "%s gave error \"%s\", expected \"%s\"" % [case[0], plan.error, case[1]]
		if not plan.segments.is_empty():
			return "%s was rejected but kept segments" % case[0]
	return ""


func test_missing_file_is_rejected() -> String:
	var plan: FlightTestPlan = FlightTestPlan.load_file("res://xr/flight_test/no_such_plan.json")
	return "" if plan.error.find("not found") >= 0 else "missing file gave \"%s\"" % plan.error


func test_all_fine_gives_4() -> String:
	var got: int = PresetRecommender.recommend(_four_step_plan(), _answers(["fine", "fine", "fine", "fine"]))
	return "" if got == 4 else "got %d" % got


func test_fine_fine_uneasy_gives_segment_2_preset() -> String:
	var got: int = PresetRecommender.recommend(_four_step_plan(), _answers(["fine", "fine", "uneasy"]))
	return "" if got == 2 else "got %d" % got


func test_answers_after_uneasy_do_not_raise_it() -> String:
	var got: int = PresetRecommender.recommend(_four_step_plan(), _answers(["fine", "uneasy", "fine", "fine"]))
	return "" if got == 1 else "got %d" % got


func test_stop_first_gives_1() -> String:
	var got: int = PresetRecommender.recommend(_four_step_plan(), _answers(["stop"]))
	return "" if got == 1 else "got %d" % got


func test_no_fine_gives_1() -> String:
	var got: int = PresetRecommender.recommend(_four_step_plan(), _answers(["uneasy", "uneasy", "uneasy", "uneasy"]))
	if got != 1:
		return "all uneasy gave %d" % got
	var none: int = PresetRecommender.recommend(_four_step_plan(), _answers([]))
	return "" if none == 1 else "no answers gave %d" % none


func test_stopped_early_uses_answers_given() -> String:
	var got: int = PresetRecommender.recommend(_four_step_plan(), _answers(["fine", "fine", "fine", "stop"]))
	if got != 3:
		return "stop at segment 4 gave %d" % got
	var short: int = PresetRecommender.recommend(_four_step_plan(), _answers(["fine", "fine"]))
	return "" if short == 2 else "two fine answers gave %d" % short


func test_shared_presets_take_the_last_fine_segment() -> String:
	var plan: FlightTestPlan = FlightTestPlan.parse_json(_plan_text([
		_segment("a", 1), _segment("b", 2), _segment("c", 2), _segment("d", 3),
	]))
	var got: int = PresetRecommender.recommend(plan, _answers(["fine", "fine", "fine", "uneasy"]))
	return "" if got == 2 else "got %d" % got


func test_unknown_answer_is_an_error() -> String:
	var plan: FlightTestPlan = _four_step_plan()
	var answers: Array[String] = _answers(["fine", "ok"])
	if PresetRecommender.recommend(plan, answers) != PresetRecommender.INVALID:
		return "unknown answer was scored"
	var message: String = PresetRecommender.check(plan, answers)
	if message.find("answer 1") < 0 or message.find("\"ok\"") < 0:
		return "unknown answer gave \"%s\"" % message
	if PresetRecommender.recommend(plan, _answers(["Fine"])) != PresetRecommender.INVALID:
		return "answers are matched case-sensitively, \"Fine\" was scored"
	return ""


func test_answers_after_stop_or_too_many_are_errors() -> String:
	var plan: FlightTestPlan = _four_step_plan()
	if PresetRecommender.recommend(plan, _answers(["fine", "stop", "fine"])) != PresetRecommender.INVALID:
		return "answer after stop was scored"
	if PresetRecommender.recommend(plan, _answers(["fine", "fine", "fine", "fine", "fine"])) != PresetRecommender.INVALID:
		return "more answers than segments was scored"
	return ""


func test_rejected_or_missing_plan_is_an_error() -> String:
	var bad: FlightTestPlan = FlightTestPlan.parse_json("{}")
	if PresetRecommender.recommend(bad, _answers(["fine"])) != PresetRecommender.INVALID:
		return "rejected plan was scored"
	if PresetRecommender.check(null, _answers([])) == "":
		return "null plan was accepted"
	return ""
