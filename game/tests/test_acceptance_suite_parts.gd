extends RefCounted

## Suite parts (#1297, DEV-6, ARC-4): a suite's `include` list adds the steps of
## part files in a subfolder after its own, parts are never suites of their own,
## a bad part stops the suite loading with the file named, and a suite with no
## steps at all is skipped rather than passed.

const SCRATCH_DIR: String = "user://test_acceptance_suite_parts"


static func _step(id: String) -> String:
	return "{\"id\": \"%s\", \"checks\": [\"xr_session\"]}" % id


static func _part(ids: Array[String]) -> String:
	var steps: PackedStringArray = PackedStringArray()
	for id: String in ids:
		steps.append(_step(id))
	return "{\"steps\": [%s]}" % ", ".join(steps)


## Empties SCRATCH_DIR and its subfolders, then writes `files` (path inside it to text).
static func _scratch(files: Dictionary[String, String]) -> String:
	_clear(SCRATCH_DIR)
	for file_name: String in files:
		var path: String = SCRATCH_DIR.path_join(file_name)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(files[file_name])
		file.close()
	return SCRATCH_DIR


static func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(sub))
		DirAccess.remove_absolute(dir.path_join(sub))
	for old: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(old))


static func _ids(suite: AcceptanceSuite) -> Array[String]:
	var ids: Array[String] = []
	for step: AcceptanceStep in suite.steps:
		ids.append(step.id)
	return ids


func test_parts_run_after_the_suite_in_the_listed_order() -> String:
	var dir: String = _scratch({
		"s.json": "{\"name\": \"s\", \"steps\": [%s], \"include\": [\"s/two\", \"s/one\"]}" % _step("own"),
		"s/one.json": _part(["one_a", "one_b"]),
		"s/two.json": _part(["two_a"]),
	})
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("s", dir)
	if found.size() != 1 or found[0].error != "":
		return "s did not load: %s" % (found[0].error if found.size() == 1 else str(found.size()))
	if _ids(found[0]) != ["own", "two_a", "one_a", "one_b"]:
		return "steps ran in the order %s" % [_ids(found[0])]
	if found[0].name != "s" or found[0].includes != ["s/two", "s/one"]:
		return "suite %s includes %s" % [found[0].name, found[0].includes]
	return ""


func test_a_suite_with_parts_may_list_no_steps_of_its_own() -> String:
	var dir: String = _scratch({
		"s.json": "{\"name\": \"s\", \"steps\": [], \"include\": [\"x/p\"]}",
		"x/p.json": _part(["a"]),
	})
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("s", dir)[0]
	if suite.error != "" or _ids(suite) != ["a"]:
		return "got '%s' with %s" % [suite.error, _ids(suite)]
	return ""


func test_files_in_subfolders_are_never_suites_of_their_own() -> String:
	var dir: String = _scratch({
		"a.json": "{\"name\": \"a\", \"steps\": [%s]}" % _step("x"),
		"a/part.json": _part(["y"]),
		"b/b.json": "{\"name\": \"b\", \"steps\": [%s]}" % _step("z"),
	})
	for asked: String in [AcceptanceSuite.ALL, AcceptanceSuite.NIGHTLY]:
		var names: Array[String] = []
		for suite: AcceptanceSuite in AcceptanceSuite.load_named(asked, dir):
			names.append(suite.name if suite.error == "" else suite.error)
		if names != ["a"]:
			return "%s gave %s" % [asked, names]
	if AcceptanceSuite.load_named("a/part", dir)[0].error == "":
		return "a part loaded as a suite by name"
	return ""


## "" if suite `s` in a scratch folder of `files` fails to load naming `names`.
func _expect_rejected(files: Dictionary[String, String], names: String) -> String:
	var dir: String = _scratch(files)
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("s", dir)
	if found.size() != 1 or found[0].error == "":
		return "accepted %s" % [files.keys()]
	if not found[0].error.contains(names):
		return "error '%s' does not name %s" % [found[0].error, names]
	if not found[0].steps.is_empty():
		return "a rejected suite kept %d steps" % found[0].steps.size()
	if not AcceptanceSuite.unreadable(found).begins_with("cannot run"):
		return "a rejected suite would still fly: %s" % AcceptanceSuite.unreadable(found)
	return ""


static func _including(part: String) -> String:
	return "{\"name\": \"s\", \"steps\": [%s], \"include\": [%s]}" % [_step("own"), part]


func test_a_missing_part_stops_the_suite_naming_the_file() -> String:
	return _expect_rejected({"s.json": _including("\"s/gone\"")}, "s/gone.json")


