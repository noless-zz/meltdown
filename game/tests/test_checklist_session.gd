extends RefCounted

## Marks on a checklist (#1325, DEV-6): what a mark records, where the page
## moves on to, the results file's contents and taking saved marks back.

const TEXT: String = '{"id": "t1", "title": "T", "issue": 7, "remarks": ["unclear"], "parts": [{"title": "P", "steps": [' \
	+ '{"id": "a", "do": "A", "look_for": "a"}, {"id": "b", "do": "B", "look_for": "b"}, {"id": "c", "do": "C", "look_for": "c"}]}]}'
const CONTEXT: Dictionary = {"preset": 1, "source": "seed:31"}
const TIME: String = "2026-11-26T08:00:00Z"


static func made() -> ChecklistSession:
	return ChecklistSession.new(Checklist.parse(TEXT))


func test_a_mark_records_the_remark_preset_source_and_time() -> String:
	var session: ChecklistSession = made()
	var problem: String = session.mark(0, ChecklistSession.FAIL, "unclear", CONTEXT, TIME)
	if problem != "":
		return problem
	var want: Dictionary = {"mark": "fail", "remark": "unclear", "time": TIME, "preset": 1, "source": "seed:31"}
	if session.marks["a"] != want:
		return "recorded %s" % session.marks["a"]
	return "" if session.started == TIME and session.updated == TIME else "times %s %s" % [session.started, session.updated]


func test_marking_moves_on_to_the_next_unmarked_step() -> String:
	var session: ChecklistSession = made()
	session.mark(1, ChecklistSession.PASS, "", CONTEXT, TIME)
	if session.current != 2:
		return "after b, current %d" % session.current
	session.mark(2, ChecklistSession.SKIP, "", CONTEXT, TIME)
	if session.current != 0:
		return "after c, current %d, want the unmarked a" % session.current
	session.mark(0, ChecklistSession.PASS, "", CONTEXT, TIME)
	return "" if session.current == 1 else "all marked, current %d" % session.current


func test_bad_marks_are_refused_and_change_nothing() -> String:
	var session: ChecklistSession = made()
	for problem: String in [session.mark(3, "pass", "", CONTEXT, TIME), session.mark(0, "maybe", "", CONTEXT, TIME),
			session.mark(0, "pass", "lovely", CONTEXT, TIME)]:
		if problem == "":
			return "a bad mark was taken"
	return "" if session.marks.is_empty() else "marks %s" % session.marks


func test_results_list_every_step_with_the_build_and_counts() -> String:
	var session: ChecklistSession = made()
	session.mark(1, ChecklistSession.PASS, "", CONTEXT, TIME)
	var results: Dictionary = session.results("abc123")
	for key: String in ["checklist", "title", "issue", "build", "started", "updated", "counts", "steps", "format"]:
		if not results.has(key):
			return "no %s in %s" % [key, results]
	if results["build"] != "abc123" or results["issue"] != 7 or results["checklist"] != "t1":
		return "results %s" % results
	var steps: Array = results["steps"]
	if steps.size() != 3 or steps[0]["mark"] != null or steps[1]["mark"] != "pass" or steps[1]["source"] != "seed:31":
		return "steps %s" % [steps]
	var counts: Dictionary = results["counts"]
	return "" if counts["pass"] == 1 and counts["open"] == 2 else "counts %s" % counts


func test_saved_results_come_back_through_json() -> String:
	var session: ChecklistSession = made()
	session.mark(0, ChecklistSession.FAIL, "unclear", CONTEXT, TIME)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.results("abc")))
	var again: ChecklistSession = made()
	if again.restore(saved) != 1:
		return "restored %d marks" % again.restore(saved)
	if again.marks["a"] != session.marks["a"] or again.current != 1 or again.started != TIME:
		return "restored %s, current %d" % [again.marks, again.current]
	return ""


func test_results_of_another_checklist_are_ignored() -> String:
	var session: ChecklistSession = made()
	session.mark(0, ChecklistSession.PASS, "", CONTEXT, TIME)
	var saved: Dictionary = session.results("abc")
	saved["checklist"] = "other"
	var again: ChecklistSession = made()
	return "" if again.restore(saved) == 0 and again.marks.is_empty() else "took %s" % again.marks
