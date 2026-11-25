class_name CrewGroups
extends RefCounted

## The crew counted by role for Crew Quarters (CRW-1, CRW-2, #1336), so three
## Cargo Riggers read as one row with the total they give, not three equal rows.
## Each role names one benefit (`CrewRoles`), so grouping by role groups by
## benefit too. The total is what a run gets: the role's summed amount, clamped
## to its stat's cap as `CrewBenefits.totals` clamps it; `capped` says so.


## One entry per role in the order its first member joined: `role`, `role_name`
## ("" when the roles file does not know it), `count`, `stat`, `each` (one
## member's amount), `total` (clamped) and `capped`. An unknown role keeps its
## id with stat "" and amounts 0, so the hub can still list it.
static func of(profile: Profile, roles: CrewRoles) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var by_role: Dictionary[String, Dictionary] = {}
	for member: Dictionary in profile.crew:
		var role: String = str(member.get(Profile.CREW_ROLE, ""))
		if not by_role.has(role):
			by_role[role] = {
				"role": role,
				"role_name": roles.role_name(role),
				"count": 0,
				"stat": roles.benefit_stat(role),
				"each": roles.benefit_amount(role),
			}
			groups.append(by_role[role])
		by_role[role]["count"] = int(by_role[role]["count"]) + 1
	for group: Dictionary in groups:
		var summed: int = int(group["each"]) * int(group["count"])
		var cap: int = roles.cap(group["stat"]) if roles.has_role(group["role"]) else summed
		group["total"] = mini(summed, cap)
		group["capped"] = summed > cap
	return groups
