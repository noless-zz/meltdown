extends RefCounted

## Rescued miners joining the profile's crew with a seeded role (#1010, CRW-1,
## SLV-3, ARC-1).

const DIR: String = "user://test_crew_roster"
## A fixed copy of the roles, so the pinned picks below do not move when the
## shipped roles file is tuned.
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""


func _roles() -> CrewRoles:
	return CrewRoles.parse_json(ROLES_TEXT)


func _member(id: String, role: String) -> Dictionary:
	return {Profile.CREW_ID: id, Profile.CREW_ROLE: role}


func test_two_miners_from_run_12345_level_0_get_pinned_roles() -> String:
	var expected: Array[Dictionary] = [_member("crew-1", "surveyor"), _member("crew-2", "shield_tech")]
	for attempt: int in 3:
		var profile: Profile = Profile.new()
		var reason: String = CrewRoster.add_rescued(profile, _roles(), 12345, 0, 2)
		if reason != "":
			return "refused: %s" % reason
		if profile.crew != expected:
			return "attempt %d gave %s" % [attempt + 1, profile.crew]
	return ""


func test_the_shipped_roles_file_parses_and_can_be_picked_from() -> String:
	var roles: CrewRoles = CrewRoles.parse_json(FileAccess.get_file_as_string(CrewRoles.ROLES_FILE))
	var profile: Profile = Profile.new()
	var reason: String = CrewRoster.add_rescued(profile, roles, 7, 1, 3)
	if reason != "" or profile.crew.size() != 3:
		return "reason '%s', crew %s" % [reason, profile.crew]
	return ""


func test_the_seed_depends_on_run_level_and_miner() -> String:
	var base: int = CrewRoster.miner_seed(12345, 0, 0)
	if base != CrewRoster.miner_seed(12345, 0, 0):
		return "the same inputs gave two seeds"
	for other: int in [CrewRoster.miner_seed(12346, 0, 0), CrewRoster.miner_seed(12345, 1, 0),
			CrewRoster.miner_seed(12345, 0, 1)]:
		if other == base:
			return "a different run, level or miner gave the same seed"
	return ""


func test_later_levels_append_with_new_unique_ids() -> String:
	var profile: Profile = Profile.new()
	CrewRoster.add_rescued(profile, _roles(), 12345, 0, 2)
	var reason: String = CrewRoster.add_rescued(profile, _roles(), 12345, 1, 3)
	if reason != "" or profile.crew.size() != 5:
		return "reason '%s', crew %s" % [reason, profile.crew]
	var ids: Dictionary[String, bool] = {}
	for member: Dictionary in profile.crew:
		ids[String(member[Profile.CREW_ID])] = true
	if ids.size() != 5 or not ids.has("crew-5"):
		return "ids not unique or not numbered on: %s" % [profile.crew]
	return ""


func test_an_id_already_taken_is_skipped() -> String:
	var profile: Profile = Profile.new()
	profile.crew.append(_member("crew-2", "surveyor"))
	CrewRoster.add_rescued(profile, _roles(), 1, 0, 2)
	var ids: Array[String] = []
	for member: Dictionary in profile.crew:
		ids.append(String(member[Profile.CREW_ID]))
	if ids != ["crew-2", "crew-3", "crew-4"]:
		return "ids %s" % [ids]
	return ""


func test_zero_rescued_adds_nothing() -> String:
	var profile: Profile = Profile.new()
	var before: String = profile.to_json()
	if CrewRoster.add_rescued(profile, _roles(), 12345, 0, 0) != "" or profile.to_json() != before:
		return "zero miners changed the profile to %s" % profile.to_json()
	return ""


func test_a_refused_add_leaves_the_profile_unchanged() -> String:
	var bad_roles: CrewRoles = CrewRoles.parse_json("{\"roles\": []}")
	var unknown: Profile = Profile.new()
	unknown.crew.append(_member("crew-1", "cook"))
	var duplicate: Profile = Profile.new()
	duplicate.crew.append(_member("crew-1", "surveyor"))
	duplicate.crew.append(_member("crew-1", "surveyor"))
	# Profile, roles, level index, count and why it must be refused.
	var cases: Array[Array] = [
		[Profile.new(), bad_roles, 0, 1, "roles that failed to parse"],
		[Profile.new(), null, 0, 1, "no roles"],
		[Profile.new(), _roles(), -1, 1, "a negative level"],
		[Profile.new(), _roles(), 0, -1, "a negative count"],
		[unknown, _roles(), 0, 1, "a crew entry with an unknown role"],
		[duplicate, _roles(), 0, 1, "a duplicate crew id"],
	]
	for case: Array in cases:
		var profile: Profile = case[0]
		profile.bank({"ore": 1})
		var before: String = profile.to_json()
		var reason: String = CrewRoster.add_rescued(profile, case[1], 12345, case[2], case[3])
		if reason == "":
			return "accepted %s" % case[4]
		if profile.to_json() != before:
			return "refusing %s changed the profile to %s" % [case[4], profile.to_json()]
	return ""


func test_check_names_an_entry_with_an_unknown_role() -> String:
	var profile: Profile = Profile.new()
	profile.crew.append(_member("crew-1", "surveyor"))
	profile.crew.append(_member("crew-2", "cook"))
	var message: String = CrewRoster.check(profile, _roles())
	if not message.contains("crew entry 2 (\"crew-2\")") or not message.contains("cook"):
		return "message: '%s'" % message
	profile.crew.pop_back()
	if CrewRoster.check(profile, _roles()) != "":
		return "a good crew failed the check"
	return ""


func test_crew_survives_a_save_and_reload() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: ProfileStore = ProfileStore.new(DIR + "/meltdown_profile.json")
	DirAccess.remove_absolute(store.path)
	var profile: Profile = Profile.new()
	CrewRoster.add_rescued(profile, _roles(), 12345, 0, 2)
	var saved: bool = store.save(profile)
	var read: Profile = ProfileStore.new(store.path).load_profile()
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())
	if not saved:
		return "save failed: %s" % store.message
	if read.crew != profile.crew or CrewRoster.check(read, _roles()) != "":
		return "read back %s" % [read.crew]
	return ""
