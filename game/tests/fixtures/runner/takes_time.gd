extends RefCounted

## Fixture for `test_run_tests_runner.gd`: one passing test that waits a few
## milliseconds, so the file's measured time cannot round to nothing (issue #1138).


func test_waits_a_little() -> String:
	OS.delay_msec(20)
	return ""
