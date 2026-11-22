extends SceneTree

## Minimal unit test runner (see docs/decisions/0001-initial-decisions.md).
##
## Loads every res://tests/test_*.gd, creates one instance, and calls each
## method whose name starts with "test_". A test returns "" on success or a
## failure message. A script error raised while a test runs fails it whatever it
## returned (issue #140); the per-file logic lives in `runner_core.gd`. Exit code
## is 0 only if at least one test ran and none failed.
##
## After the totals it prints `SLOW <ms> <file>` for the slowest files and the
## total time, so the CI log shows where the job's minutes go (issue #1138).
## `-- --only=<prefix>` runs only files whose name starts with the prefix, for
## local runs; CI passes nothing and runs every file.

const TESTS_DIR: String = "res://tests"
const RunnerCore := preload("res://tests/runner_core.gd")
const SLOW_FILES_SHOWN: int = 15
const ONLY_FLAG: String = "--only="


func _init() -> void:
	var failures: int = 0
	var count: int = 0
	var times: Dictionary = {}
	var started_usec: int = Time.get_ticks_usec()
	var only: String = _only_prefix()
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	if dir == null:
		printerr("Cannot open ", TESTS_DIR)
		quit(1)
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		if not file.begins_with(only):
			continue
		var result: Dictionary = RunnerCore.run_file(TESTS_DIR + "/" + file, file)
		count += result["count"]
		failures += result["failures"]
		times[file] = result["ms"]
		for line: String in result["lines"]:
			if line.begins_with("PASS "):
				print(line)
			else:
				printerr(line)
	print(count, " tests, ", failures, " failed")
	for line: String in RunnerCore.slow_lines(times, SLOW_FILES_SHOWN):
		print(line)
	print("Total time ", (Time.get_ticks_usec() - started_usec) / 1000, " ms")
	if count == 0:
		printerr("No tests found")
		quit(1)
	elif failures > 0:
		quit(1)
	else:
		quit(0)


## The prefix given with `-- --only=<prefix>`, or "" (every file) without one.
static func _only_prefix() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(ONLY_FLAG):
			return arg.substr(ONLY_FLAG.length())
	return ""
