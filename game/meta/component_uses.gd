class_name ComponentUses
extends RefCounted

## What a banked component is for (CRF-3, CRF-5, #1336): the upgrades whose cost
## names it, so the Parts Locker can say "For Needle Gun +17" instead of only a
## count. Read from the upgrade files (ARC-4); nothing here is per component.

## Names a Parts Locker note lists before it counts the rest; one keeps the
## note inside `max_row_chars` (#1300).
const SHOWN: int = 1


## Display names of the upgrades in `upgrades` (in their order) whose cost
## names component `id`. Empty when no upgrade uses it.
static func names(upgrades: Array[UpgradeDef], id: String) -> Array[String]:
	var out: Array[String] = []
	for upgrade: UpgradeDef in upgrades:
		if upgrade.cost.has(id):
			out.append(upgrade.display_name)
	return out


## The Parts Locker note of component `id`: the first `SHOWN` names, a count
## of the rest, or the "not used yet" words, all from `words` (NAM-3, ARC-4).
static func line(words: HubWords, upgrades: Array[UpgradeDef], id: String) -> String:
	var used: Array[String] = names(upgrades, id)
	if used.is_empty():
		return words.row("store_unused")
	var listed: String = words.row("list_join").join(used.slice(0, SHOWN))
	if used.size() <= SHOWN:
		return words.row("store_uses", {"names": listed})
	return words.row("store_uses_more", {"names": listed, "count": used.size() - SHOWN})
