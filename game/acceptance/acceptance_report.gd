class_name AcceptanceReport
extends RefCounted

## The outcome of one acceptance suite run (DEV-6): which build ran on which
## device, and each step's result, message and measurements. It is written as
## JSON so a script can read it from app storage or from the device log.

const RESULT_PASS: String = "pass"
const RESULT_FAIL: String = "fail"
const RESULT_SKIPPED: String = "skipped"
const RESULTS: Array[String] = [RESULT_PASS, RESULT_FAIL, RESULT_SKIPPED]

## The report is echoed to the log between these lines, so it can be cut out
## of `adb logcat` or a CI log without knowing anything else about the output.
const LOG_BEGIN: String = "MELTDOWN_ACCEPTANCE_BEGIN"
const LOG_END: String = "MELTDOWN_ACCEPTANCE_END"

var build_commit: String = ""
var device_name: String = ""
var suite_name: String = ""
## One Dictionary per step, in the order the steps ran: id, result, message,
## measurements.
var steps: Array[Dictionary] = []
## Why the last `write_file` failed, or "".
var write_error: String = ""


func _init(p_suite_name: String = "", p_build_commit: String = "", p_device_name: String = "") -> void:
	suite_name = p_suite_name
	build_commit = p_build_commit
	device_name = p_device_name


## Records one step. Returns false, recording nothing, if `result` is not one
## of RESULTS: an unknown result must not count as a pass.
func add_step(id: String, result: String, message: String = "", measurements: Dictionary = {}) -> bool:
	if not RESULTS.has(result):
		return false
	steps.append({
		"id": id,
		"result": result,
		"message": message,
		"measurements": measurements.duplicate(true),
	})
	return true


## True only if at least one step ran and none failed. A run in which every
## step was skipped proved nothing, so it does not pass.
func passed() -> bool:
	var ran: bool = false
	for step: Dictionary in steps:
		if step["result"] == RESULT_FAIL:
			return false
		if step["result"] == RESULT_PASS:
			ran = true
	return ran


## The step result from its checks' results: any fail fails, otherwise any
## pass passes, otherwise (every check skipped, or none) it is skipped.
static func combine(results: Array[String]) -> String:
	if results.has(RESULT_FAIL):
		return RESULT_FAIL
	return RESULT_PASS if results.has(RESULT_PASS) else RESULT_SKIPPED


## True only if there is a report and every report passed.
static func all_passed(reports: Array[AcceptanceReport]) -> bool:
	for report: AcceptanceReport in reports:
		if not report.passed():
			return false
	return not reports.is_empty()


## Writes the report as `<suite>-<commit>.json` in `dir`. Returns the path
## written, or "" with the reason in `write_error`.
func write_file(dir: String, short_commit: String) -> String:
	var path: String = dir.path_join("%s-%s.json" % [suite_name, short_commit])
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		write_error = "cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]
		return ""
	file.store_string(to_json() + "\n")
	file.close()
	write_error = ""
	return path


func to_dictionary() -> Dictionary:
	return {
		"suite": suite_name,
		"build_commit": build_commit,
		"device": device_name,
		"passed": passed(),
		"steps": steps.duplicate(true),
	}


## Keys are sorted at every level, measurements included, so two reports of
## the same run are byte-identical and can be compared with a plain diff.
func to_json() -> String:
	return JSON.stringify(to_dictionary(), "\t", true)


## The JSON between the begin and end markers, one log line per JSON line:
## a single long line could be cut short by the Android log.
func to_log_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray([LOG_BEGIN])
	lines.append_array(to_json().split("\n"))
	lines.append(LOG_END)
	return lines
