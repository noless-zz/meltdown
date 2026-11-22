extends RefCounted

## Check files (#1297, DEV-6, ARC-4): a script in `acceptance/checks/` adds
## checks a suite step may name and the runner judges, without an edit to
## `AcceptanceChecks` or `AcceptanceStep`; unknown names are still rejected,
## and a broken check file stops every suite with the file named.

const SCRATCH_DIR: String = "user://test_acceptance_check_files"

const GOOD_SCRIPT: String = """extends RefCounted

static func judges() -> Dictionary[String, Callable]:
	return {"%s": _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	measurements["judged"] = step.id
	return [AcceptanceReport.RESULT_PASS, "judged by a check file"]
"""


## A fresh scratch folder `name` holding `files` (file name to text), read as the check files.
## Each test uses its own folder: a loaded script stays cached by its path.
static func _use(name: String, files: Dictionary[String, String]) -> String:
	var dir: String = SCRATCH_DIR.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	for old: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(old))
	for file_name: String in files:
		var file: FileAccess = FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
		file.store_string(files[file_name])
		file.close()
	AcceptanceCheckFiles.use_dir(dir)
	return dir


static func _restore() -> void:
	AcceptanceCheckFiles.use_dir(AcceptanceCheckFiles.CHECKS_DIR)


static func _suite_with_check(check: String) -> AcceptanceSuite:
	return AcceptanceSuite.parse_json(
		"{\"name\": \"x\", \"steps\": [{\"id\": \"s\", \"checks\": [\"no_script_errors\", \"%s\"]}]}" % check)


func test_the_shipped_check_files_load() -> String:
	_restore()
	if AcceptanceCheckFiles.problem() != "":
		return AcceptanceCheckFiles.problem()
	return ""


func test_a_check_from_a_file_is_known_and_judged() -> String:
	_use("good", {"lane_check.gd": GOOD_SCRIPT % "lane_check"})
	var problem: String = _judged("lane_check")
	_restore()
	return problem


func _judged(check: String) -> String:
	if AcceptanceCheckFiles.problem() != "":
		return AcceptanceCheckFiles.problem()
	if not AcceptanceCheckFiles.known_checks().has(check) \
			or not AcceptanceCheckFiles.known_checks().has(AcceptanceStep.CHECK_XR_SESSION):
		return "known checks: %s" % [AcceptanceCheckFiles.known_checks()]
	var suite: AcceptanceSuite = _suite_with_check(check)
	if suite.error != "":
		return "a step naming %s was rejected: %s" % [check, suite.error]
	var checks: AcceptanceChecks = AcceptanceChecks.new()
	if not checks.judged_checks().has(check):
		return "%s is not judged" % check
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var measurements: Dictionary = {}
	var result: Array = checks.run(check, suite.steps[0], runner, measurements)
	runner.free()
	if result != [AcceptanceReport.RESULT_PASS, "judged by a check file"] or measurements.get("judged") != "s":
		return "%s gave %s measuring %s" % [check, str(result), str(measurements)]
	return ""


func test_an_unknown_check_is_still_rejected() -> String:
	_use("unknown", {"lane_check.gd": GOOD_SCRIPT % "other_check"})
	var suite: AcceptanceSuite = _suite_with_check("not_a_check")
	var answer: Array = AcceptanceChecks.new().run("not_a_check", AcceptanceStep.new(), null, {})
	_restore()
	if suite.error == "" or not suite.error.contains("steps[0].checks[1]"):
		return "an unknown check gave '%s'" % suite.error
	if not suite.error.contains("other_check"):
		return "the known list leaves out the file's check: %s" % suite.error
	if answer != [AcceptanceReport.RESULT_FAIL, AcceptanceChecks.UNKNOWN_CHECK]:
		return "running an unknown check gave %s" % str(answer)
	return ""


func test_a_broken_check_file_stops_every_suite_naming_it() -> String:
	var cases: Dictionary[String, String] = {
		"no_judges.gd": "extends RefCounted\n",
		"not_static.gd": "extends RefCounted\n\nfunc judges() -> Dictionary:\n\treturn {}\n",
		"node.gd": "extends Node\n\nstatic func judges() -> Dictionary:\n\treturn {}\n",
		"not_a_dict.gd": "extends RefCounted\n\nstatic func judges() -> Array:\n\treturn []\n",
		"builtin.gd": GOOD_SCRIPT % AcceptanceStep.CHECK_XR_SESSION,
		"bad_name.gd": GOOD_SCRIPT % "Bad Name",
		"no_judge.gd": "extends RefCounted\n\nstatic func judges() -> Dictionary:\n\treturn {\"c\": 3}\n",
	}
	for file_name: String in cases:
		_use("broken_" + file_name.get_basename(), {file_name: cases[file_name]})
		var problem: String = AcceptanceCheckFiles.problem()
		var suite: AcceptanceSuite = AcceptanceSuite.load_named("m1")[0]
		_restore()
		if problem == "" or not problem.contains(file_name):
			return "%s gave '%s'" % [file_name, problem]
		if suite.error == "" or not suite.error.contains(file_name):
			return "%s: the m1 suite still loaded ('%s')" % [file_name, suite.error]
	return ""


func test_two_files_may_not_register_the_same_check() -> String:
	_use("twice", {"a.gd": GOOD_SCRIPT % "same_check", "b.gd": GOOD_SCRIPT % "same_check"})
	var problem: String = AcceptanceCheckFiles.problem()
	_restore()
	if not problem.contains("b.gd") or not problem.contains("same_check"):
		return "a check registered twice gave '%s'" % problem
	return ""


func test_files_are_read_in_name_order_and_only_scripts() -> String:
	_use("order", {"b.gd": GOOD_SCRIPT % "b_check", "a.gd": GOOD_SCRIPT % "a_check", "notes.txt": "x"})
	var names: Array = AcceptanceCheckFiles.judges().keys()
	var problem: String = AcceptanceCheckFiles.problem()
	_restore()
	if problem != "" or names != ["a_check", "b_check"]:
		return "read %s ('%s')" % [names, problem]
	return ""
