class_name CrewRoster
extends RefCounted

## Turns a level's rescued miners into crew on the profile (CRW-1, SLV-3, #1010).
## Each miner's role is rolled by `CrewRoles.pick` from a seed made of the run
## seed, the level index and the miner's number within that level, so the same
## run always gives the same crew and nothing here draws unseeded randomness
## (ARC-1, ARC-2).
##
## Miners count only once the level is escaped, like components (SLV-3, CRF-2):
## the caller adds crew at escape, and a lost run adds nothing (RUN-7). This
## class does not decide when that is; `RunBanking` and the run wiring (lane-b)
## call `add_rescued` from the escape path.

const ID_PREFIX: String = "crew-"
## Mixed into each miner's seed so it never matches a seed another system
## derives from the same run seed and level.
const SEED_SALT: String = "rescued_miner"


## Appends `count` rescued miners to `profile.crew`, each with a seeded role.
## Returns "" on success or the reason it refused; a refusal leaves the profile
## exactly as it was.
static func add_rescued(profile: Profile, roles: CrewRoles, run_seed: int, level_index: int, count: int) -> String:
	if roles == null or roles.error != "" or roles.ids.is_empty():
		return "no crew roles to pick from%s" % ("" if roles == null or roles.error == "" else ": " + roles.error)
	if level_index < 0:
		return "level index %d must be at least 0" % level_index
	if count < 0:
		return "rescued count %d must be at least 0" % count
	var existing: String = check(profile, roles)
	if existing != "":
		return "the profile's crew is invalid: %s" % existing
	var joined: Array[Dictionary] = []
	var used: Dictionary[String, bool] = {}
	for member: Dictionary in profile.crew:
		used[String(member[Profile.CREW_ID])] = true
	var number: int = profile.crew.size()
	for miner: int in count:
		var role: String = roles.pick(miner_seed(run_seed, level_index, miner))
		if not roles.has_role(role):
			return "role pick for miner %d gave unknown role \"%s\"" % [miner + 1, role]
		number += 1
		while used.has(ID_PREFIX + str(number)):
			number += 1
		var id: String = ID_PREFIX + str(number)
		used[id] = true
		joined.append({Profile.CREW_ID: id, Profile.CREW_ROLE: role})
	profile.crew.append_array(joined)
	return ""


## Seed for miner `miner` (counted from 0) rescued on level `level_index` of the
## run seeded `run_seed`.
static func miner_seed(run_seed: int, level_index: int, miner: int) -> int:
	return hash([run_seed, level_index, miner, SEED_SALT])


## Error naming the first bad crew entry, or "" when the crew is well formed and
## every role is one `roles` knows.
static func check(profile: Profile, roles: CrewRoles) -> String:
	var shape: String = Profile.crew_error(profile.crew)
	if shape != "":
		return shape
	for i: int in profile.crew.size():
		var member: Dictionary = profile.crew[i]
		if not roles.has_role(String(member[Profile.CREW_ROLE])):
			return "crew entry %d (\"%s\") has unknown role \"%s\"" % [
				i + 1, member[Profile.CREW_ID], member[Profile.CREW_ROLE]]
	return ""
