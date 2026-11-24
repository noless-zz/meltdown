class_name DevMenuSections
extends RefCounted

## Reads the `sections` list of `dev_menu.json` (#1301, ARC-4): which entries
## each section row opens, in order. Split from `DevMenuSpec` so that file
## stays under about 300 lines.


## Appends each section in `value` to `sections` as `{"label": ..., "kinds": [...]}`.
## Every named kind must be in `listed` (the file's entries) and in one section
## only. Returns why `value` was rejected, or "".
static func read(value: Variant, listed: Array[String], sections: Array[Dictionary]) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "\"sections\" must be a list"
	var seen: Array[String] = []
	for item: Variant in value:
		if typeof(item) != TYPE_DICTIONARY or (item as Dictionary).keys().size() != 2 \
				or not (item as Dictionary).has("label") or not (item as Dictionary).has("entries"):
			return "a section must have exactly \"label\" and \"entries\""
		var section: Dictionary = item
		if typeof(section["label"]) != TYPE_STRING or (section["label"] as String).strip_edges() == "":
			return "every section needs a non-empty label"
		if typeof(section["entries"]) != TYPE_ARRAY or (section["entries"] as Array).is_empty():
			return "section \"%s\" needs a non-empty list of entries" % section["label"]
		var kinds: Array[String] = []
		for kind: Variant in section["entries"]:
			if not listed.has(str(kind)):
				return "section \"%s\" names \"%s\", which is not an entry" % [section["label"], kind]
			if seen.has(str(kind)):
				return "entry \"%s\" is in more than one section" % kind
			seen.append(str(kind))
			kinds.append(str(kind))
		sections.append({"label": section["label"], "kinds": kinds})
	return ""
