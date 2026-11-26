extends RefCounted

## The `docs/checklists/` copy of each shipped checklist (#1325) is generated
## from it; this fails when one was edited without running
## `tools/checklist_docs.sh`, so the headset and the docs cannot drift.


func test_every_shipped_checklist_matches_its_docs_copy() -> String:
	for path: String in Checklist.files():
		var checklist: Checklist = Checklist.load_file(path)
		var copy: String = ChecklistMarkdown.docs_path(checklist)
		if not FileAccess.file_exists(copy):
			return "no %s; run tools/checklist_docs.sh" % copy
		if FileAccess.get_file_as_string(copy) != ChecklistMarkdown.render(checklist, path):
			return "%s differs from %s; run tools/checklist_docs.sh" % [copy, path]
	return ""


func test_the_copy_lists_every_step_with_its_action() -> String:
	var checklist: Checklist = ChecklistFixtures.checklist()
	var text: String = ChecklistMarkdown.render(checklist, "res://t1.json")
	for want: String in ["# T", "## P", "1. **A** (`a`)", "set comfort preset 1", "3. **C** (`c`)",
			"fly seed #31", "issue #7", "meltdown_checklist_t1.json"]:
		if not text.contains(want):
			return "no \"%s\" in\n%s" % [want, text]
	return ""
