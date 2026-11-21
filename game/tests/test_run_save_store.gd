extends RefCounted

## The suspended run on disk (#949, RUN-8, RUN-7, NAM-1): a kill mid-save keeps
## the previous save, `take` resumes once only, and the run save never touches
## the profile.

const DIR: String = "user://test_run_save_store"


func _fresh_store() -> RunSaveStore:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: RunSaveStore = RunSaveStore.new(DIR + "/meltdown_run.json")
	_cleanup(store)
	return store


func _cleanup(store: RunSaveStore) -> void:
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())


func _write(file_path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run(next_level: int) -> RunSave:
	var run: RunSave = RunSave.new()
	run.run_seed = 42
	run.next_level = next_level
	run.ship = "default_ship"
	run.loadout = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}
	return run


func test_the_default_file_uses_the_codename() -> String:
	var store: RunSaveStore = RunSaveStore.new()
	if store.path != "user://meltdown_run.json":
		return "default path %s" % store.path
	if store.path == ProfileStore.DEFAULT_PATH:
		return "the run save and the profile share a file"
	return ""


func test_a_saved_run_is_taken_once() -> String:
	var store: RunSaveStore = _fresh_store()
	if store.has_save():
		return "a fresh store says a save waits"
	if not store.save(_run(2)):
		_cleanup(store)
		return "save failed: %s" % store.message
	var temp_left: bool = FileAccess.file_exists(store.temp_path())
	if not store.has_save():
		_cleanup(store)
		return "has_save is false after a save"
	var taken: RunSave = RunSaveStore.new(store.path).take()
	var second: RunSave = store.take()
	var still_there: bool = store.has_save()
	_cleanup(store)
	if taken == null or taken.next_level != 2 or taken.run_seed != 42:
		return "took %s" % (taken.to_json() if taken != null else "nothing")
	if second != null or still_there or store.message == "":
		return "a second take gave %s, has_save %s, message '%s'" % [second, still_there, store.message]
	return "the temporary file was left behind" if temp_left else ""


func test_a_kill_before_the_rename_leaves_the_previous_save() -> String:
	var store: RunSaveStore = _fresh_store()
	store.save(_run(2))
	var killed: RunSaveStore = RunSaveStore.new(store.path)
	killed.stop_before_rename = true
	killed.save(_run(5))
	if not FileAccess.file_exists(store.temp_path()):
		_cleanup(store)
		return "the simulated kill wrote no temporary file"
	var after_kill: RunSave = RunSaveStore.new(store.path).take()
	if after_kill == null or after_kill.to_json() != _run(2).to_json():
		_cleanup(store)
		return "after the kill the save reads %s" % (after_kill.to_json() if after_kill != null else "nothing")
	# The next suspend saves normally over the leftover temporary file.
	var next: RunSaveStore = RunSaveStore.new(store.path)
	var saved: bool = next.save(_run(4))
	var final: RunSave = next.take()
	_cleanup(store)
	if not saved or final == null or final.next_level != 4:
		return "the next save gave %s (%s)" % [final, next.message]
	return ""


func test_a_kill_before_the_first_rename_leaves_no_save() -> String:
	var store: RunSaveStore = _fresh_store()
	store.stop_before_rename = true
	store.save(_run(2))
	var waits: bool = store.has_save()
	var taken: RunSave = store.take()
	_cleanup(store)
	if waits or taken != null:
		return "a half-done first save counts as a save"
	return ""


func test_a_missing_file_gives_no_save_and_a_message() -> String:
	var store: RunSaveStore = _fresh_store()
	var taken: RunSave = store.take()
	if taken != null or store.message == "":
		return "took %s, message '%s'" % [taken, store.message]
	return ""


func test_an_unreadable_file_gives_no_save_and_a_message() -> String:
	var store: RunSaveStore = _fresh_store()
	for text: String in ["{\"version\": 1, \"run_seed\": ", "", "[]", "{\"version\": 1}"]:
		_write(store.path, text)
		var taken: RunSave = store.take()
		if taken != null or store.message == "":
			_cleanup(store)
			return "'%s': took %s, message '%s'" % [text, taken, store.message]
	var left: bool = store.has_save()
	var discarded: bool = store.discard()
	_cleanup(store)
	if not left:
		return "an unreadable save was deleted by take"
	return "" if discarded and not store.has_save() else "discard failed: %s" % store.message


