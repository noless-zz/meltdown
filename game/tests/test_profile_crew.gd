extends RefCounted

## The profile's crew list (#1010, CRW-1): read, written and checked for shape.
## Role ids are checked against `CrewRoles` in test_crew_roster.gd.


func _member(id: String, role: String) -> Dictionary:
	return {Profile.CREW_ID: id, Profile.CREW_ROLE: role}


func test_an_old_version_1_file_without_crew_loads_with_an_empty_crew() -> String:
	var profile: Profile = Profile.parse_json(
		"{\"version\": 1, \"banked\": {\"ore\": 2}, \"crafted\": [\"hull_1\"]}")
	if profile.error != "":
		return "an old profile was rejected: %s" % profile.error
	if not profile.crew.is_empty() or profile.count_of("ore") != 2 or profile.crafted != ["hull_1"]:
		return "read back %s" % profile.to_json()
	if profile.version != Profile.VERSION:
		return "an old file was not moved to the current layout: version %d" % profile.version
	return ""


func test_a_current_file_without_crew_also_loads() -> String:
	var profile: Profile = Profile.parse_json(
		"{\"version\": %d, \"banked\": {}, \"crafted\": []}" % Profile.VERSION)
	if profile.error != "" or not profile.crew.is_empty():
		return "error '%s', crew %s" % [profile.error, profile.crew]
	return ""


func test_the_version_was_raised_for_the_crew_key() -> String:
	# A version 1 build refuses unknown keys; only a higher number makes it leave
	# a file with crew alone instead of calling it unreadable and saving over it.
	if Profile.VERSION < 2:
		return "VERSION is %d" % Profile.VERSION
	return ""


func test_crew_survives_the_json_round_trip_in_order() -> String:
	var profile: Profile = Profile.new()
	profile.crew.append(_member("crew-2", "surveyor"))
	profile.crew.append(_member("crew-1", "shield_tech"))
	var text: String = profile.to_json()
	var read: Profile = Profile.parse_json(text)
	if read.error != "":
		return "rejected its own text: %s" % read.error
	if read.crew != profile.crew:
		return "read back %s" % [read.crew]
	if read.to_json() != text:
		return "the text changed on a round trip"
	return ""


func test_a_new_profile_writes_an_empty_crew() -> String:
	if not Profile.new().to_json().contains("\"crew\": []"):
		return "no crew key in %s" % Profile.new().to_json()
	return ""


func test_bad_crew_entries_are_errors_naming_the_entry() -> String:
	var head: String = "{\"version\": %d, \"banked\": {}, \"crafted\": [], \"crew\": " % Profile.VERSION
	# Each bad crew value, with a piece of text the error must contain.
	var cases: Array[Array] = [
		["{}", "crew"],
		["[1]", "crew entry 1"],
		["[{\"id\": \"crew-1\"}]", "crew entry 1 (\"crew-1\")"],
		["[{\"id\": \"crew-1\", \"role\": \"\"}]", "crew entry 1 (\"crew-1\")"],
		["[{\"id\": \"crew-1\", \"role\": 3}]", "role"],
		["[{\"role\": \"surveyor\"}]", "crew entry 1"],
		["[{\"id\": \"\", \"role\": \"surveyor\"}]", "crew entry 1"],
		["[{\"id\": \"crew-1\", \"role\": \"surveyor\", \"mood\": \"glad\"}]", "mood"],
		["[{\"id\": \"crew-1\", \"role\": \"surveyor\"}, {\"id\": \"crew-1\", \"role\": \"shield_tech\"}]",
			"crew entry 2 (\"crew-1\")"],
	]
	for case: Array in cases:
		var text: String = head + String(case[0]) + "}"
		var profile: Profile = Profile.parse_json(text)
		if profile.error == "":
			return "accepted crew %s" % case[0]
		if not profile.error.contains(String(case[1])):
			return "error for %s does not name the entry: %s" % [case[0], profile.error]
		if not profile.crew.is_empty() or not profile.banked.is_empty():
			return "crew %s left data in the rejected profile" % case[0]
	return ""
