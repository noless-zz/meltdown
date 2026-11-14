extends RefCounted

## Every script needs its `.uid` file in version control (ARC-5). Godot writes
## a missing one on import with a new random identifier, so two clones would
## disagree about the same script. `tools/check_clean_import.sh` catches that
## in CI; this test names the script when the tests are run locally.

const ROOT: String = "res://"


## Returns the scripts in `files` that have no `<script>.uid` among `files`.
static func scripts_without_uid(files: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for file: String in files:
		if file.ends_with(".gd") and not files.has(file + ".uid"):
			missing.append(file)
	return missing


## Every file under `dir_path`. Hidden folders are skipped, which leaves out
## Godot's own cache in `.godot/`.
static func _files_under(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return files
	for file: String in dir.get_files():
		files.append(dir_path.path_join(file))
	for sub_dir: String in dir.get_directories():
		files.append_array(_files_under(dir_path.path_join(sub_dir)))
	return files


func test_every_script_has_a_uid_file() -> String:
	var files: Array[String] = _files_under(ROOT)
	if not files.has("res://core/sim.gd"):
		# A failed directory read would find no scripts and pass.
		return "res://core/sim.gd was not found; the project was not read"
	var missing: Array[String] = scripts_without_uid(files)
	if not missing.is_empty():
		return "no .uid file beside: %s" % ", ".join(missing)
	return ""


func test_missing_uid_file_is_reported() -> String:
	var files: Array[String] = [
		"res://core/a.gd", "res://core/a.gd.uid",
		"res://core/b.gd",
		"res://gen/a.gd.uid", "res://gen/deep/c.gd", "res://notes.txt",
	]
	var missing: Array[String] = scripts_without_uid(files)
	if missing != ["res://core/b.gd", "res://gen/deep/c.gd"]:
		return "expected b.gd and c.gd, got %s" % str(missing)
	return ""
