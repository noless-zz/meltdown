extends Logger

## Collects the script errors Godot reports while a test runs (issue #140).
##
## A test method that hits a script error is aborted and returns its type's
## default, `""` for `-> String`, which the runner would read as a pass. The
## runner registers one of these with `OS.add_logger()` so the error itself
## marks the test failed.
##
## Only `ERROR_TYPE_SCRIPT` counts. Pushed warnings stay warnings, and engine
## errors (`push_error`, a rejected file) are left to the test's own checks,
## since several tests feed bad data on purpose.
##
## Captures nest: `test_run_tests_runner.gd` runs fixture files through the
## runner while the outer run is capturing that test. An error goes only to the
## innermost capture, so a fixture's deliberate error does not fail the test
## that checks it. Godot may call a logger from any thread, hence the mutex.

var _mutex: Mutex = Mutex.new()
var _stack: Array[PackedStringArray] = []


## Starts a new, innermost capture.
func push() -> void:
	_mutex.lock()
	_stack.append(PackedStringArray())
	_mutex.unlock()


## Ends the innermost capture and returns the errors it collected.
func pop() -> PackedStringArray:
	_mutex.lock()
	var errors: PackedStringArray = PackedStringArray()
	if not _stack.is_empty():
		errors = _stack.pop_back()
	_mutex.unlock()
	return errors


func depth() -> int:
	_mutex.lock()
	var result: int = _stack.size()
	_mutex.unlock()
	return result


func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	var message: String = rationale if rationale != "" else code
	var where: String = "%s:%d in %s()" % [file.get_file(), line, function]
	_mutex.lock()
	if not _stack.is_empty():
		_stack[_stack.size() - 1].append("%s (%s)" % [message, where])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
