class_name RunEscapeBank
extends RefCounted

## Banks one escaped run level (#977, #1032, #1092; RUN-7, CRF-2, CRW-1,
## CRW-2, SLV-3), split out of `RunWiring` (#1136) so the run's level flow and
## its bank-and-save path each stay small enough to change on their own.
##
## The level's components are banked into the profile (`RunBanking`), its
## rescued miners join the crew (`CrewRoster.add_rescued`, a role seeded by the
## run seed and the escaped level's index), the escape is counted in the
## statistics (`RunStatsRecorder`), and the profile is saved once for all three.
## A refused bank or crew join is logged and the rest still happens: the run
## flies on. A rejected roles file was logged once when it was read, so an
## escape then adds no crew without another line.
##
## It holds no state between escapes; `RunWiring` keeps `error` and
## `crew_error` as before and copies the outcome from here.

const LOG_PREFIX: String = "Meltdown: run"

## Why the escape was refused, the bank failed or the save failed; empty when
## all went well. Set the way `RunWiring.error` always was: the last problem wins.
var error: String = ""
## Why miners were rescued but none joined; empty otherwise.
var crew_error: String = ""
## True when `RunState.advance` refused the escape: nothing was banked or saved
## and the crew was not looked at.
var refused: bool = false


## Banks the escape of level `level_index` of `state`'s run: `counts` from
## `RunState.advance` and `rescued` miners into `profile`, counted by `stats`,
## then one save to `store` (none when it is null).
static func bank(state: RunState, counts: Dictionary[String, int], level_index: int, rescued: int,
		profile: Profile, store: ProfileStore, roles: CrewRoles, stats: RunStatsRecorder) -> RunEscapeBank:
	var result: RunEscapeBank = RunEscapeBank.new()
	if state.error != "":
		result.refused = true
		result._note("the escape was refused: %s" % state.error)
		return result
	var banked: Dictionary[String, int] = {}
	if not counts.is_empty():
		var problem: String = RunBanking.bank_escape(profile, counts)
		if problem != "":
			result._note(problem)
		else:
			banked = counts
	var joined: int = rescued if result._add_crew(profile, roles, state.plan.run_seed, level_index, rescued) else 0
	stats.escaped(profile, level_index, joined, banked)
	if store != null and not store.save(profile):
		result._note(store.message)
		stats.fail("the escape was not saved: %s" % store.message)
	return result


## The crew roles read from `text`, the roles file's text. A rejected file logs
## one line here; escapes then add no crew.
static func read_roles(text: String) -> CrewRoles:
	var roles: CrewRoles = CrewRoles.parse_json(text)
	if roles.error != "":
		print("%s: %s rejected, rescued miners will not join the crew: %s" % [LOG_PREFIX,
			CrewRoles.ROLES_FILE, roles.error])
	return roles


func _note(problem: String) -> void:
	error = problem
	print("%s: %s" % [LOG_PREFIX, problem])


## Adds `rescued` miners from level `level_index` to the crew; true when any
## joined. A refusal is logged and leaves the crew as it was.
func _add_crew(profile: Profile, roles: CrewRoles, run_seed: int, level_index: int, rescued: int) -> bool:
	if rescued <= 0:
		return false
	if roles == null or roles.error != "":
		crew_error = "no crew roles"  # Logged once when the roles file was read.
		return false
	crew_error = CrewRoster.add_rescued(profile, roles, run_seed, level_index, rescued)
	if crew_error != "":
		print("%s: %d rescued miners did not join the crew: %s" % [LOG_PREFIX, rescued, crew_error])
		return false
	print("%s %d: %d rescued miners joined the crew" % [LOG_PREFIX, run_seed, rescued])
	return true
