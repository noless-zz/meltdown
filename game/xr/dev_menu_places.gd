class_name DevMenuPlaces
extends RefCounted

## Where each dev menu entry shows (#1450, ARC-4, CRW-2, CMF-6): the menu opens
## wherever the pilot sits, and each entry of `res://xr/dev_menu.json` names the
## places it belongs to with an optional `"places"` list. In the mine every
## entry can show; at the home base, the shaft choice and the end screens only
## what makes sense there, so Level, Restart level, Flight test and Return to
## base list `mine` alone. An entry without the key shows everywhere, as every
## entry did before. Data only: nothing here reads or writes the simulation.

const MINE: String = "mine"
const BASE: String = "base"
const SHAFT: String = "shaft"
const END: String = "end"
const ALL: Array[String] = [MINE, BASE, SHAFT, END]
const KEY: String = "places"


## Reads `entry`'s places into `into` (every place when the key is absent).
## Returns why they were refused, or "".
static func read(entry: Dictionary, into: Array[String]) -> String:
	into.clear()
	if not entry.has(KEY):
		into.append_array(ALL)
		return ""
	var value: Variant = entry[KEY]
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "entry \"%s\" needs a non-empty \"places\" list" % str(entry.get("kind", ""))
	for item: Variant in value:
		if typeof(item) != TYPE_STRING or not ALL.has(str(item)) or into.has(str(item)):
			return "entry \"%s\" place %s is not one of %s or given twice" % [
				str(entry.get("kind", "")), str(item), ", ".join(ALL)]
		into.append(str(item))
	return ""


## Whether a parsed entry (`DevMenuSpec.entries`) shows at `place`.
static func shows(entry: Dictionary, place: String) -> bool:
	var places: Variant = entry.get(KEY, ALL)
	return (places as Array).has(place)
