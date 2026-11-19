class_name HttpUpdateTransport
extends UpdateTransport

## The update check's request through Godot's `HTTPRequest` (#646). The node
## is added under `host` so it is freed with the scene. One request at a time:
## `UpdateRequest` never asks for a second while one is out.

const NODE_NAME: String = "UpdateHttpRequest"
## A release JSON is a few kilobytes; anything far larger is not one.
const BODY_SIZE_LIMIT: int = 1 << 20

var _http: HTTPRequest = null
var _done: Callable = Callable()


func _init(host: Node) -> void:
	_http = HTTPRequest.new()
	_http.name = NODE_NAME
	_http.body_size_limit = BODY_SIZE_LIMIT
	_http.request_completed.connect(_on_completed)
	host.add_child(_http)


func send(url: String, headers: PackedStringArray, timeout_seconds: float, done: Callable) -> int:
	_http.timeout = timeout_seconds
	_done = done
	var started: int = _http.request(url, headers)
	if started != OK:
		_done = Callable()
	return started


func _on_completed(result: int, http_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var done: Callable = _done
	_done = Callable()
	if done.is_valid():
		done.call(result, http_code, body.get_string_from_utf8())
