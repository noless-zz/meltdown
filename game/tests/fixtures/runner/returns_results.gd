extends RefCounted

## Fixture for `test_run_tests_runner.gd`: two correct tests, one of which pushes
## a warning, must pass; one that returns a message must fail (issue #140).


func test_passes() -> String:
	return ""


func test_passes_with_a_warning() -> String:
	push_warning("fixture warning, expected")
	return ""


func test_fails_by_message() -> String:
	return "expected message"
