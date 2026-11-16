extends RefCounted

## Fixture for `test_run_tests_runner.gd`: `_init` calls a method on null, but
## `new()` still returns an instance. The runner must fail the file for the
## load-time error and still run its test (issue #171).


func _init() -> void:
	var node: Node = null
	node.set_name("never")


func test_passes() -> String:
	return ""
