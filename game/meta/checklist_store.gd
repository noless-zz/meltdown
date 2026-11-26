class_name ChecklistStore
extends RefCounted

## Where a checklist's results live on the headset (#1325, DEV-6): one JSON
## file per checklist at a fixed `user://` path, written whole after every
## mark (`SafeFileWrite`), so a PC script can `adb pull` it and post it to the
## gate issue. The game holds no token and sends nothing itself.
##
## On a Quest the file is under the app's data folder,
## `/sdcard/Android/data/<package>/files/` (Godot's `user://` on Android).

const PREFIX: String = "user://meltdown_checklist_"
const EXTENSION: String = ".json"

## Where results are written; tests point it at a scratch prefix.
var prefix: String = PREFIX


## The results file of the checklist with `id`.
func path_for(id: String) -> String:
	return "%s%s%s" % [prefix, id, EXTENSION]


## Writes `session`'s results with the build `commit`. Returns "" or what failed.
func save(session: ChecklistSession, commit: String) -> String:
	var text: String = JSON.stringify(session.results(commit), "\t")
	return SafeFileWrite.write(path_for(session.checklist.id), text, "checklist results")


## Takes back the marks saved for `session`'s checklist, if any. Returns how many.
func load_into(session: ChecklistSession) -> int:
	var path: String = path_for(session.checklist.id)
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Checklist results in %s are not a JSON object; starting afresh" % path)
		return 0
	return session.restore(data)
