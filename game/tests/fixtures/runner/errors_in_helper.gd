extends RefCounted

## Fixture for `test_run_tests_runner.gd`: the error is in a helper. Godot
## aborts only the helper, and the test goes on to return "". The runner must
## still count it as failed (issue #140).


func test_errors_in_a_helper() -> String:
	_helper()
	return ""


func _helper() -> void:
	var table: Dictionary = {}
	var missing: Object = table.get("missing")
	missing.free()
