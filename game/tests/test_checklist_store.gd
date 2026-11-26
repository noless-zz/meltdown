extends RefCounted

## Checklist results on the headset (#1325, DEV-6): one JSON file per
## checklist at a fixed `user://` path, written after every mark and read back.

const SCRATCH: String = "user://test_checklist_store_"


static func store() -> ChecklistStore:
	var made: ChecklistStore = ChecklistStore.new()
	made.prefix = SCRATCH
	DirAccess.remove_absolute(made.path_for("t1"))
	return made


func test_the_results_path_is_fixed_per_checklist() -> String:
	var path: String = ChecklistStore.new().path_for("g6")
	return "" if path == "user://meltdown_checklist_g6.json" else path


func test_a_save_writes_the_results_and_a_new_session_takes_them_back() -> String:
	var saving: ChecklistStore = store()
	var session: ChecklistSession = ChecklistFixtures.session()
	session.mark(0, ChecklistSession.PASS, "", {"preset": 2, "source": ""}, "2026-11-26T08:00:00Z")
	var problem: String = saving.save(session, "abc123")
	if problem != "":
		return problem
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(saving.path_for("t1")))
	if typeof(data) != TYPE_DICTIONARY or data["build"] != "abc123" or data["steps"][0]["mark"] != "pass":
		return "file holds %s" % [data]
	var again: ChecklistSession = ChecklistFixtures.session()
	return "" if saving.load_into(again) == 1 and again.marks.has("a") else "took back %s" % again.marks


func test_a_broken_file_starts_afresh() -> String:
	var saving: ChecklistStore = store()
	var file: FileAccess = FileAccess.open(saving.path_for("t1"), FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	var session: ChecklistSession = ChecklistFixtures.session()
	return "" if saving.load_into(session) == 0 and session.marks.is_empty() else "took %s" % session.marks
