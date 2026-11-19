class_name FakeUpdateTransport
extends UpdateTransport

## Stands in for the network in the update tests: records every request and
## answers at once with `result`, `http_code` and `body`, or holds the answer
## until `answer()` when `deferred` is set. No test reaches GitHub.

var result: int = HTTPRequest.RESULT_SUCCESS
var http_code: int = 200
var body: String = ""
var deferred: bool = false
var start_error: int = OK
var urls: Array[String] = []
var timeouts: Array[float] = []
var headers: Array[PackedStringArray] = []

var _pending: Callable = Callable()


func send(url: String, p_headers: PackedStringArray, timeout_seconds: float, done: Callable) -> int:
	urls.append(url)
	timeouts.append(timeout_seconds)
	headers.append(p_headers)
	if start_error != OK:
		return start_error
	if deferred:
		_pending = done
	else:
		done.call(result, http_code, body)
	return OK


## Answers the held request, if any.
func answer() -> void:
	var done: Callable = _pending
	_pending = Callable()
	if done.is_valid():
		done.call(result, http_code, body)
