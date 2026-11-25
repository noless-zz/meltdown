extends RefCounted

## The m6 `tally_counts` acceptance check (#1356, DEV-6): judged on fed tallies,
## and listed on the `pickup_look` step, whose flight collects cell salts and
## rescues a miner, before the moving `crew_joins` check.

const TallyCheck := preload("res://acceptance/checks/tally_check.gd")


static func _flown(collected: Dictionary, rescued: int) -> StatusPanelTally:
	var tally: StatusPanelTally = StatusPanelTally.new(StatusPanelLook.FALLBACK, {"cell_salts": "Cell Salts"})
	tally.update({}, 0, {}, true)
	tally.update(collected, rescued, {}, true)
	return tally


func test_a_tally_that_followed_the_flight_passes() -> String:
	var tally: StatusPanelTally = _flown({"cell_salts": 2}, 1)
	var verdict: Array = TallyCheck.judge(tally, tally.row_text(), {"cell_salts": 2}, 1)
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "verdict %s" % [verdict]
	return ""


func test_a_flight_without_a_pickup_or_rescue_fails() -> String:
	var tally: StatusPanelTally = _flown({"cell_salts": 2}, 0)
	var verdict: Array = TallyCheck.judge(tally, tally.row_text(), {"cell_salts": 2}, 0)
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not String(verdict[1]).contains("rescue"):
		return "verdict %s" % [verdict]
	return ""


func test_a_count_or_line_out_of_step_fails() -> String:
	var tally: StatusPanelTally = _flown({"cell_salts": 2}, 1)
	var counted: Array = TallyCheck.judge(tally, tally.row_text(), {"cell_salts": 3}, 1)
	var shown: Array = TallyCheck.judge(tally, "Hold empty", {"cell_salts": 2}, 1)
	if counted[0] != AcceptanceReport.RESULT_FAIL or shown[0] != AcceptanceReport.RESULT_FAIL:
		return "verdicts %s and %s" % [counted, shown]
	return ""


func test_an_unconfirmed_rescue_fails() -> String:
	var tally: StatusPanelTally = StatusPanelTally.new(StatusPanelLook.FALLBACK)
	# The first frame only remembers, so a rescue already counted is not confirmed.
	tally.update({"cell_salts": 2}, 1, {}, true)
	var verdict: Array = TallyCheck.judge(tally, tally.row_text(), {"cell_salts": 2}, 1)
	if verdict[0] != AcceptanceReport.RESULT_FAIL:
		return "verdict %s" % [verdict]
	return ""


func test_the_pickup_look_step_lists_the_check_before_crew_joins() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return "the m6 suite did not load"
	for step: AcceptanceStep in found[0].steps:
		if step.id == "pickup_look":
			var at: int = step.checks.find(TallyCheck.CHECK)
			if at < 0 or at > step.checks.find(AcceptanceStep.CHECK_CREW_JOINS):
				return "pickup_look checks %s" % [step.checks]
			return ""
	return "m6 has no pickup_look step"
