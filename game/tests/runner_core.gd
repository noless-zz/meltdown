extends RefCounted

## The per-file logic of `run_tests.gd`, kept apart so `test_run_tests_runner.gd`
## can run fixture files through exactly the code the suite uses (issue #140).
##
## `run_file()` loads one test script, calls each `test_*` method and returns
## the outcome as data; the caller prints it. A method fails when it returns
## anything but `""`, or when a script error was raised while it ran, whatever
## it returned. A file whose loading or instantiation raised a script error
## (in `_init` or a static initialiser) counts one extra failure, and its
## methods still run (issue #171).

const ScriptErrorLogger := preload("res://tests/script_error_logger.gd")

## Shared by nested captures; registered while at least one capture is open.
static var _logger: ScriptErrorLogger = null


## Runs every `test_*` method of the script at `path`. Returns
## `{"count": int, "failures": int, "lines": Array[String], "ms": int}`, where
## each line starts with `PASS ` or `FAIL ` and is named by `label` (the file
## name), and `ms` is the file's wall time including loading (issue #1138).
static func run_file(path: String, label: String) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var result: Dictionary = _run_file_untimed(path, label)
	result["ms"] = (Time.get_ticks_usec() - started_usec) / 1000
	return result


## Returns up to `limit` lines `SLOW <ms> <file>` for the files in `times`
## (file name to milliseconds), longest first, ties by name so the CI log is
## stable. The suite prints them so the costly files can be found and cut.
static func slow_lines(times: Dictionary, limit: int) -> Array[String]:
	var files: Array = times.keys()
	files.sort_custom(func(a: Variant, b: Variant) -> bool:
		if times[a] != times[b]:
			return times[a] > times[b]
		return str(a) < str(b))
	var lines: Array[String] = []
	for file: Variant in files.slice(0, maxi(limit, 0)):
		lines.append("SLOW %d %s" % [times[file], file])
	return lines


static func _run_file_untimed(path: String, label: String) -> Dictionary:
	var lines: Array[String] = []
	var count: int = 0
	var failures: int = 0
	_begin_capture()
	var script: GDScript = load(path) as GDScript
	var instance: Object = null
	if script != null and script.can_instantiate():
		instance = script.new()
	var load_errors: PackedStringArray = _end_capture()
	# A script that does not load at all gets only this line; its parse errors
	# are already printed above it.
	if instance == null:
		lines.append("FAIL %s - could not load script" % label)
		return {"count": 0, "failures": 1, "lines": lines}
	if not load_errors.is_empty():
		failures += 1
		lines.append("FAIL %s - script error while loading: %s" % [label, "; ".join(load_errors)])
	for method: Dictionary in instance.get_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with("test_"):
			continue
		count += 1
		var message: String = run_method(instance, method_name)
		if message == "":
			lines.append("PASS %s::%s" % [label, method_name])
		else:
			failures += 1
			lines.append("FAIL %s::%s - %s" % [label, method_name, message])
	return {"count": count, "failures": failures, "lines": lines}


## Calls one test method. Returns "" on a pass, otherwise the failure message.
static func run_method(instance: Object, method_name: String) -> String:
	_begin_capture()
	var result: Variant = instance.call(method_name)
	var errors: PackedStringArray = _end_capture()
	if not errors.is_empty():
		return "script error: %s" % "; ".join(errors)
	return str(result)


static func _begin_capture() -> void:
	if _logger == null:
		_logger = ScriptErrorLogger.new()
		OS.add_logger(_logger)
	_logger.push()


static func _end_capture() -> PackedStringArray:
	var errors: PackedStringArray = _logger.pop()
	if _logger.depth() == 0:
		OS.remove_logger(_logger)
		_logger = null
	return errors
