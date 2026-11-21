extends RefCounted

## The player profile's data and JSON text (#928, CRF-2, CRF-3, RUN-7).


func test_a_new_profile_is_empty_at_the_current_version() -> String:
	var profile: Profile = Profile.new()
	if profile.version != Profile.VERSION or not profile.banked.is_empty() or not profile.crafted.is_empty():
		return "new profile: %s" % profile.to_json()
	return ""


func test_bank_adds_to_the_counts() -> String:
	var profile: Profile = Profile.new()
	if not profile.bank({"ore": 3, "cell": 1}) or not profile.bank({"ore": 2, "chip": 0}):
		return "a valid bank was refused"
	if profile.count_of("ore") != 5 or profile.count_of("cell") != 1:
		return "banked %s" % profile.banked
	if profile.banked.has("chip"):
		return "a zero count left an entry: %s" % profile.banked
	return ""


func test_bank_refuses_bad_counts_and_changes_nothing() -> String:
	var bad: Array[Dictionary] = [
		{"ore": 2, "cell": -1}, {"ore": 2, "cell": 1.5}, {"ore": 2, "cell": true},
		{"ore": 2, "cell": "3"}, {"ore": 2, "": 1}, {"ore": 2, 7: 1},
	]
	for counts: Dictionary in bad:
		var profile: Profile = Profile.new()
		profile.bank({"ore": 1})
		if profile.bank(counts):
			return "bank accepted %s" % counts
		if profile.banked != {"ore": 1}:
			return "a refused bank of %s changed the counts to %s" % [counts, profile.banked]
	return ""


func test_spend_takes_from_the_counts() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"ore": 5, "cell": 2})
	if not profile.spend({"ore": 3, "cell": 2}):
		return "an affordable spend was refused"
	if profile.count_of("ore") != 2 or profile.banked.has("cell"):
		return "left %s" % profile.banked
	return ""


func test_spend_refuses_when_a_count_would_go_negative() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"ore": 5, "cell": 2})
	for counts: Dictionary in [{"ore": 1, "cell": 3}, {"chip": 1}, {"ore": -1}, {"ore": 0.5}]:
		if profile.spend(counts):
			return "spend accepted %s" % [counts]
		if profile.banked != {"ore": 5, "cell": 2}:
			return "a refused spend of %s changed the counts to %s" % [counts, profile.banked]
	return ""


func test_the_json_round_trips() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"ore": 4, "cell": 1})
	profile.crafted.append("hull_1")
	var read: Profile = Profile.parse_json(profile.to_json())
	if read.error != "":
		return "rejected its own text: %s" % read.error
	if read.banked != profile.banked or read.crafted != profile.crafted or read.version != Profile.VERSION:
		return "read back %s" % read.to_json()
	if read.to_json() != profile.to_json():
		return "the text changed on a round trip"
	return ""


func test_the_json_text_is_stable() -> String:
	var first: Profile = Profile.new()
	first.bank({"b": 1, "a": 2})
	var second: Profile = Profile.new()
	second.bank({"a": 2})
	second.bank({"b": 1})
	if first.to_json() != second.to_json():
		return "same counts, different text:\n%s\n%s" % [first.to_json(), second.to_json()]
	return ""


func test_bad_texts_give_an_empty_profile_and_a_message() -> String:
	var bad: Array[String] = [
		"", "not json", "[1, 2]", "{}",
		"{\"version\": 1, \"banked\": {}}",
		"{\"version\": 1, \"banked\": {}, \"crafted\": [], \"extra\": 1}",
		"{\"version\": 0, \"banked\": {}, \"crafted\": []}",
		"{\"version\": 1.5, \"banked\": {}, \"crafted\": []}",
		"{\"version\": true, \"banked\": {}, \"crafted\": []}",
		"{\"version\": 1, \"banked\": [], \"crafted\": []}",
		"{\"version\": 1, \"banked\": {\"ore\": -1}, \"crafted\": []}",
		"{\"version\": 1, \"banked\": {\"ore\": 1.5}, \"crafted\": []}",
		"{\"version\": 1, \"banked\": {}, \"crafted\": {}}",
		"{\"version\": 1, \"banked\": {}, \"crafted\": [3]}",
		"{\"version\": 1, \"banked\": {}, \"crafted\": [\"\"]}",
	]
	for text: String in bad:
		var profile: Profile = Profile.parse_json(text)
		if profile.error == "":
			return "accepted %s" % text
		if profile.too_new:
			return "%s read as too new" % text
		if not profile.banked.is_empty() or not profile.crafted.is_empty():
			return "%s left data in the rejected profile" % text
	return ""


func test_a_newer_version_is_refused_as_too_new() -> String:
	# A newer build may add keys; the version must be refused before they are judged.
	var profile: Profile = Profile.parse_json(
		"{\"version\": %d, \"banked\": {\"ore\": 9}, \"crafted\": [], \"crew\": []}" % (Profile.VERSION + 1))
	if profile.error == "" or not profile.too_new:
		return "a newer version was read: error '%s', too_new %s" % [profile.error, profile.too_new]
	if not profile.banked.is_empty():
		return "a refused profile kept %s" % profile.banked
	return ""
