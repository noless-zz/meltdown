extends RefCounted

## Component kinds as data (CRF-1, ARC-4, #925): each file parses, errors name
## the key and the file, ids are unique, and a new kind needs only a file.

const GOOD: String = "{\"id\": \"scrap_alloy\", \"display_name\": \"Scrap Alloy\", \"tier\": 1, \"map_colour\": \"#9aa3ad\"}"
const SHIPPED: Array[String] = ["scrap_alloy", "cell_salts", "circuit_shards", "core_glass"]


func test_good_text_sets_every_field() -> String:
	var kind: ComponentDef = ComponentDef.parse_json(GOOD)
	if kind.error != "":
		return kind.error
	if kind.id != "scrap_alloy" or kind.display_name != "Scrap Alloy" or kind.tier != 1 or kind.map_colour != "#9aa3ad":
		return "fields not read: %s %s %d %s" % [kind.id, kind.display_name, kind.tier, kind.map_colour]
	return ""


func test_rejects_each_bad_value() -> String:
	var cases: Dictionary = {
		"id": ["\"scrap_alloy\"", "\"Scrap\"", "\"\"", "3", "\"../x\""],
		"display_name": ["\"Scrap Alloy\"", "\"\"", "\"  \"", "7", "\"%s\"" % "x".repeat(65)],
		"tier": ["1", "0", "4", "1.5", "true", "\"1\""],
		"map_colour": ["\"#9aa3ad\"", "\"9aa3ad\"", "\"#9AA3AD\"", "\"#9aa3a\"", "\"#9aa3az\"", "12"],
	}
	for key: String in cases:
		var values: Array = cases[key]
		var good: String = values[0]
		for i: int in range(1, values.size()):
			var text: String = GOOD.replace("\"%s\": %s" % [key, good], "\"%s\": %s" % [key, values[i]])
			if text == GOOD:
				return "test case for %s did not change the text" % key
			var kind: ComponentDef = ComponentDef.parse_json(text)
			if kind.error == "" or not kind.error.contains("\"%s\"" % key):
				return "%s = %s: error \"%s\" does not name the key" % [key, values[i], kind.error]
			if kind.id != "":
				return "rejected kind kept its id"
	return ""


func test_rejects_missing_unknown_and_broken() -> String:
	for key: String in ComponentDef.KEYS:
		var json: JSON = JSON.new()
		json.parse(GOOD)
		var data: Dictionary = json.data
		data.erase(key)
		var kind: ComponentDef = ComponentDef.parse_json(JSON.stringify(data))
		if kind.error != "missing key \"%s\"" % key:
			return "missing %s gave \"%s\"" % [key, kind.error]
	var extra: ComponentDef = ComponentDef.parse_json(GOOD.replace("}", ", \"teir\": 2}"))
	if not extra.error.contains("unknown key \"teir\""):
		return "misspelt key gave \"%s\"" % extra.error
	if ComponentDef.parse_json("{").error == "":
		return "broken JSON accepted"
	if ComponentDef.parse_json("[]").error == "":
		return "a list accepted as a kind"
	return ""


func test_list_errors_name_the_file_and_key() -> String:
	var list: ComponentList = ComponentList.parse({
		"scrap_alloy.json": GOOD,
		"bad.json": GOOD.replace("\"tier\": 1", "\"tier\": 9").replace("scrap_alloy", "bad"),
	})
	if not (list.error.begins_with("bad.json: ") and list.error.contains("\"tier\"")):
		return "error \"%s\" does not name bad.json and tier" % list.error
	if not list.kinds.is_empty():
		return "a rejected list kept kinds"
	return ""


func test_list_rejects_duplicate_id() -> String:
	var list: ComponentList = ComponentList.parse({"a.json": GOOD, "b.json": GOOD.replace("Scrap Alloy", "Other")})
	if list.error != "b.json: key \"id\" is \"scrap_alloy\", already used by a.json":
		return "duplicate gave \"%s\"" % list.error
	if list.has_kind("scrap_alloy"):
		return "a rejected list still has a kind"
	return ""


func test_list_rejects_non_text() -> String:
	var list: ComponentList = ComponentList.parse({"a.json": 5})
	if not list.error.begins_with("a.json: "):
		return "non-text gave \"%s\"" % list.error
	return ""


func test_shipped_files_load_clean() -> String:
	var list: ComponentList = load_shipped()
	if list.error != "":
		return list.error
	var expected: Array[String] = SHIPPED.duplicate()
	expected.sort()
	if list.ids() != expected:
		return "shipped kinds are %s" % str(list.ids())
	var tiers: Dictionary[int, bool] = {}
	for kind: ComponentDef in list.kinds:
		tiers[kind.tier] = true
		if kind.id + ".json" not in DirAccess.get_files_at(ComponentList.COMPONENTS_DIR):
			return "kind %s is not in a file of its own name" % kind.id
	if tiers.size() != 3:
		return "shipped kinds cover tiers %s, want 1 to 3" % str(tiers.keys())
	return ""


## A kind is added by a file alone: no code names the new kind.
func test_new_kind_is_added_by_text_alone() -> String:
	var texts: Dictionary = shipped_texts()
	texts["vent_resin.json"] = "{\"id\": \"vent_resin\", \"display_name\": \"Vent Resin\", \"tier\": 2, \"map_colour\": \"#33aa55\"}"
	var list: ComponentList = ComponentList.parse(texts)
	if list.error != "":
		return list.error
	if not list.has_kind("vent_resin") or list.get_kind("vent_resin").tier != 2:
		return "new kind not loaded"
	if list.kinds.size() != SHIPPED.size() + 1:
		return "%d kinds" % list.kinds.size()
	return ""


func test_order_does_not_depend_on_input_order() -> String:
	var texts: Dictionary = shipped_texts()
	var reversed: Dictionary = {}
	var names: Array = texts.keys()
	names.reverse()
	for name: Variant in names:
		reversed[name] = texts[name]
	if ComponentList.parse(texts).ids() != ComponentList.parse(reversed).ids():
		return "order follows the caller's dictionary"
	return ""


static func shipped_texts() -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ComponentList.COMPONENTS_DIR):
		if file.get_extension() == "json":
			texts[file] = FileAccess.get_file_as_string("%s/%s" % [ComponentList.COMPONENTS_DIR, file])
	return texts


static func load_shipped() -> ComponentList:
	return ComponentList.parse(shipped_texts())
