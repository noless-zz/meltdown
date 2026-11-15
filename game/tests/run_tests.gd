extends SceneTree

## Minimal unit test runner (see docs/decisions/0001-initial-decisions.md).
##
## Loads every res://tests/test_*.gd, creates one instance, and calls each
## method whose name starts with "test_". A test returns "" on success or a
## failure message. A script error raised while a test runs fails it whatever it
## returned (issue #140); the per-file logic lives in `runner_core.gd`. Exit code
## is 0 only if at least one test ran and none failed.

const TESTS_DIR: String = "res://tests"
const RunnerCore := preload("res://tests/runner_core.gd")


func _init() -> void:
	var failures: int = 0
	var count: int = 0
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
		var result: Dictionary = RunnerCore.run_file(TESTS_DIR + "/" + file, file)
		count += result["count"]
		failures += result["failures"]
		for line: String in result["lines"]:
			if line.begins_with("PASS "):
				print(line)
			else:
				printerr(line)
	print(count, " tests, ", failures, " failed")
	if count == 0:
		printerr("No tests found")
		quit(1)
	elif failures > 0:
		quit(1)
	else:
		quit(0)
