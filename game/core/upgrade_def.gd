class_name UpgradeDef
extends RefCounted

## One craftable upgrade: a node of the tech tree (CRF-3, CRF-6). Upgrades are
## data so a new one is a file, not code (ARC-4). Parsed like `ComponentDef`:
## the caller reads the file and hands its text over, because core never opens
## files; `UpgradeTree` adds the file name to errors and checks the links
## between upgrades, which one file alone cannot see.

## Unique name of the upgrade. Lower case letters, digits and underscores.
var id: String = ""
## Name shown to the player, 1..64 characters.
var display_name: String = ""
## Branch of the tree, one of `BRANCHES` (CRF-6).
var branch: String = ""
## What the upgrade is, one of `KINDS`, as CRF-3 lists them.
var kind: String = ""
## Depth of the upgrade in its branch, 1 or more. Must be above the tier of
## every upgrade it requires.
var tier: int = 1
## Ids of the upgrades that must be crafted first; may be empty.
var requires: Array[String] = []
## Component kind id to whole count above 0, spent when crafting.
var cost: Dictionary[String, int] = {}
## Id of the part or module crafting makes available. For a weapon it names a
## file in `res://data/weapons/`.
var grants: String = ""

const KEYS: Array[String] = ["id", "name", "branch", "kind", "tier", "requires", "cost", "grants"]
const BRANCHES: Array[String] = ["weapons", "defence", "engines", "utility"]
const KINDS: Array[String] = ["weapon", "shield", "hull", "engine", "module"]
const NAME_MAX_LENGTH: int = 64

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of an upgrade data file. A missing or unknown key is an error
## naming the key. On failure the returned upgrade has `error` set and default
## values.
static func parse_json(text: String) -> UpgradeDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _failed("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _failed("missing key \"%s\"" % key)
	var message: String = ComponentDef.check_id("id", data["id"])
	if message == "":
		message = _check_name(data["name"])
	if message == "":
		message = _check_choice("branch", data["branch"], BRANCHES)
	if message == "":
		message = _check_choice("kind", data["kind"], KINDS)
	if message == "":
		message = _check_whole("tier", data["tier"])
	if message == "":
		message = _check_requires(data["requires"])
	if message == "":
		message = _check_cost(data["cost"])
	if message == "":
		message = ComponentDef.check_id("grants", data["grants"])
	if message != "":
		return _failed(message)
	var upgrade: UpgradeDef = UpgradeDef.new()
	upgrade.id = data["id"]
	upgrade.display_name = data["name"]
	upgrade.branch = data["branch"]
	upgrade.kind = data["kind"]
	upgrade.tier = int(data["tier"])
	for required: Variant in data["requires"]:
		upgrade.requires.append(str(required))
	var cost_data: Dictionary = data["cost"]
	var kinds: Array = cost_data.keys()
	kinds.sort()
	for component: Variant in kinds:
		upgrade.cost[str(component)] = int(cost_data[component])
	upgrade.grants = data["grants"]
	return upgrade


static func _check_name(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"name\" must be a string"
	var text: String = value
	if text.strip_edges().is_empty() or text.length() > NAME_MAX_LENGTH:
		return "key \"name\" must be 1 to %d characters" % NAME_MAX_LENGTH
	return ""


static func _check_choice(key: String, value: Variant, allowed: Array[String]) -> String:
	if typeof(value) != TYPE_STRING or not allowed.has(value):
		return "key \"%s\" is \"%s\", must be one of %s" % [key, str(value), ", ".join(allowed)]
	return ""


## A whole number of 1 or more. JSON numbers arrive as floats; a bool or a
## string must not pass.
static func _check_whole(key: String, value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "key \"%s\" must be a number" % key
	var number: float = float(value)
	if number != floorf(number) or number < 1.0:
		return "key \"%s\" is %s, must be a whole number above 0" % [key, number]
	return ""


static func _check_requires(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "key \"requires\" must be a list of upgrade ids"
	var seen: Array[String] = []
	for item: Variant in value:
		var message: String = ComponentDef.check_id("requires", item)
		if message != "":
			return message
		if seen.has(item):
			return "key \"requires\" names \"%s\" twice" % item
		seen.append(item)
	return ""


static func _check_cost(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"cost\" must be an object of component id to count"
	var cost_data: Dictionary = value
	if cost_data.is_empty():
		return "key \"cost\" must name at least one component"
	for component: Variant in cost_data:
		var message: String = ComponentDef.check_id("cost", component)
		if message != "":
			return message
		message = _check_whole("cost", cost_data[component])
		if message != "":
			return "%s (component \"%s\")" % [message, component]
	return ""


static func _failed(message: String) -> UpgradeDef:
	var upgrade: UpgradeDef = UpgradeDef.new()
	upgrade.error = message
	return upgrade
