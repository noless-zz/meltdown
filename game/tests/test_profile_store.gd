extends RefCounted

## The profile on disk (#928, CRF-2, RUN-8, NAM-1): written through a temporary
## file and a rename, so a kill mid-save leaves the old profile whole.

const DIR: String = "user://test_profile_store"


func _fresh_store() -> ProfileStore:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: ProfileStore = ProfileStore.new(DIR + "/meltdown_profile.json")
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())
	return store


func _cleanup(store: ProfileStore) -> void:
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())


func _write(file_path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _profile(counts: Dictionary) -> Profile:
	var profile: Profile = Profile.new()
	profile.bank(counts)
	return profile


func test_the_default_file_uses_the_codename() -> String:
	if ProfileStore.new().path != "user://meltdown_profile.json":
		return "default path %s" % ProfileStore.new().path
	return ""


func test_a_missing_file_gives_an_empty_profile_and_a_message() -> String:
	var store: ProfileStore = _fresh_store()
	var profile: Profile = store.load_profile()
	_cleanup(store)
	if not profile.banked.is_empty() or store.message == "" or store.locked:
		return "banked %s, message '%s', locked %s" % [profile.banked, store.message, store.locked]
	return ""


func test_a_saved_profile_loads_back() -> String:
	var store: ProfileStore = _fresh_store()
	if not store.save(_profile({"ore": 3})):
		_cleanup(store)
		return "save failed: %s" % store.message
	var read: Profile = ProfileStore.new(store.path).load_profile()
	var temp_left: bool = FileAccess.file_exists(store.temp_path())
	_cleanup(store)
	if read.count_of("ore") != 3:
		return "read back %s" % read.banked
	return "the temporary file was left behind" if temp_left else ""


func test_an_unreadable_file_gives_an_empty_profile_and_a_message() -> String:
	var store: ProfileStore = _fresh_store()
	for text: String in ["{\"version\": 1, \"banked\": {\"ore\": ", "", "[]"]:
		_write(store.path, text)
		var profile: Profile = store.load_profile()
		if not profile.banked.is_empty() or store.message == "" or store.locked:
			_cleanup(store)
			return "%s: banked %s, message '%s', locked %s" % [text, profile.banked, store.message, store.locked]
	_cleanup(store)
	return ""


func test_a_kill_before_the_rename_leaves_the_old_profile() -> String:
	var store: ProfileStore = _fresh_store()
	store.save(_profile({"ore": 3}))
	var killed: ProfileStore = ProfileStore.new(store.path)
	killed.stop_before_rename = true
	killed.save(_profile({"ore": 99}))
	if not FileAccess.file_exists(store.temp_path()):
		_cleanup(store)
		return "the simulated kill wrote no temporary file"
	var after_kill: Profile = ProfileStore.new(store.path).load_profile()
	if after_kill.count_of("ore") != 3:
		_cleanup(store)
		return "after the kill the profile reads %s" % after_kill.banked
	# The next run saves normally over the leftover temporary file.
	var next: ProfileStore = ProfileStore.new(store.path)
	var saved: bool = next.save(_profile({"ore": 5}))
	var final: Profile = next.load_profile()
	_cleanup(store)
	if not saved or final.count_of("ore") != 5:
		return "the next save gave %s (%s)" % [final.banked, next.message]
	return ""


func test_a_newer_version_is_refused_and_left_untouched() -> String:
	var store: ProfileStore = _fresh_store()
	var text: String = "{\"version\": %d, \"banked\": {\"ore\": 7}, \"crafted\": []}" % (Profile.VERSION + 1)
	_write(store.path, text)
	var profile: Profile = store.load_profile()
	if not store.locked or store.message == "" or not profile.banked.is_empty():
		_cleanup(store)
		return "locked %s, message '%s', banked %s" % [store.locked, store.message, profile.banked]
	var saved: bool = store.save(_profile({"ore": 1}))
	var on_disk: String = FileAccess.get_file_as_string(store.path)
	var temp_left: bool = FileAccess.file_exists(store.temp_path())
	_cleanup(store)
	if saved or store.message == "":
		return "a save over a newer profile was allowed"
	if on_disk != text or temp_left:
		return "the newer file was touched: %s" % on_disk
	return ""


func test_a_good_load_unlocks_the_store() -> String:
	var store: ProfileStore = _fresh_store()
	_write(store.path, "{\"version\": %d, \"banked\": {}, \"crafted\": []}" % (Profile.VERSION + 1))
	store.load_profile()
	_write(store.path, _profile({"ore": 2}).to_json())
	var profile: Profile = store.load_profile()
	var saved: bool = store.save(profile)
	_cleanup(store)
	if store.locked or not saved or store.message != "":
		return "locked %s, saved %s, message '%s'" % [store.locked, saved, store.message]
	return ""


func test_a_profile_newer_than_the_build_is_not_written() -> String:
	var store: ProfileStore = _fresh_store()
	var profile: Profile = Profile.new()
	profile.version = Profile.VERSION + 1
	var saved: bool = store.save(profile)
	var written: bool = FileAccess.file_exists(store.path) or FileAccess.file_exists(store.temp_path())
	_cleanup(store)
	if saved or written:
		return "saved %s, file written %s" % [saved, written]
	return ""


func test_an_unwritable_place_fails_without_a_crash() -> String:
	var store: ProfileStore = ProfileStore.new(DIR + "/no_such_dir/meltdown_profile.json")
	if store.save(_profile({"ore": 1})) or store.message == "":
		return "a save into a missing folder reported success"
	return ""


func test_the_profile_layer_depends_only_on_core() -> String:
	for file_path: String in ["res://meta/profile.gd", "res://meta/profile_store.gd"]:
		var text: String = FileAccess.get_file_as_string(file_path)
		for word: String in ["Node", "res://view", "res://xr", "res://net", "res://gen", "Input.", "randi", "randf", "Time."]:
			if text.contains(word):
				return "%s mentions %s" % [file_path, word]
	return ""