func test_an_unreadable_part_stops_the_suite_naming_the_file() -> String:
	var cases: Dictionary[String, String] = {
		"{\"steps\": [": "invalid JSON",
		"[]": "JSON object",
		"{\"steps\": [], \"name\": \"p\"}": "name: unknown key",
		"{}": "steps",
		"{\"steps\": [{\"id\": \"a\", \"checks\": [\"nope\"]}]}": "unknown check",
	}
	for text: String in cases:
		var problem: String = _expect_rejected({"s.json": _including("\"s/p\""), "s/p.json": text}, "s/p.json")
		if problem == "":
			problem = _expect_rejected({"s.json": _including("\"s/p\""), "s/p.json": text}, cases[text])
		if problem != "":
			return "%s: %s" % [text, problem]
	return ""


func test_a_part_that_is_not_a_plain_name_is_rejected() -> String:
	for bad: String in ["\"p\"", "\"../p\"", "\"s/../p\"", "\"s/p/q\"", "\"S/p\"", "\"s/\"", "3", "\"s/p.json\""]:
		var problem: String = _expect_rejected({"s.json": _including(bad), "s/p.json": _part([])}, "include[0]")
		if problem != "":
			return "%s: %s" % [bad, problem]
	var listed_twice: String = _expect_rejected(
		{"s.json": _including("\"s/p\", \"s/p\""), "s/p.json": _part([])}, "include[1]")
	if listed_twice != "":
		return "a part listed twice: %s" % listed_twice
	return _expect_rejected({"s.json": "{\"name\": \"s\", \"steps\": [], \"include\": \"s/p\"}"}, "include")


func test_a_step_id_used_twice_across_suite_and_parts_is_rejected() -> String:
	var problem: String = _expect_rejected({"s.json": _including("\"s/p\""), "s/p.json": _part(["own"])},
		"s/p.json")
	if problem != "":
		return "suite and part: %s" % problem
	problem = _expect_rejected({"s.json": _including("\"s/p\", \"s/q\""), "s/p.json": _part(["a"]),
		"s/q.json": _part(["b", "a"])}, "s/q.json: steps[1].id")
	if problem != "":
		return "two parts: %s" % problem
	return ""


func test_a_suite_with_no_steps_and_no_parts_is_still_rejected() -> String:
	return _expect_rejected({"s.json": "{\"name\": \"s\", \"steps\": []}"}, "steps")


## Two parts per lane, and lane-c's `menu` (#1457) beside `look` and `base`.
func test_the_shipped_m6_suite_includes_two_parts_per_lane() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return "m6 did not load: %s" % (found[0].error if found.size() == 1 else str(found.size()))
	var wanted: Array[String] = ["m6/ship", "m6/perf", "m6/sound", "m6/effects", "m6/look", "m6/base", "m6/menu"]
	if found[0].name != "m6" or found[0].includes != wanted:
		return "m6 includes %s" % [found[0].includes]
	return ""


func test_a_suite_with_no_steps_is_skipped_not_passed() -> String:
	var dir: String = _scratch({
		"e.json": "{\"name\": \"e\", \"steps\": [], \"include\": [\"e/p\"]}",
		"e/p.json": _part([]),
	})
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("e", dir)[0]
	if suite.error != "" or not suite.steps.is_empty():
		return "e loaded with '%s' and %d steps" % [suite.error, suite.steps.size()]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var suites: Array[AcceptanceSuite] = [suite]
	runner.setup(null, suites, null)
	for frame: int in 10:
		runner.process_frame()
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_FAIL:
		problem = "an empty suite alone finished %s with exit %d" % [runner.finished, runner.exit_code]
	elif runner.reports.size() != 1 or not runner.reports[0].skipped() or runner.reports[0].passed():
		problem = "the empty suite's report was not skipped"
	else:
		var data: Dictionary = runner.reports[0].to_dictionary()
		if data.get("message") != AcceptanceReport.NO_STEPS or data.get("result") != AcceptanceReport.RESULT_SKIPPED:
			problem = "report said %s" % str(data)
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	runner.free()
	return problem


func test_an_empty_suite_does_not_fail_a_run_that_passed() -> String:
	var passed: AcceptanceReport = AcceptanceReport.new("p")
	passed.add_step("a", AcceptanceReport.RESULT_PASS)
	var empty: AcceptanceReport = AcceptanceReport.new("e")
	var failed: AcceptanceReport = AcceptanceReport.new("f")
	failed.add_step("a", AcceptanceReport.RESULT_FAIL)
	if not AcceptanceReport.all_passed([passed, empty] as Array[AcceptanceReport]):
		return "an empty suite failed a run that passed"
	if AcceptanceReport.all_passed([empty] as Array[AcceptanceReport]):
		return "a run of only an empty suite passed"
	if AcceptanceReport.all_passed([passed, empty, failed] as Array[AcceptanceReport]):
		return "a failed suite passed beside an empty one"
	if passed.to_dictionary().has("message") or passed.to_dictionary().has("result"):
		return "a report with steps gained keys: %s" % str(passed.to_dictionary().keys())
	return ""
