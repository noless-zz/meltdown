class_name FittingStore
extends RefCounted

## Keeps the pilot's `Fitting` on disk beside the profile (CRF-4, CMB-1, #1031),
## so the hub can set it and a run can read it later. It is its own small file
## rather than part of the profile, so crafting and crew changes never touch it
## and a damaged fitting file only empties the fitting. A save goes through
## `SafeFileWrite`, as `ProfileStore` does: a kill at any moment leaves the old
## file or the new one whole. The file name uses the codename (NAM-1).
##
## On disk the fitting sits under a version number, because `Fitting` itself has
## none and refuses unknown keys: a later build that adds a slot kind raises the
## version, and this build then leaves that file alone instead of saving over it.
## Version 2 added the shield, hull and engine part slots (#1055); a version-1
## file still reads, with those slots empty.

const DEFAULT_PATH: String = "user://meltdown_fitting.json"
const VERSION: int = 2
const KEY_VERSION: String = "version"
const KEY_FITTING: String = "fitting"
const LOG_PREFIX: String = "[meltdown fitting]"

var path: String = DEFAULT_PATH
## What the last `load_fitting` or `save` had to say; empty when all went well.
var message: String = ""
## Set when the file on disk came from a newer build. Saves are then refused, so
## the newer fitting is left exactly as it is.
var locked: bool = false
## Test seam: the save writes the temporary file and stops before the rename,
## as a kill at that moment would.
var stop_before_rename: bool = false


func _init(fitting_path: String = DEFAULT_PATH) -> void:
	path = fitting_path


func temp_path() -> String:
	return SafeFileWrite.temp_path(path)


## Reads the fitting. A missing file gives an empty fitting quietly. A corrupt
## or too-new file gives an empty fitting, logs one line and stays on disk
## untouched; a too-new one also locks the store against saving. A temporary
## file left by a killed save is ignored.
func load_fitting() -> Fitting:
	message = ""
	locked = false
	if not FileAccess.file_exists(path):
		return Fitting.new()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _unreadable("cannot open it (%s)" % error_string(FileAccess.get_open_error()))
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _unreadable("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _unreadable("top level must be a JSON object")
	var data: Dictionary = json.data
	var version: Variant = data.get(KEY_VERSION)
	if (typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT) or float(version) != floorf(float(version)):
		return _unreadable("key \"%s\" must be a whole number" % KEY_VERSION)
	if int(version) > VERSION:
		locked = true
		message = "%s: fitting version %d is newer than this build reads (%d); it is left untouched and this build will not save over it" % [
			path, int(version), VERSION]
		print("%s %s" % [LOG_PREFIX, message])
		return Fitting.new()
	if int(version) < 1:
		return _unreadable("key \"%s\" is %d, must be 1 to %d" % [KEY_VERSION, int(version), VERSION])
	for key: Variant in data:
		if key != KEY_VERSION and key != KEY_FITTING:
			return _unreadable("unknown key \"%s\"" % str(key))
	if not data.has(KEY_FITTING):
		return _unreadable("missing key \"%s\"" % KEY_FITTING)
	var read: Fitting = Fitting.parse_json(JSON.stringify(data[KEY_FITTING]))
	if read.error != "":
		return _unreadable(read.error)
	return read


## Writes `fitting` safely (see the class comment). Returns false, with
## `message` set and the old file unchanged, when it could not.
func save(fitting: Fitting) -> bool:
	message = ""
	if locked:
		message = "%s came from a newer build; not saving over it" % path
		return false
	var failure: String = SafeFileWrite.write(path, to_file_text(fitting), "fitting", stop_before_rename)
	if failure != "":
		message = failure
		return false
	return true


## The text `save` writes: the fitting's own JSON under a version number, with
## sorted keys so an unchanged fitting writes the same bytes.
static func to_file_text(fitting: Fitting) -> String:
	var data: Dictionary = {
		KEY_VERSION: VERSION,
		KEY_FITTING: JSON.parse_string(fitting.to_json()),
	}
	return JSON.stringify(data, "\t", true) + "\n"


## A copy of `fitting` without the slots `Fitting.check` would refuse on this
## profile and ship (an upgrade no longer known or not crafted here, a second
## copy of one upgrade, a utility slot the ship lacks, a wrong kind, part slots
## included), so a stale
## file never stops a run. Each dropped slot logs one line and, when `notes` is
## given, is appended to it. Slots are judged in slot order, so of two slots
## holding the same upgrade the first is kept. Never changes `fitting`.
static func valid_for(fitting: Fitting, tree: UpgradeTree, crafted: Array[String], ship_data: Dictionary, notes: Array[String] = []) -> Fitting:
	var kept: Fitting = Fitting.new()
	kept.utility.resize(fitting.utility.size())
	kept.utility.fill("")
	for kind: String in Fitting.KEYS:
		var ids: Array[String] = fitting.ids_of(kind)
		for slot: int in ids.size():
			if ids[slot] == "":
				continue
			kept.ids_of(kind)[slot] = ids[slot]
			var reason: String = Fitting.check(kept, tree, crafted, ship_data)
			if reason != "":
				kept.ids_of(kind)[slot] = ""
				var line: String = "dropped %s" % reason
				notes.append(line)
				print("%s %s" % [LOG_PREFIX, line])
	for slot: String in Fitting.PART_KEYS:
		if fitting.parts[slot] == "":
			continue
		kept.parts[slot] = fitting.parts[slot]
		var reason: String = Fitting.check(kept, tree, crafted, ship_data)
		if reason != "":
			kept.parts[slot] = ""
			var line: String = "dropped %s" % reason
			notes.append(line)
			print("%s %s" % [LOG_PREFIX, line])
	return kept


func _unreadable(reason: String) -> Fitting:
	message = "%s is unreadable (%s); starting with an empty fitting and leaving the file as it is" % [path, reason]
	print("%s %s" % [LOG_PREFIX, message])
	return Fitting.new()
