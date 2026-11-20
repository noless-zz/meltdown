class_name UpdateDownloader
extends RefCounted

## The file downloads the in-app update makes (#647), behind an interface so
## the tests can fake them and no test ever reaches GitHub.
## `HttpUpdateDownloader` is the real one. One download at a time.


## Starts a GET of `url` written straight to the file `path`, giving up after
## `timeout_seconds` (0 means never), and returns `OK` when it started. When it
## ends it calls `done.call(result: int, http_code: int)` once, where `result`
## is an `HTTPRequest.Result` value, unless `cancel()` came first: a cancelled
## download never calls `done`. The file may be left partly written either
## way; the caller removes it. This base class fetches nothing.
func fetch(_url: String, _path: String, _timeout_seconds: float, _done: Callable) -> int:
	return ERR_UNAVAILABLE


## Bytes of the body received so far by the running download.
func downloaded_bytes() -> int:
	return 0


## The body size the server announced, or -1 when it gave none.
func total_bytes() -> int:
	return -1


## Stops the running download, if any. `done` is not called for it.
func cancel() -> void:
	pass
