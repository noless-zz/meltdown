extends RefCounted

## The `checklist` acceptance check (#1325, DEV-6): passes when A marks the
## first step and the results file is written, leaves the owner's marks alone,
## and in a release build passes only when the page and its row are absent.

const Check := preload("res://acceptance/checks/checklist_check.gd")
const Wired := preload("res://tests/test_checklist_wiring.gd")


func test_a_development_build_marks_and_saves_through_a() -> String:
	var pair: Array = Wired.wired([])
	var checklist: ChecklistWiring = pair[1]
	var owners: ChecklistSession = checklist.session
	var measurements: Dictionary = {}
	var verdict: Array = Check.judge_wiring(checklist, pair[0], "abc123", measurements)
	var problem: String = ""
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		problem = "verdict %s" % [verdict]
	elif checklist.session != owners or not owners.marks.is_empty() or checklist.store.prefix != Wired.SCRATCH:
		problem = "the owner's session or store was changed"
	elif checklist.is_open() or measurements.get("checklist_steps") != 3:
		problem = "page open %s, measurements %s" % [checklist.is_open(), measurements]
	Wired.done(pair)
	return problem


func test_a_release_build_passes_with_nothing_attached() -> String:
	var pair: Array = Wired.wired([], false)
	var verdict: Array = Check.judge_wiring(pair[1], pair[0], "abc123", {})
	Wired.done(pair)
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS and str(verdict[1]).contains("release") else "verdict %s" % [verdict]


func test_a_development_build_without_a_checklist_fails() -> String:
	var checklist: ChecklistWiring = ChecklistWiring.new()
	checklist.available = true
	var verdict: Array = Check.judge_wiring(checklist, null, "abc123", {})
	return "" if verdict[0] == AcceptanceReport.RESULT_FAIL else "verdict %s" % [verdict]
