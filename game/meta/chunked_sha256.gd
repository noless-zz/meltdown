class_name ChunkedSha256
extends RefCounted

## SHA-256 of a file read a chunk at a time (#647), so checking an 89 MB APK
## never holds a second copy of it in memory, and spread over frames by
## `feed()` so the headset does not drop frames while it hashes.

const DEFAULT_CHUNK_BYTES: int = 1 << 18

## Lowercase hex once `finished`, "" before or on failure.
var digest: String = ""
## Why it failed, "" when it did not.
var failure: String = ""
var finished: bool = false

var _file: FileAccess = null
var _context: HashingContext = null
var _chunk_bytes: int = DEFAULT_CHUNK_BYTES


## Opens `path` for hashing. False (with `failure` set) when it cannot.
func open(path: String, chunk_bytes: int = DEFAULT_CHUNK_BYTES) -> bool:
	close()
	digest = ""
	failure = ""
	finished = false
	_chunk_bytes = maxi(1, chunk_bytes)
	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		return _fail("cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	_context = HashingContext.new()
	if _context.start(HashingContext.HASH_SHA256) != OK:
		return _fail("cannot start SHA-256")
	return true


## Hashes up to `max_chunks` more chunks. Returns true once it has finished,
## successfully or not.
func feed(max_chunks: int) -> bool:
	if finished or _file == null:
		return true
	for i: int in maxi(1, max_chunks):
		var chunk: PackedByteArray = _file.get_buffer(_chunk_bytes)
		if not chunk.is_empty() and _context.update(chunk) != OK:
			_fail("SHA-256 update failed")
			return true
		if chunk.size() < _chunk_bytes:
			digest = _context.finish().hex_encode()
			finished = true
			close()
			return true
	return false


func close() -> void:
	if _file != null:
		_file.close()
	_file = null


## The whole file at once, a chunk at a time. "" when it cannot be read.
static func of_file(path: String, chunk_bytes: int = DEFAULT_CHUNK_BYTES) -> String:
	var hasher: ChunkedSha256 = ChunkedSha256.new()
	if not hasher.open(path, chunk_bytes):
		return ""
	while not hasher.feed(64):
		pass
	return hasher.digest


func _fail(reason: String) -> bool:
	failure = reason
	finished = true
	close()
	return false
