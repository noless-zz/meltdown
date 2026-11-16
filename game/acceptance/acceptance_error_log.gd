class_name AcceptanceErrorLog
extends Logger

## Counts the script errors Godot reports while an acceptance run is going,
## for the `no_script_errors` check (DEV-6, #165). The test runner has its own
## logger in `tests/`, which every export leaves out, so the game needs this one.
##
## Only `ERROR_TYPE_SCRIPT` counts, as in the test runner: engine errors and
## warnings are left to the checks that expect them. Godot may call a logger
## from any thread, hence the mutex.

var _mutex: Mutex = Mutex.new()
var _errors: PackedStringArray = PackedStringArray()


## Every script error seen so far, oldest first.
func errors() -> PackedStringArray:
	_mutex.lock()
	var copy: PackedStringArray = _errors.duplicate()
	_mutex.unlock()
	return copy


func count() -> int:
	_mutex.lock()
	var result: int = _errors.size()
	_mutex.unlock()
	return result


func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	var message: String = rationale if rationale != "" else code
	_mutex.lock()
	_errors.append("%s (%s:%d in %s())" % [message, file.get_file(), line, function])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
