extends RefCounted

## Fixture for `test_run_tests_runner.gd`: reads past the end of an array, then
## would return "". The runner must count it as failed (issue #140).


func test_indexes_past_the_end() -> String:
	var items: Array[int] = [1, 2]
	var value: int = items[items.size() + 1]
	return "" if value >= 0 else ""
