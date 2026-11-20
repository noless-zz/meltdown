extends RefCounted

## The update APK is hashed a chunk at a time, and the result equals the
## one-shot check in `UpdateCheck` (#647).

const DIR: String = "user://test_chunked_sha256"


static func _dir() -> String:
	var path: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func _bytes(size: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(size)
	for i: int in size:
		bytes[i] = (i * 31 + 7) % 251
	return bytes


func test_chunked_hash_equals_the_one_shot_check() -> String:
	var path: String = _dir().path_join("chunked.bin")
	for size: int in [0, 1, 7, 4096, ChunkedSha256.DEFAULT_CHUNK_BYTES, 300001]:
		var bytes: PackedByteArray = _bytes(size)
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		for chunk: int in [1, 7, 4096, ChunkedSha256.DEFAULT_CHUNK_BYTES]:
			if size > 5000 and chunk < 4096:
				continue
			var digest: String = ChunkedSha256.of_file(path, chunk)
			if not UpdateCheck.matches_sha256(bytes, digest):
				return "size %d, chunk %d: %s does not match the one-shot hash" % [size, chunk, digest]
	DirAccess.remove_absolute(path)
	return ""


func test_hashing_a_missing_file_fails() -> String:
	var hasher: ChunkedSha256 = ChunkedSha256.new()
	if hasher.open(_dir().path_join("missing.bin")):
		return "opened a missing file"
	return "" if hasher.failure != "" and hasher.feed(1) else "no failure reported"