func test_a_newer_version_is_refused_and_left_on_disk() -> String:
	var store: RunSaveStore = _fresh_store()
	var text: String = "{\"version\": %d, \"run_seed\": \"1\", \"crew\": []}" % (RunSave.VERSION + 1)
	_write(store.path, text)
	var taken: RunSave = store.take()
	if taken != null or store.message == "":
		_cleanup(store)
		return "took %s, message '%s'" % [taken, store.message]
	var saved: bool = store.save(_run(2))
	var on_disk: String = FileAccess.get_file_as_string(store.path)
	var temp_left: bool = FileAccess.file_exists(store.temp_path())
	_cleanup(store)
	if saved or store.message == "":
		return "a save over a newer run save was allowed"
	if on_disk != text or temp_left:
		return "the newer file was touched: %s" % on_disk
	return ""


func test_a_save_that_would_not_read_back_is_refused() -> String:
	var store: RunSaveStore = _fresh_store()
	var bad: RunSave = _run(0)
	var saved: bool = store.save(bad)
	var written: bool = FileAccess.file_exists(store.path) or FileAccess.file_exists(store.temp_path())
	_cleanup(store)
	if saved or written or not store.message.contains("next_level"):
		return "saved %s, written %s, message '%s'" % [saved, written, store.message]
	return ""


func test_discard_removes_the_run_and_never_the_profile() -> String:
	var store: RunSaveStore = _fresh_store()
	var profiles: ProfileStore = ProfileStore.new(DIR + "/meltdown_profile.json")
	var profile: Profile = Profile.new()
	profile.bank({"ore": 4})
	if not profiles.save(profile):
		return "profile save failed: %s" % profiles.message
	var profile_text: String = FileAccess.get_file_as_string(profiles.path)
	store.save(_run(3))
	_write(store.temp_path(), "left by a kill")
	var discarded: bool = store.discard()
	var run_left: bool = FileAccess.file_exists(store.path) or FileAccess.file_exists(store.temp_path())
	var profile_after: String = FileAccess.get_file_as_string(profiles.path)
	var again: bool = store.discard()
	DirAccess.remove_absolute(profiles.path)
	_cleanup(store)
	if not discarded or run_left:
		return "discard %s, run file left %s (%s)" % [discarded, run_left, store.message]
	if profile_after != profile_text:
		return "discarding the run changed the profile: %s" % profile_after
	return "" if again else "discarding nothing failed: %s" % store.message


func test_taking_a_run_never_touches_the_profile() -> String:
	var store: RunSaveStore = _fresh_store()
	var profiles: ProfileStore = ProfileStore.new(DIR + "/meltdown_profile.json")
	var profile: Profile = Profile.new()
	profile.bank({"ore": 6})
	profiles.save(profile)
	store.save(_run(2))
	store.take()
	var read: Profile = ProfileStore.new(profiles.path).load_profile()
	DirAccess.remove_absolute(profiles.path)
	_cleanup(store)
	return "" if read.count_of("ore") == 6 else "profile after take: %s" % read.banked


func test_an_unwritable_place_fails_without_a_crash() -> String:
	var store: RunSaveStore = RunSaveStore.new(DIR + "/no_such_dir/meltdown_run.json")
	if store.save(_run(2)) or store.message == "":
		return "a save into a missing folder reported success"
	return ""


func test_the_run_save_layer_depends_only_on_core() -> String:
	for file_path: String in ["res://meta/run_save.gd", "res://meta/run_save_store.gd", "res://meta/safe_file_write.gd"]:
		var text: String = FileAccess.get_file_as_string(file_path)
		for word: String in ["Node", "res://view", "res://xr", "res://net", "res://gen", "Input.", "randi", "randf", "Time.", "RunState"]:
			if text.contains(word):
				return "%s mentions %s" % [file_path, word]
	return ""
