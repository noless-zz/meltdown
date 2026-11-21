class_name Crafting
extends RefCounted

## Crafting an upgrade between runs (CRF-3, #963): spends banked components from
## the profile and records the upgrade as crafted for good. The profile outlives
## lost runs (CRF-2, RUN-7), so a crafted upgrade does too. No hub screen yet;
## `available` gives it a stable list to show.


## Crafts upgrade `id`: spends its cost and appends it to `profile.crafted`.
## Returns "" on success, otherwise the reason from `UpgradeTree.missing`, with
## the profile exactly as it was.
static func craft(profile: Profile, tree: UpgradeTree, id: String) -> String:
	var reason: String = tree.missing(id, profile.crafted, profile.banked)
	if reason != "":
		return reason
	var upgrade: UpgradeDef = tree.get_upgrade(id)
	# `missing` already checked the counts; `spend` refuses as a whole, so even a
	# disagreement between the two cannot leave the profile half changed.
	if not profile.spend(upgrade.cost):
		return "\"%s\" could not spend its cost %s" % [id, upgrade.cost]
	profile.crafted.append(id)
	return ""


## Ids of the upgrades `profile` can craft now, sorted by branch (in the order
## of `UpgradeDef.BRANCHES`), then tier, then id, so a hub lists them the same
## way every time.
static func available(profile: Profile, tree: UpgradeTree) -> Array[String]:
	var ready: Array[UpgradeDef] = []
	for upgrade: UpgradeDef in tree.upgrades:
		if tree.missing(upgrade.id, profile.crafted, profile.banked) == "":
			ready.append(upgrade)
	ready.sort_custom(_before)
	var ids: Array[String] = []
	for upgrade: UpgradeDef in ready:
		ids.append(upgrade.id)
	return ids


static func _before(a: UpgradeDef, b: UpgradeDef) -> bool:
	var branch_a: int = UpgradeDef.BRANCHES.find(a.branch)
	var branch_b: int = UpgradeDef.BRANCHES.find(b.branch)
	if branch_a != branch_b:
		return branch_a < branch_b
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.id < b.id
