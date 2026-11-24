class_name ProjectileWeaponLooks
extends RefCounted

## The per-weapon part of `projectile_look.json` (#1309, GFX-2, ARC-4): under
## `weapons`, each weapon id holds any of `KEYS`, which replace the file's own
## value for that weapon's bolts. A weapon with no row, or a key left out of
## its row, keeps the file's value, so every weapon is one data row and no
## weapon is a code branch.
##
## A ship's bolt is its slot's weapon; a robot's bolt is its robot's weapon,
## then the `robot` row. View only: it reads the ships and robots it is given
## and keeps nothing of them (MP-2).

## The keys a weapon's row may set.
const KEYS: Array[String] = [
	"bolt_shape", "bolt_length_m", "bolt_radius_m", "emission_color",
	"trail_length_m", "trail_color", "muzzle_flash_radius_m", "spark_color",
]
## The row robot bolts fall back to before the file's own values.
const ROBOT_ROW: String = "robot"
## The name of a bolt with no known weapon: the file's own values.
const NO_WEAPON: String = ""


## Checks the `weapons` value of a look file: an object of weapon id to an
## object of `KEYS`. Returns weapon id to its checked values, or a dictionary
## holding only `"error"`, which names the weapon and key.
static func parse(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "key \"weapons\" must be an object of weapon id to look"}
	var rows: Dictionary = {}
	for id: Variant in data:
		if typeof(id) != TYPE_STRING or (id as String).is_empty():
			return {"error": "weapons: an id must be a non-empty name"}
		if typeof(data[id]) != TYPE_DICTIONARY:
			return {"error": "weapons \"%s\" must be an object" % id}
		var row: Dictionary = data[id]
		var values: Dictionary = {}
		for key: Variant in row:
			if typeof(key) != TYPE_STRING or not KEYS.has(key):
				return {"error": "weapons \"%s\": unknown key \"%s\"" % [id, str(key)]}
			var checked: Variant = ProjectileLook.check_value(key, row[key])
			if checked is Dictionary:
				return {"error": "weapons \"%s\": %s" % [id, checked["error"]]}
			values[key] = checked
		rows[id] = values
	return rows


## The look of `weapon`'s bolts: `look` (parsed, with `weapons`) with the
## weapon's row laid over it. An unknown weapon gets `look` unchanged.
static func look_for(look: Dictionary, weapon: String) -> Dictionary:
	var merged: Dictionary = {}
	for key: String in KEYS:
		merged[key] = look[key]
	var rows: Dictionary = look.get(ProjectileLook.WEAPONS_KEY, {})
	if rows.has(weapon):
		merged.merge(rows[weapon], true)
	return merged


## The row name for `projectile`: the weapon in the slot that fired it, or the
## robot's weapon (or `robot` when that has no row in `rows`); `NO_WEAPON`
## when it cannot be told.
static func weapon_of(projectile: Projectile, ships: Array[ShipState], robots: Array[RobotState],
		rows: Dictionary) -> String:
	if projectile.is_robot_owned():
		var robot: int = -1 - projectile.owner_index
		if robot < robots.size() and robots[robot] != null and robots[robot].def != null \
				and rows.has(robots[robot].def.weapon):
			return robots[robot].def.weapon
		return ROBOT_ROW
	var owner: int = projectile.owner_index
	if owner < ships.size() and ships[owner] != null and projectile.slot < ships[owner].primary_ids.size():
		return ships[owner].primary_ids[projectile.slot]
	return NO_WEAPON
