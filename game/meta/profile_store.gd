class_name ProfileStore
extends RefCounted

## Keeps the player's `Profile` on disk (#928, CRF-2, RUN-8). A save writes a
## temporary file next to the profile and then renames it over the old one, so a
## kill at any moment leaves either the old profile or the new one whole, never a
## half-written file. The file name uses the codename (NAM-1).

const DEFAULT_PATH: String = "user://meltdown_profile.json"
const TEMP_SUFFIX: String = ".tmp"

var path: String = DEFAULT_PATH
## What the last `load_profile` or `save` had to say; empty when all went well.
var message: String = ""
## Set when the file on disk came from a newer build. Saves are then refused, so
## the newer profile is left exactly as it is.
var locked: bool = false
## Test seam: the save writes the temporary file and stops before the rename,
## as a kill at that moment would.
var stop_before_rename: bool = false


func _init(profile_path: String = DEFAULT_PATH) -> void:
	path = profile_path


func temp_path() -> String:
	return path + TEMP_SUFFIX


## Reads the profile. A missing or unreadable file gives an empty profile and a
## message; a file from a newer build also locks the store against saving. A
## temporary file left by a killed save is ignored: the profile it was replacing
## is still whole.
func load_profile() -> Profile:
	message = ""
	locked = false
	if not FileAccess.file_exists(path):
		message = "no profile at %s yet; starting with an empty one" % path
		return Profile.new()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		message = "cannot open %s (%s); starting with an empty profile" % [
			path, error_string(FileAccess.get_open_error())]
		return Profile.new()
	var text: String = file.get_as_text()
	file.close()
	var read: Profile = Profile.parse_json(text)
	if read.too_new:
		locked = true
		message = "%s: %s; it is left untouched and this build will not save over it" % [path, read.error]
		return Profile.new()
	if read.error != "":
		message = "%s is unreadable (%s); starting with an empty profile" % [path, read.error]
		return Profile.new()
	return read


## Writes `profile` safely (see the class comment). Returns false, with
## `message` set and the old file unchanged, when it could not.
func save(profile: Profile) -> bool:
	message = ""
	if locked:
		message = "%s came from a newer build; not saving over it" % path
		return false
	if profile.version > Profile.VERSION:
		message = "profile version %d is newer than this build writes" % profile.version
		return false
	var file: FileAccess = FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		message = "cannot write %s (%s)" % [temp_path(), error_string(FileAccess.get_open_error())]
		return false
	var text: String = profile.to_json()
	file.store_string(text)
	var write_error: Error = file.get_error()
	file.close()
	# A full disk can leave a short file: check it before it replaces a good one.
	if write_error != OK or FileAccess.get_file_as_string(temp_path()) != text:
		DirAccess.remove_absolute(temp_path())
		message = "writing %s failed (%s); the old profile is kept" % [temp_path(), error_string(write_error)]
		return false
	if stop_before_rename:
		return true
	var rename_error: Error = DirAccess.rename_absolute(temp_path(), path)
	if rename_error != OK:
		message = "cannot replace %s (%s); the old profile is kept" % [path, error_string(rename_error)]
		return false
	return true
