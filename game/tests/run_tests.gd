extends SceneTree

## Minimal unit test runner (see docs/decisions/0001-initial-decisions.md).
##
## Loads every res://tests/test_*.gd, creates one instance, and calls each
## method whose name starts with "test_". A test returns "" on success or a
## failure message. Exit code is 0 only if at least one test ran and none failed.

const TESTS_DIR: String = "res://tests"


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
		var script: GDScript = load(TESTS_DIR + "/" + file) as GDScript
		if script == null or not script.can_instantiate():
			failures += 1
			printerr("FAIL ", file, " - could not load script")
			continue
		var instance: Object = script.new()
		for method: Dictionary in instance.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			count += 1
			var message: String = str(instance.call(method_name))
			if message == "":
				print("PASS ", file, "::", method_name)
			else:
				failures += 1
				printerr("FAIL ", file, "::", method_name, " - ", message)
	print(count, " tests, ", failures, " failed")
	if count == 0:
		printerr("No tests found")
		quit(1)
	elif failures > 0:
		quit(1)
	else:
		quit(0)
