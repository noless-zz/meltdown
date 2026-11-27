class_name AcceptanceRunOutput
extends RefCounted

## What an acceptance run leaves for the PC scripts besides the suite reports (#1444, DEV-6):
## the position fields on each step line, and `acceptance_exit.json` next to the reports. A
## script that lost the log stream can still read the result from that file (#1436, #1438).

const EXIT_FILE: String = "acceptance_exit.json"


## Appended to each step line after the existing text, so `step <id>` and `step <id> <result>`
## still parse: `suite=m1 index=3 count=9`, the index counting from 1.
static func step_fields(suite_name: String, index: int, count: int) -> String:
	return "suite=%s index=%d count=%d" % [suite_name, index + 1, count]


## The exit file's fields: the build, every suite that ran, and which of them passed, failed or
## were skipped (no steps), the exit code the log line also prints, and the finish time in UTC.
static func exit_data(build_commit: String, reports: Array[AcceptanceReport], code: int,
		finished_utc: String) -> Dictionary:
	var suites: Array[String] = []
	var passed: Array[String] = []
	var failed: Array[String] = []
	var skipped: Array[String] = []
	for report: AcceptanceReport in reports:
		suites.append(report.suite_name)
		if report.skipped():
			skipped.append(report.suite_name)
		elif report.passed():
			passed.append(report.suite_name)
		else:
			failed.append(report.suite_name)
	return {
		"build": build_commit,
		"suites": suites,
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"exit_code": code,
		"finished": finished_utc,
	}


## Now, as `2026-11-27T08:15:00Z`.
static func now_utc() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## Writes a suite's report to `dir` and echoes it through `say`, one log line at a time. A failed
## write is said; the log still has the report. Returns the path written, or "".
static func write_report(report: AcceptanceReport, dir: String, short_commit: String, say: Callable) -> String:
	var path: String = report.write_file(dir, short_commit)
	if path == "":
		say.call("%s: %s" % [AcceptanceRunner.LOG_PREFIX, report.write_error])
	for line: String in report.to_log_lines():
		say.call(line)
	return path


## Writes `data` as EXIT_FILE in `dir`. Returns the path, or "" after saying why through `say`.
static func write_exit(dir: String, data: Dictionary, say: Callable) -> String:
	var path: String = dir.path_join(EXIT_FILE)
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		say.call("%s: cannot write %s: %s" % [AcceptanceRunner.LOG_PREFIX, path,
			error_string(FileAccess.get_open_error())])
		return ""
	file.store_string(JSON.stringify(data, "\t", true) + "\n")
	file.close()
	return path
