extends RefCounted

## A level without `exit_radius` takes its exit from the data file
## `res://data/level_defaults.json`, which the level loader reads and hands to
## core (#311, RUN-3, ARC-1, ARC-4): changing the file changes the exit, with
## no code change.

const SHIPPED_FILE: String = "res://data/level_defaults.json"
const SCRATCH_DIR: String = "user://test_level_defaults"
const REACTOR: String = '{"position": [0, 0, -60], "radius": 2, "hull": 8, "meltdown_seconds": 5}'
## A level file with a reactor and no `exit_radius`.
const LEVEL_NO_EXIT: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": [],' \
	+ ' "reactor": ' + REACTOR + '}'


func _scratch(file_name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR.path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_the_shipped_defaults_file_is_read() -> String:
	var defaults: LevelDefaults = LevelSwitch.load_defaults()
	if defaults == null:
		return "%s was rejected" % SHIPPED_FILE
	var direct: LevelDefaults = LevelDefaults.parse_json(FileAccess.get_file_as_string(SHIPPED_FILE))
	if direct.error != "" or direct.exit_radius_mm != defaults.exit_radius_mm:
		return "parse gave %s, %d mm" % [direct.error, direct.exit_radius_mm]
	if defaults.exit_radius_mm < 1000:
		return "the default exit, %d mm, is narrower than the ship" % defaults.exit_radius_mm
	return ""


func test_changing_the_data_file_changes_the_exit_of_a_level_without_one() -> String:
	var level_path: String = _scratch("no_exit_level.json", LEVEL_NO_EXIT)
	var failures: PackedStringArray = PackedStringArray()
	for metres: float in [2.5, 7.25]:
		var defaults_path: String = _scratch("defaults.json", '{"exit_radius": %s}' % metres)
		var level: LevelDef = LevelSwitch.load_level(level_path, defaults_path)
		var want: int = roundi(metres * 1000.0)
		if level == null:
			failures.append("%s m: level rejected" % metres)
		elif level.exit_radius_mm != want or level.reactor.exit_radius_mm != want:
			failures.append("%s m: level %d mm, reactor %d mm" % [metres, level.exit_radius_mm,
				level.reactor.exit_radius_mm])
	return "\n".join(failures)


func test_a_level_that_names_its_exit_ignores_the_default() -> String:
	var defaults: LevelDefaults = LevelDefaults.parse_json('{"exit_radius": 9}')
	var text: String = LEVEL_NO_EXIT.trim_suffix("}") + ', "exit_radius": 3}'
	var level: LevelDef = LevelDef.parse_json(text, defaults)
	if level.error != "":
		return level.error
	if level.exit_radius_mm != 3000 or level.reactor.exit_radius_mm != 3000:
		return "level %d mm, reactor %d mm" % [level.exit_radius_mm, level.reactor.exit_radius_mm]
	return ""


func test_a_level_without_a_reactor_still_takes_the_default() -> String:
	var defaults: LevelDefaults = LevelDefaults.parse_json('{"exit_radius": 5.5}')
	var text: String = LEVEL_NO_EXIT.replace(', "reactor": ' + REACTOR, "")
	var level: LevelDef = LevelDef.parse_json(text, defaults)
	if level.error != "" or level.reactor != null:
		return "level: '%s', reactor %s" % [level.error, level.reactor]
	if level.exit_radius_mm != 5500:
		return "level %d mm" % level.exit_radius_mm
	return ""


func test_a_missing_or_bad_defaults_file_keeps_the_level_off() -> String:
	var level_path: String = _scratch("no_exit_level.json", LEVEL_NO_EXIT)
	var failures: PackedStringArray = PackedStringArray()
	if LevelSwitch.load_level(level_path, SCRATCH_DIR.path_join("missing.json")) != null:
		failures.append("a missing defaults file still loaded the level")
	var bad: String = _scratch("bad.json", '{"exit_radius": -1}')
	if LevelSwitch.load_level(level_path, bad) != null:
		failures.append("a bad defaults file still loaded the level")
	return "\n".join(failures)


func test_bad_defaults_are_rejected_with_the_problem_named() -> String:
	var cases: Dictionary = {
		"[]": "top level must be a JSON object",
		"{}": "missing key \"exit_radius\"",
		'{"exit_radius": 4, "hull": 1}': "unknown key \"hull\"",
		'{"exit_radius": 0}': "exit_radius must be a number above zero",
		'{"exit_radius": true}': "exit_radius must be a number above zero",
		'{"exit_radius": 101}': "exit_radius must be at most 100.0 m",
	}
	var failures: PackedStringArray = PackedStringArray()
	for text: String in cases:
		var got: String = LevelDefaults.parse_json(text).error
		if got != cases[text]:
			failures.append("%s: got '%s'" % [text, got])
	return "\n".join(failures)
