class_name ProfileStore
extends RefCounted

## Keeps the player's `Profile` on disk (#928, CRF-2, RUN-8). A save writes a
## temporary file next to the profile and then renames it over the old one, so a
## kill at any moment leaves either the old profile or the new one whole, never a
## half-written file (`SafeFileWrite`). The file name uses the codename (NAM-1).

const DEFAULT_PATH: String = "user://meltdown_profile.json"
const TEMP_SUFFIX: String = SafeFileWrite.TEMP_SUFFIX

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
	return SafeFileWrite.temp_path(path)


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
	var failure: String = SafeFileWrite.write(path, profile.to_json(), "profile", stop_before_rename)
	if failure != "":
		message = failure
		return false
	return true
