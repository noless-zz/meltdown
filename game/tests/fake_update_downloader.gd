class_name FakeUpdateDownloader
extends UpdateDownloader

## Stands in for the network in the download tests: each URL is served from
## `bodies` (missing ones answer 404) and written to the asked-for file. With
## `deferred` set, half the body is written at once and the answer waits for
## `answer()`, so a test can watch progress, cancel or fail midway. No test
## reaches GitHub.

## url -> PackedByteArray.
var bodies: Dictionary = {}
## url -> HTTPRequest.Result, for a network failure on that URL.
var results: Dictionary = {}
var deferred: bool = false
var announce_size: bool = true
var urls: Array[String] = []
var paths: Array[String] = []
var cancels: int = 0

var _pending: Callable = Callable()
var _url: String = ""
var _path: String = ""
var _written: int = 0


func fetch(url: String, path: String, _timeout_seconds: float, done: Callable) -> int:
	urls.append(url)
	paths.append(path)
	_url = url
	_path = path
	_pending = done
	var body: PackedByteArray = bodies.get(url, PackedByteArray())
	if deferred:
		_write(body.slice(0, body.size() / 2))
	else:
		answer()
	return OK


## Finishes the held download: writes the rest and calls `done`.
func answer() -> void:
	var done: Callable = _pending
	_pending = Callable()
	if not done.is_valid():
		return
	var result: int = results.get(_url, HTTPRequest.RESULT_SUCCESS)
	var code: int = 200 if bodies.has(_url) else 404
	if result == HTTPRequest.RESULT_SUCCESS:
		_write(bodies.get(_url, PackedByteArray()))
	done.call(result, code)


func downloaded_bytes() -> int:
	return _written


func total_bytes() -> int:
	if not announce_size or not bodies.has(_url):
		return -1
	var body: PackedByteArray = bodies[_url]
	return body.size()


func cancel() -> void:
	cancels += 1
	_pending = Callable()


func _write(bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()
	_written = bytes.size()
