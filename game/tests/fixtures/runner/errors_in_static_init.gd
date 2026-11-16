extends RefCounted

## Fixture for `test_run_tests_runner.gd`: a static variable initialiser
## indexes past the end of an array while the script loads. The runner must
## fail the file for the load-time error and still run its test (issue #171).

static var _first_word: String = _pick_word()


static func _pick_word() -> String:
	var words: Array[String] = []
	return words[3]


func test_passes() -> String:
	return ""
