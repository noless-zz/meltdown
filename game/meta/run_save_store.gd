class_name RunSaveStore
extends RefCounted

## Keeps one suspended run on disk (#949, RUN-8) in its own file, apart from the
## profile, so losing or abandoning a run (RUN-7) never touches what the profile
## banked. Writes go through `SafeFileWrite`: a kill mid-save leaves the previous
## run save whole. The file name uses the codename (NAM-1).
##
## A suspended run is resumed once only: `take` reads the save and deletes it,
## and hands nothing out if it cannot delete it.

const DEFAULT_PATH: String = "user://meltdown_run.json"

var path: String = DEFAULT_PATH
## What the last call had to say; empty when all went well.
var message: String = ""
## Test seam: the save writes the temporary file and stops before the rename,
## as a kill at that moment would.
var stop_before_rename: bool = false


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


func temp_path() -> String:
	return SafeFileWrite.temp_path(path)


## Whether a suspended run waits on disk. A temporary file left by a killed save
## does not count: only a renamed, whole file does.
func has_save() -> bool:
	return FileAccess.file_exists(path)


## Writes `run` safely. Refuses, with `message` set and the file on disk
## unchanged, a save that would not read back, or one over a run save written by
## a newer build.
func save(run: RunSave) -> bool:
	message = ""
	var problem: String = run.check()
	if problem != "":
		message = "not saving the run: %s" % problem
		return false
	if FileAccess.file_exists(path):
		var on_disk: RunSave = RunSave.parse_json(FileAccess.get_file_as_string(path))
		if on_disk.too_new:
			message = "%s came from a newer build; not saving over it" % path
			return false
	message = SafeFileWrite.write(path, run.to_json(), "run save", stop_before_rename)
	return message == ""


## Reads the suspended run and deletes its file, so it resumes once only.
## Returns null with `message` set when there is none: no file, an unreadable
## one (left on disk for `discard`), one from a newer build (left untouched), or
## one that could not be deleted.
func take() -> RunSave:
	message = ""
	if not FileAccess.file_exists(path):
		message = "no suspended run at %s" % path
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		message = "cannot open %s (%s); no run to resume" % [path, error_string(FileAccess.get_open_error())]
		return null
	var text: String = file.get_as_text()
	file.close()
	var run: RunSave = RunSave.parse_json(text)
	if run.too_new:
		message = "%s: %s; it is left untouched" % [path, run.error]
		return null
	if run.error != "":
		message = "%s is unreadable (%s); no run to resume" % [path, run.error]
		return null
	var remove_error: Error = DirAccess.remove_absolute(path)
	if remove_error != OK:
		message = "cannot delete %s (%s); not resuming, so the run cannot resume twice" % [
			path, error_string(remove_error)]
		return null
	return run


## Removes the suspended run, and any temporary file a killed save left, for a
## run that was lost or abandoned. True when neither file remains.
func discard() -> bool:
	message = ""
	for file_path: String in [path, temp_path()]:
		if FileAccess.file_exists(file_path):
			var remove_error: Error = DirAccess.remove_absolute(file_path)
			if remove_error != OK:
				message = "cannot delete %s (%s)" % [file_path, error_string(remove_error)]
	return message == ""
