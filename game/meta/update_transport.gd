class_name UpdateTransport
extends RefCounted

## The one network call the update check makes (#646), behind an interface so
## the tests can fake it and no test ever reaches GitHub. `HttpUpdateTransport`
## is the real one.


## Starts a GET of `url` that gives up after `timeout_seconds`, and returns
## `OK` when it started. When it ends, successfully or not, it calls
## `done.call(result: int, http_code: int, body: String)` exactly once, where
## `result` is an `HTTPRequest.Result` value. This base class sends nothing.
func send(_url: String, _headers: PackedStringArray, _timeout_seconds: float, _done: Callable) -> int:
	return ERR_UNAVAILABLE
