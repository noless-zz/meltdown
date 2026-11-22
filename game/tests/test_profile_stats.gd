extends RefCounted

## Lifetime statistics in the profile (#1069, CRW-2, RUN-7): the update calls,
## the `stats` key, old files and the trip through `ProfileStore`.

const DIR: String = "user://test_profile_stats"


func _busy_stats() -> ProfileStats:
	var stats: ProfileStats = ProfileStats.new()
	stats.record_run_start()
	stats.record_run_start()
	stats.record_escape(0, 2, {"ore": 3, "glass": 1})
	stats.record_escape(2, 1, {})
	stats.record_loss()
	stats.record_win()
	return stats


func test_a_new_stats_is_all_zero() -> String:
	var values: Dictionary = ProfileStats.new().to_dict()
	if values.size() != ProfileStats.KEYS.size():
		return "counters %s" % values
	for key: String in ProfileStats.KEYS:
		if values[key] != 0:
			return "%s starts at %s" % [key, values[key]]
	return ""


func test_each_record_call_counts() -> String:
	var stats: ProfileStats = ProfileStats.new()
	if not stats.record_run_start() or stats.runs_started != 1:
		return "run start: %s" % stats.to_dict()
	if not stats.record_loss() or stats.runs_lost != 1:
		return "loss: %s" % stats.to_dict()
	if not stats.record_win() or stats.runs_won != 1:
		return "win: %s" % stats.to_dict()
	if not stats.record_escape(1, 3, {"ore": 2, "glass": 5}):
		return "a good escape was refused"
	var expected: Dictionary = {
		"runs_started": 1, "runs_won": 1, "runs_lost": 1, "levels_escaped": 1,
		"deepest_level": 2, "miners_rescued": 3, "components_banked": 7,
	}
	if stats.to_dict() != expected:
		return "after one of each: %s" % stats.to_dict()
	return ""


func test_the_first_level_escaped_makes_the_deepest_level_one() -> String:
	var stats: ProfileStats = ProfileStats.new()
	stats.record_escape(0, 0, {})
	if stats.deepest_level != 1 or stats.levels_escaped != 1:
		return "%s" % stats.to_dict()
	return ""


func test_the_deepest_level_keeps_the_maximum() -> String:
	var stats: ProfileStats = ProfileStats.new()
	stats.record_escape(4, 0, {})
	stats.record_escape(1, 0, {})
	if stats.deepest_level != 5 or stats.levels_escaped != 2:
		return "%s" % stats.to_dict()
	return ""


func test_bad_escape_arguments_change_nothing() -> String:
	var bad_banked: Array[Dictionary] = [
		{"ore": -1},
		{"ore": 1.5},
		{"ore": "2"},
		{"ore": true},
		{"": 1},
		{3: 1},
		{"ore": 1, "glass": -2},
	]
	for banked: Dictionary in bad_banked:
		var stats: ProfileStats = _busy_stats()
		var before: Dictionary = stats.to_dict()
		if stats.record_escape(1, 1, banked):
			return "accepted banked %s" % banked
		if stats.to_dict() != before:
			return "banked %s changed %s" % [banked, stats.to_dict()]
	var stats: ProfileStats = _busy_stats()
	var before: Dictionary = stats.to_dict()
	if stats.record_escape(-1, 0, {}) or stats.record_escape(0, -1, {}):
		return "accepted a negative level or miner count"
	if stats.to_dict() != before:
		return "a refused escape changed %s" % stats.to_dict()
	return ""


func test_stats_survive_the_json_round_trip() -> String:
	var profile: Profile = Profile.new()
	profile.stats = _busy_stats()
	var text: String = profile.to_json()
	var read: Profile = Profile.parse_json(text)
	if read.error != "":
		return "rejected its own text: %s" % read.error
	if not read.stats.equals(profile.stats):
		return "read back %s" % read.stats.to_dict()
	if read.to_json() != text:
		return "the text changed on a round trip"
	return ""


func test_an_unchanged_profile_writes_the_same_sorted_bytes() -> String:
	var profile: Profile = Profile.new()
	profile.stats = _busy_stats()
	var text: String = profile.to_json()
	if profile.to_json() != text:
		return "two writes differ"
	var at: int = text.find("\"stats\"")
	if at < 0 or text.find("\"components_banked\"", at) > text.find("\"deepest_level\"", at):
		return "stats missing or not sorted in %s" % text
	if text.find("\"crew\"") > at or text.find("\"version\"") < at:
		return "top-level keys not sorted in %s" % text
	return ""


func test_the_version_was_raised_for_the_stats_key() -> String:
	if Profile.VERSION < 3:
		return "VERSION is %d" % Profile.VERSION
	return ""


func test_version_1_and_2_files_load_with_zeroed_stats() -> String:
	var texts: Array[String] = [
		"{\"version\": 1, \"banked\": {\"ore\": 2}, \"crafted\": [\"hull_1\"]}",
		"{\"version\": 2, \"banked\": {\"ore\": 2}, \"crafted\": [\"hull_1\"], " +
			"\"crew\": [{\"id\": \"crew-1\", \"role\": \"surveyor\"}]}",
	]
	for text: String in texts:
		var profile: Profile = Profile.parse_json(text)
		if profile.error != "":
			return "an old profile was rejected: %s" % profile.error
		if not profile.stats.equals(ProfileStats.new()):
			return "old file got stats %s" % profile.stats.to_dict()
		if profile.count_of("ore") != 2 or profile.version != Profile.VERSION:
			return "read back %s" % profile.to_json()
	return ""


func test_missing_counters_read_as_zero() -> String:
	var profile: Profile = Profile.parse_json(
		"{\"version\": 3, \"banked\": {}, \"crafted\": [], \"stats\": {\"runs_won\": 4}}")
	if profile.error != "" or profile.stats.runs_won != 4 or profile.stats.runs_started != 0:
		return "error '%s', stats %s" % [profile.error, profile.stats.to_dict()]
	return ""


func test_bad_stats_values_are_rejected() -> String:
	var head: String = "{\"version\": 3, \"banked\": {}, \"crafted\": [], \"stats\": "
	var bad: Array[String] = [
		"[]", "3", "{\"runs_won\": -1}", "{\"runs_won\": 1.5}", "{\"runs_won\": true}",
		"{\"runs_won\": \"2\"}", "{\"robots_destroyed\": 1}",
	]
	for value: String in bad:
		var profile: Profile = Profile.parse_json(head + value + "}")
		if profile.error == "" or not profile.error.contains("stats"):
			return "stats %s gave error '%s'" % [value, profile.error]
		if not profile.stats.equals(ProfileStats.new()):
			return "a rejected file kept stats %s" % profile.stats.to_dict()
	return ""


func test_stats_survive_a_save_and_load_through_the_store() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: ProfileStore = ProfileStore.new(DIR + "/meltdown_profile.json")
	DirAccess.remove_absolute(store.path)
	var profile: Profile = Profile.new()
	profile.bank({"ore": 4})
	profile.crew.append({Profile.CREW_ID: "crew-1", Profile.CREW_ROLE: "surveyor"})
	profile.stats = _busy_stats()
	var saved: bool = store.save(profile)
	var read: Profile = ProfileStore.new(store.path).load_profile()
	DirAccess.remove_absolute(store.path)
	if not saved:
		return "save failed: %s" % store.message
	if not read.stats.equals(profile.stats) or read.to_json() != profile.to_json():
		return "read back %s" % read.to_json()
	return ""
