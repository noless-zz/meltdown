class_name Profile
extends RefCounted

## The save that outlives a run (#928): components banked on escape (CRF-2) and,
## later, crafted upgrades (CRF-3). Lost runs keep it (RUN-7). This class is only
## the data and its JSON text; `ProfileStore` puts it on disk.

## The newest profile layout this build understands. A file with a higher number
## came from a newer build and is never read or overwritten (see ProfileStore).
const VERSION: int = 1
const KEY_VERSION: String = "version"
const KEY_BANKED: String = "banked"
const KEY_CRAFTED: String = "crafted"
const KEYS: Array[String] = [KEY_VERSION, KEY_BANKED, KEY_CRAFTED]

var version: int = VERSION
## Component id to count; only counts above zero are kept.
var banked: Dictionary[String, int] = {}
## Upgrade ids, in the order they were crafted. Nothing fills it yet.
var crafted: Array[String] = []
## Set when `parse_json` rejected the text; the profile is then empty.
var error: String = ""
## True when the text was rejected only because its version is newer than ours.
var too_new: bool = false


## Adds `counts` (component id to a whole number of at least 0) to the banked
## counts. Refuses the whole call, changing nothing, if any entry is not that.
func bank(counts: Dictionary) -> bool:
	if not _valid_counts(counts):
		return false
	for id: Variant in counts:
		var add: int = int(counts[id])
		if add > 0:
			banked[str(id)] = banked.get(str(id), 0) + add
	return true


## Takes `counts` from the banked counts. Refuses the whole call, changing
## nothing, if any count would go below zero or any entry is malformed.
func spend(counts: Dictionary) -> bool:
	if not _valid_counts(counts):
		return false
	for id: Variant in counts:
		if int(counts[id]) > banked.get(str(id), 0):
			return false
	for id: Variant in counts:
		var left: int = banked.get(str(id), 0) - int(counts[id])
		if left > 0:
			banked[str(id)] = left
		else:
			banked.erase(str(id))
	return true


## How many of component `id` are banked.
func count_of(id: String) -> int:
	return banked.get(id, 0)


## JSON text with sorted keys, so a profile that did not change writes the same bytes.
func to_json() -> String:
	var data: Dictionary = {
		KEY_VERSION: version,
		KEY_BANKED: banked.duplicate(),
		KEY_CRAFTED: crafted.duplicate(),
	}
	return JSON.stringify(data, "\t", true) + "\n"


## Reads the text `to_json` writes. A rejected text gives an empty profile with
## `error` set (and `too_new` when the version is the only reason); never a crash.
static func parse_json(text: String) -> Profile:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	# The version decides how the rest is read, so it is checked before the keys:
	# a newer build may have added keys this one does not know.
	if not data.has(KEY_VERSION) or not _whole_number(data[KEY_VERSION]):
		return _rejected("key \"%s\" must be a whole number" % KEY_VERSION)
	var file_version: int = int(data[KEY_VERSION])
	if file_version > VERSION:
		var newer: Profile = _rejected(
			"profile version %d is newer than this build reads (%d)" % [file_version, VERSION])
		newer.too_new = true
		return newer
	if file_version < 1:
		return _rejected("key \"%s\" is %d, must be at least 1" % [KEY_VERSION, file_version])
	for key: Variant in data:
		if not KEYS.has(str(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	if typeof(data[KEY_BANKED]) != TYPE_DICTIONARY or not _valid_counts(data[KEY_BANKED]):
		return _rejected("key \"%s\" must map component ids to whole numbers of at least 0" % KEY_BANKED)
	if typeof(data[KEY_CRAFTED]) != TYPE_ARRAY:
		return _rejected("key \"%s\" must be a list of upgrade ids" % KEY_CRAFTED)
	var profile: Profile = Profile.new()
	for item: Variant in data[KEY_CRAFTED]:
		if typeof(item) != TYPE_STRING or String(item).is_empty():
			return _rejected("key \"%s\" must be a list of upgrade ids" % KEY_CRAFTED)
		profile.crafted.append(String(item))
	profile.version = file_version
	profile.bank(data[KEY_BANKED])
	return profile


static func _valid_counts(counts: Dictionary) -> bool:
	for id: Variant in counts:
		if typeof(id) != TYPE_STRING or String(id).is_empty():
			return false
		if not _whole_number(counts[id]) or float(counts[id]) < 0.0:
			return false
	return true


## JSON gives every number as a float; a bool must not pass as 0 or 1.
static func _whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and number == floorf(number) and absf(number) < 1.0e15


static func _rejected(reason: String) -> Profile:
	var profile: Profile = Profile.new()
	profile.error = reason
	return profile
