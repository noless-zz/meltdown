extends RefCounted

## Fixture for `test_run_tests_runner.gd`: calls a method on null, then would
## return "". The runner must count it as failed (issue #140).


func test_calls_a_method_on_null() -> String:
	var node: Node = null
	node.set_name("never")
	return ""
