extends SceneTree

## Writes the `docs/checklists/` copy of every shipped checklist file (#1325,
## `ChecklistMarkdown`). Run through `tools/checklist_docs.sh` after editing a
## file under `game/data/checklists/`; `test_checklist_docs.gd` fails until it is.
## A rejected checklist stops it with the file and field named.


func _init() -> void:
	var failed: bool = false
	for path: String in Checklist.files():
		var checklist: Checklist = Checklist.load_file(path)
		if not checklist.is_valid():
			printerr("%s: %s" % [path, checklist.error])
			failed = true
			continue
		var target: String = ChecklistMarkdown.docs_path(checklist)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			printerr("cannot write %s" % target)
			failed = true
			continue
		file.store_string(ChecklistMarkdown.render(checklist, path))
		file.close()
		print("wrote %s" % target)
	quit(1 if failed else 0)
