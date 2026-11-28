class_name DevMenuIcons
extends RefCounted

## Reads the `icons` block of `dev_menu.json` (#1458, ARC-4): which icon of the
## base's set (`HubIcons`, `res://data/hub/icons.json`) each row of the menu
## shows beside its label.
##
##     "icons": {"back": "menu/back",
##               "sections": {"Comfort": "menu/comfort_section", ...},
##               "entries": {"comfort": "menu/comfort", ...}}
##
## An icon is named `<group>/<id>`. Every key is optional, so a row with no icon
## named shows none; a named icon the set does not draw shows its plain marker
## (`HubIcons.icon`). Split from `DevMenuSpec` so that file stays under about
## 300 lines. Nothing here reads or writes the simulation (ARC-3).

const KEYS: Array[String] = ["back", "sections", "entries"]
const BACK_KEY: String = "back"
const SECTION_PREFIX: String = "section:"


## Fills `icons` from `value`, keyed `back`, `section:<label>` or an entry kind.
## `sections` and `kinds` are the file's own; a name for anything else is
## refused. Returns why `value` was refused, or "".
static func read(value: Variant, sections: Array[Dictionary], kinds: Array[String],
		icons: Dictionary[String, String]) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"icons\" must be an object"
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(str(key)):
			return "icons has an unknown key \"%s\"" % str(key)
	if data.has(BACK_KEY):
		if not is_name(data[BACK_KEY]):
			return "icons.back must be \"<group>/<id>\""
		icons[BACK_KEY] = data[BACK_KEY]
	var labels: Array[String] = []
	for section: Dictionary in sections:
		labels.append(str(section["label"]))
	for pair: Array in [["sections", labels, SECTION_PREFIX], ["entries", kinds, ""]]:
		if not data.has(pair[0]):
			continue
		if typeof(data[pair[0]]) != TYPE_DICTIONARY:
			return "icons.%s must be an object" % pair[0]
		for key: Variant in data[pair[0]]:
			if not (pair[1] as Array).has(str(key)):
				return "icons.%s names \"%s\", which the file does not list" % [pair[0], key]
			if not is_name(data[pair[0]][key]):
				return "icons.%s.%s must be \"<group>/<id>\"" % [pair[0], key]
			icons[str(pair[2]) + str(key)] = data[pair[0]][key]
	return ""


## Whether `value` is `<group>/<id>`, both parts non-empty.
static func is_name(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var parts: PackedStringArray = (value as String).split("/")
	return parts.size() == 2 and parts[0] != "" and parts[1] != ""


## The icon name row `row` (as `DevMenuRows` numbers rows) shows, or "".
static func name_for(spec: DevMenuSpec, row: int) -> String:
	if row == DevMenuRows.BACK:
		return spec.icons.get(BACK_KEY, "")
	var section: int = DevMenuRows.section_of(row)
	if section != -1:
		return spec.icons.get(SECTION_PREFIX + str(spec.sections[section]["label"]), "")
	if row >= 0 and row < spec.entries.size():
		return spec.icons.get(str(spec.entries[row]["kind"]), "")
	return ""
