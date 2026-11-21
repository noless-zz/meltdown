extends RefCounted

## Which suites the nightly device run executes (#812, PRF-3, DEV-6): every
## suite that is not `manual_only`, so the 25-minute soak is left to a manual
## dispatch while `all` keeps every suite, the soak included.

const SCRATCH_DIR: String = "user://test_nightly_suites"
const STEP_JSON: String = "{\"id\": \"a\", \"checks\": [\"xr_session\"]}"


static func _names(found: Array[AcceptanceSuite]) -> Array[String]:
	var names: Array[String] = []
	for suite: AcceptanceSuite in found:
		names.append(suite.name if suite.error == "" else "error")
	return names


## A scratch suites folder holding exactly `files` (file name to text).
static func _scratch_dir(files: Dictionary[String, String]) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	for old: String in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(SCRATCH_DIR.path_join(old))
	for file_name: String in files:
		var file: FileAccess = FileAccess.open(SCRATCH_DIR.path_join(file_name), FileAccess.WRITE)
		file.store_string(files[file_name])
		file.close()
	return SCRATCH_DIR


static func _suite(suite_name: String, manual_only: String) -> String:
	var extra: String = "" if manual_only == "" else ", \"manual_only\": %s" % manual_only
	return "{\"name\": \"%s\", \"steps\": [%s]%s}" % [suite_name, STEP_JSON, extra]


func test_nightly_is_every_shipped_suite_but_the_soak() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named(AcceptanceSuite.NIGHTLY)
	if AcceptanceSuite.unreadable(found) != "":
		return AcceptanceSuite.unreadable(found)
	var names: Array[String] = _names(found)
	if names != ["m0", "m1", "m2", "m3"]:
		return "nightly gave %s" % [names]
	return ""


func test_all_still_includes_the_soak() -> String:
	var names: Array[String] = _names(AcceptanceSuite.load_named(AcceptanceSuite.ALL))
	if names != ["m0", "m1", "m2", "m3", "soak"]:
		return "all gave %s" % [names]
	return ""


func test_only_the_soak_is_manual_only() -> String:
	for suite: AcceptanceSuite in AcceptanceSuite.load_named(AcceptanceSuite.ALL):
		if suite.manual_only != (suite.name == "soak"):
			return "%s has manual_only %s" % [suite.name, suite.manual_only]
	return ""


func test_the_soak_still_runs_when_asked_for_by_name() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("soak")
	if found.size() != 1 or found[0].error != "" or found[0].name != "soak":
		return "soak gave %s" % [_names(found)]
	return ""


## A suite added later joins the nightly run without a workflow change, and a
## broken file is kept so the night fails on it instead of skipping it.
func test_nightly_takes_new_suites_and_keeps_broken_ones() -> String:
	var dir: String = _scratch_dir({
		"a.json": _suite("a", ""),
		"b.json": _suite("b", "true"),
		"c.json": _suite("c", "false"),
		"d.json": "{\"name\": \"d\", \"steps\": [",
	})
	var nightly: Array[String] = _names(AcceptanceSuite.load_named(AcceptanceSuite.NIGHTLY, dir))
	if nightly != ["a", "c", "error"]:
		return "nightly gave %s" % [nightly]
	var every: Array[String] = _names(AcceptanceSuite.load_named(AcceptanceSuite.ALL, dir))
	if every != ["a", "b", "c", "error"]:
		return "all gave %s" % [every]
	return ""


func test_manual_only_must_be_true_or_false() -> String:
	for bad: String in ["1", "\"yes\"", "null"]:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite("x", bad))
		if suite.error == "" or not suite.error.contains("manual_only"):
			return "manual_only %s gave '%s'" % [bad, suite.error]
	if AcceptanceSuite.parse_json(_suite("x", "false")).error != "":
		return "manual_only false was rejected"
	return ""
