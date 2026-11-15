extends RefCounted

## Fixture for `test_run_tests_runner.gd`: does not parse, so the runner must
## report the file as failed (issue #140).


func test_never_runs() -> String
	return ""
