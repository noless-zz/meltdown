extends RefCounted

## The m6 `end_screen_lists` acceptance check (#1376, DEV-6): judged on fed
## lists, and listed on the `pickup_look` step, whose flight collects cell
## salts, rescues a miner and escapes, before the moving `crew_joins` check.

const ListsCheck := preload("res://acceptance/checks/end_screen_lists_check.gd")
const BASE: String = "Press A: return to base"


static func _lists() -> EndScreenLists:
	return EndScreenLists.new(EndScreenListsLook.FALLBACK, {"cell_salts": "Cell Salts"})


func test_lists_that_follow_the_flight_pass() -> String:
	var lists: EndScreenLists = _lists()
	var shown: String = lists.escape_text({"cell_salts": 2}, 1)
	var verdict: Array = ListsCheck.judge(lists, shown, {"cell_salts": 2}, 1, BASE, false, "Press A to fly again")
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "verdict %s" % [verdict]
	return ""


func test_a_flight_without_a_pickup_or_rescue_fails() -> String:
	var lists: EndScreenLists = _lists()
	var verdict: Array = ListsCheck.judge(lists, lists.escape_text({"cell_salts": 2}, 0), {"cell_salts": 2}, 0,
		BASE, false, "")
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not String(verdict[1]).contains("rescue"):
		return "verdict %s" % [verdict]
	return ""


func test_lists_out_of_step_with_the_sim_fail() -> String:
	var lists: EndScreenLists = _lists()
	var stale: Array = ListsCheck.judge(lists, lists.escape_text({"cell_salts": 1}, 1), {"cell_salts": 2}, 1,
		BASE, false, "")
	var empty: Array = ListsCheck.judge(lists, "", {"cell_salts": 2}, 1, BASE, false, "")
	if stale[0] != AcceptanceReport.RESULT_FAIL or empty[0] != AcceptanceReport.RESULT_FAIL:
		return "verdicts %s and %s" % [stale, empty]
	return ""


func test_a_base_prompt_without_the_words_or_out_of_place_fails() -> String:
	var lists: EndScreenLists = _lists()
	var shown: String = lists.escape_text({"cell_salts": 2}, 1)
	var restart: Array = ListsCheck.judge(lists, shown, {"cell_salts": 2}, 1, "Press A to restart", false, "")
	var early: Array = ListsCheck.judge(lists, shown, {"cell_salts": 2}, 1, BASE, false, BASE)
	var missed: Array = ListsCheck.judge(lists, shown, {"cell_salts": 2}, 1, BASE, true, "Press A to fly again")
	for verdict: Array in [restart, early, missed]:
		if verdict[0] != AcceptanceReport.RESULT_FAIL:
			return "verdict %s" % [verdict]
	return ""


func test_the_pickup_look_step_lists_the_check_before_crew_joins() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return "the m6 suite did not load"
	for step: AcceptanceStep in found[0].steps:
		if step.id == "pickup_look":
			var at: int = step.checks.find(ListsCheck.CHECK)
			if at < 0 or at > step.checks.find(AcceptanceStep.CHECK_CREW_JOINS):
				return "pickup_look checks %s" % [step.checks]
			return ""
	return "the m6 suite has no pickup_look step"
