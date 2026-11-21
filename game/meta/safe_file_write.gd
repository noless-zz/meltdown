class_name SafeFileWrite
extends RefCounted

## Writes a save file so that a kill at any moment leaves either the old file or
## the new one whole, never a half-written one: the text goes to a temporary file
## next to the target, is read back, and only then is renamed over the target.
## Shared by `ProfileStore` (#928) and `RunSaveStore` (#949) so the two saves
## cannot drift apart in how safely they write.

const TEMP_SUFFIX: String = ".tmp"


## The temporary file a save to `path` writes first.
static func temp_path(path: String) -> String:
	return path + TEMP_SUFFIX


## Writes `text` to `path` through the temporary file. Returns "" on success, or
## a message naming what failed, with the old file at `path` unchanged; `what`
## names the save in that message ("profile", "run save"). With
## `stop_before_rename` it writes the temporary file and stops, as a kill at that
## moment would (a test seam), and reports success.
static func write(path: String, text: String, what: String, stop_before_rename: bool = false) -> String:
	var temp: String = temp_path(path)
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [temp, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	var write_error: Error = file.get_error()
	file.close()
	# A full disk can leave a short file: check it before it replaces a good one.
	if write_error != OK or FileAccess.get_file_as_string(temp) != text:
		DirAccess.remove_absolute(temp)
		return "writing %s failed (%s); the old %s is kept" % [temp, error_string(write_error), what]
	if stop_before_rename:
		return ""
	var rename_error: Error = DirAccess.rename_absolute(temp, path)
	if rename_error != OK:
		return "cannot replace %s (%s); the old %s is kept" % [path, error_string(rename_error), what]
	return ""
