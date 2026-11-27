class_name DevMenuLists
extends RefCounted

## Reads the `corners` and `schemes` lists of `res://xr/dev_menu.json` (#753,
## #778). Split from `DevMenuSpec` (#1450) so that file stays under about 300
## lines once each entry could name its places.


## Appends each corner in `value` to `corners`. Returns why `value` was refused, or "".
static func read_corners(value: Variant, corners: Array[String]) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"corners\" must be a non-empty list"
	for item: Variant in value:
		var corner: String = str(item)
		if typeof(item) != TYPE_STRING or corner == "" or corners.has(corner):
			return "corner %s is empty, not text or given twice" % str(item)
		for character: String in corner:
			if not DevMenuSpec.NAME_CHARACTERS.contains(character):
				return "corner \"%s\" is not a name" % corner
		corners.append(corner)
	return ""


## Replaces `schemes` with the schemes in `value`, each one of
## `ControlSchemeSwitch.SCHEMES`. Returns why `value` was refused, or "".
static func read_schemes(value: Variant, schemes: Array[String]) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"schemes\" must be a non-empty list"
	schemes.clear()
	for item: Variant in value:
		var scheme: String = str(item)
		if typeof(item) != TYPE_STRING or not ControlSchemeSwitch.SCHEMES.has(scheme) \
				or schemes.has(scheme):
			return "scheme %s is not one of %s or given twice" % [
				str(item), ", ".join(ControlSchemeSwitch.SCHEMES)]
		schemes.append(scheme)
	return ""
