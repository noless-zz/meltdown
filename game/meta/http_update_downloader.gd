class_name HttpUpdateDownloader
extends UpdateDownloader

## The in-app update's downloads through Godot's `HTTPRequest` (#647). The node
## is added under `host` so it is freed with the scene. `HTTPRequest` writes
## the body to the file as it arrives, so an 89 MB APK is never held in memory,
## and its own thread does the reading so the headset's frames do not wait on
## the network. GitHub's asset URLs redirect to its download host, which
## `HTTPRequest` follows.

const NODE_NAME: String = "UpdateHttpDownload"

var _http: HTTPRequest = null
var _done: Callable = Callable()


func _init(host: Node) -> void:
	_http = HTTPRequest.new()
	_http.name = NODE_NAME
	_http.use_threads = true
	_http.body_size_limit = -1
	_http.request_completed.connect(_on_completed)
	host.add_child(_http)


func fetch(url: String, path: String, timeout_seconds: float, done: Callable) -> int:
	_http.download_file = path
	_http.timeout = timeout_seconds
	_done = done
	var started: int = _http.request(url, PackedStringArray(["User-Agent: meltdown-update-download"]))
	if started != OK:
		_done = Callable()
	return started


func downloaded_bytes() -> int:
	return _http.get_downloaded_bytes()


func total_bytes() -> int:
	return _http.get_body_size()


func cancel() -> void:
	_done = Callable()
	_http.cancel_request()


func _on_completed(result: int, http_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var done: Callable = _done
	_done = Callable()
	if done.is_valid():
		done.call(result, http_code)
