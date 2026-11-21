class_name CrewRoles
extends RefCounted

## The roles a rescued miner can have and the small permanent benefit each one
## unlocks (CRW-1, SLV-3). Roles are data so a new one is a file entry, not
## code (ARC-4). The caller reads `ROLES_FILE` and hands its text over, because
## core never opens files. What a benefit does to a run is wired later; here a
## benefit is only a known stat and a small whole amount.

const ROLES_FILE: String = "res://data/crew/roles.json"

## Every stat a benefit may raise, with the largest amount one role may give.
## The caps keep each benefit small, so crew widens options without
## trivialising early levels (CRW-3). A new stat needs code that applies it,
## so it is added here when that code exists.
const STAT_MAX: Dictionary[String, int] = {
	"shield_max": 10,
	"salvage_slots": 1,
	"meltdown_seconds": 10,
	"map_reveal": 1,
}
## Keys of one role entry and of its benefit; all are required, no others.
const ROLE_KEYS: Array[String] = ["id", "name", "weight", "benefit"]
const BENEFIT_KEYS: Array[String] = ["stat", "amount"]
const ID_MAX_LENGTH: int = 64
const NAME_MAX_LENGTH: int = 64
## Mixed into the pick seed so a role pick never shares a random stream with
## another system seeded from the same number.
const STREAM_SALT: String = "crew_role"

## Role ids in file order; `pick` walks them in this order.
var ids: Array[String] = []
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""
var _names: Dictionary[String, String] = {}
var _weights: Dictionary[String, int] = {}
var _stats: Dictionary[String, String] = {}
var _amounts: Dictionary[String, int] = {}
var _total_weight: int = 0


## Parses the text of the roles file. Each error names the role (by id, or by
## position when the id itself is the problem) and the key. On failure `error`
## is set and no role is kept, so no caller works with part of the list.
static func parse_json(text: String) -> CrewRoles:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if str(key) != "roles":
			return _failed("unknown key \"%s\"" % str(key))
	if not data.has("roles"):
		return _failed("missing key \"roles\"")
	if typeof(data["roles"]) != TYPE_ARRAY or (data["roles"] as Array).is_empty():
		return _failed("key \"roles\" must be a non-empty array")
	var roles: CrewRoles = CrewRoles.new()
	var entries: Array = data["roles"]
	for i: int in entries.size():
		var message: String = roles._add(i, entries[i])
		if message != "":
			return _failed(message)
	return roles


## Picks a role id by weight. The same seed always gives the same role, and
## the generator is local to the call so nothing else's stream moves (ARC-1).
func pick(role_seed: int) -> String:
	if ids.is_empty():
		return ""
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([role_seed, STREAM_SALT])
	var roll: int = rng.randi_range(1, _total_weight)
	for id: String in ids:
		roll -= _weights[id]
		if roll <= 0:
			return id
	return ids[ids.size() - 1]


## True when a role with this id exists.
func has_role(id: String) -> bool:
	return _weights.has(id)


## Name shown to the player, or "" for an unknown id.
func role_name(id: String) -> String:
	return _names.get(id, "")


## Pick weight of the role, or 0 for an unknown id.
func weight(id: String) -> int:
	return _weights.get(id, 0)


## Sum of every role's weight.
func total_weight() -> int:
	return _total_weight


## Stat the role's benefit raises, or "" for an unknown id.
func benefit_stat(id: String) -> String:
	return _stats.get(id, "")


## Amount the role's benefit adds to its stat, or 0 for an unknown id.
func benefit_amount(id: String) -> int:
	return _amounts.get(id, 0)


func _add(index: int, entry: Variant) -> String:
	var label: String = "role %d" % (index + 1)
	if typeof(entry) != TYPE_DICTIONARY:
		return "%s: must be a JSON object" % label
	var role: Dictionary = entry
	if role.has("id") and typeof(role["id"]) == TYPE_STRING and not (role["id"] as String).is_empty():
		label = "role \"%s\"" % role["id"]
	for key: Variant in role:
		if typeof(key) != TYPE_STRING or not ROLE_KEYS.has(key):
			return "%s: unknown key \"%s\"" % [label, str(key)]
	for key: String in ROLE_KEYS:
		if not role.has(key):
			return "%s: missing key \"%s\"" % [label, key]
	var message: String = _check_id(role["id"])
	if message == "" and _weights.has(role["id"]):
		message = "key \"id\" is \"%s\", already used by an earlier role" % role["id"]
	if message == "":
		message = _check_name(role["name"])
	if message == "":
		message = _check_whole("weight", role["weight"], 1, 1000000)
	if message == "":
		message = _check_benefit(role["benefit"])
	if message != "":
		return "%s: %s" % [label, message]
	var id: String = role["id"]
	var benefit: Dictionary = role["benefit"]
	ids.append(id)
	_names[id] = role["name"]
	_weights[id] = int(role["weight"])
	_stats[id] = benefit["stat"]
	_amounts[id] = int(benefit["amount"])
	_total_weight += _weights[id]
	return ""


static func _check_id(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"id\" must be a string"
	var text: String = value
	if text.is_empty() or text.length() > ID_MAX_LENGTH:
		return "key \"id\" must be 1 to %d characters" % ID_MAX_LENGTH
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return "key \"id\" is \"%s\", must use only a-z, 0-9 and _" % text
	return ""


static func _check_name(value: Variant) -> String:
	if typeof(value) != TYPE_STRING or (value as String).strip_edges().is_empty():
		return "key \"name\" must be a non-blank string"
	if (value as String).length() > NAME_MAX_LENGTH:
		return "key \"name\" must be at most %d characters" % NAME_MAX_LENGTH
	return ""


static func _check_benefit(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"benefit\" must be a JSON object"
	var benefit: Dictionary = value
	for key: Variant in benefit:
		if typeof(key) != TYPE_STRING or not BENEFIT_KEYS.has(key):
			return "key \"benefit\" has unknown key \"%s\"" % str(key)
	for key: String in BENEFIT_KEYS:
		if not benefit.has(key):
			return "key \"benefit\" is missing key \"%s\"" % key
	var stat: Variant = benefit["stat"]
	if typeof(stat) != TYPE_STRING or not STAT_MAX.has(stat):
		return "key \"stat\" is \"%s\", must be one of %s" % [str(stat), ", ".join(STAT_MAX.keys())]
	return _check_whole("amount", benefit["amount"], 1, STAT_MAX[stat])


## JSON numbers arrive as floats, so a whole number is a float with no
## fraction; booleans and strings are refused.
static func _check_whole(key: String, value: Variant, low: int, high: int) -> String:
	var ok: bool = typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and float(value) == floorf(float(value)))
	if not ok or int(value) < low or int(value) > high:
		return "key \"%s\" is %s, must be a whole number from %d to %d" % [key, str(value), low, high]
	return ""


static func _failed(message: String) -> CrewRoles:
	var roles: CrewRoles = CrewRoles.new()
	roles.error = message
	return roles
