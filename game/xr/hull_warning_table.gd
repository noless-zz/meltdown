class_name HullWarningTable
extends RefCounted

## The low-hull warning tone's table (#1456, AUD-1, CMB-2, ARC-4), read from
## `res://data/audio/hull_warning.json`:
##
##     {
##       "threshold": 0.25,        # optional; at or below this hull fraction the tone repeats
##       "interval_s": 1.2,        # seconds between tones
##       "fast_threshold": 0.1,    # at or below this hull fraction ...
##       "fast_interval_s": 0.6,   # ... the tones come this often instead
##       "sound": "res://data/audio/hull_warning.wav",
##       "volume_db": -10.0
##     }
##
## Without `threshold` the warning starts where the status panel's hull bar
## turns red (`low_hull_fraction` in `xr/status_panel_look.json`), so the tone,
## the red bar and the low-hull pulse agree unless the file says otherwise.
## A wrong or unknown key names its field in `error`, and the warning stays
## silent rather than guessing.

const DEFAULT_FILE: String = "res://data/audio/hull_warning.json"
const KEYS: Array[String] = ["threshold", "interval_s", "fast_threshold", "fast_interval_s", "sound", "volume_db"]

var threshold: float = StatusPanel.HULL_WARNING_FRACTION
var interval_s: float = 1.2
var fast_threshold: float = 0.1
var fast_interval_s: float = 0.6
var sound: String = ""
var volume_db: float = 0.0
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


static func load_file(path: String = DEFAULT_FILE) -> HullWarningTable:
	if not FileAccess.file_exists(path):
		var missing: HullWarningTable = HullWarningTable.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path), float(StatusPanelLook.shared()["low_hull_fraction"]))


## The table in `text`; `panel_threshold` stands in for a missing `threshold`.
## On a rejected file `error` says why and `interval_for` is always 0.
static func parse(text: String, panel_threshold: float = StatusPanel.HULL_WARNING_FRACTION) -> HullWarningTable:
	var table: HullWarningTable = HullWarningTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	for key: Variant in root:
		if not KEYS.has(str(key)):
			return table._reject("%s is not a known field" % key)
	table.threshold = panel_threshold
	if root.has("threshold"):
		if not _fraction(root["threshold"]):
			return table._reject("threshold must be a number from 0 to 1")
		table.threshold = float(root["threshold"])
	if not _fraction(root.get("fast_threshold")) or float(root["fast_threshold"]) > table.threshold:
		return table._reject("fast_threshold must be a number from 0 to threshold (%.2f)" % table.threshold)
	table.fast_threshold = float(root["fast_threshold"])
	if not _number(root.get("interval_s")) or float(root["interval_s"]) <= 0.0:
		return table._reject("interval_s must be a number above 0")
	table.interval_s = float(root["interval_s"])
	if not _number(root.get("fast_interval_s")) or float(root["fast_interval_s"]) <= 0.0 \
			or float(root["fast_interval_s"]) > table.interval_s:
		return table._reject("fast_interval_s must be a number above 0 and at most interval_s")
	table.fast_interval_s = float(root["fast_interval_s"])
	if not root.get("sound") is String or not str(root["sound"]).begins_with("res://"):
		return table._reject("sound must be a res:// path")
	table.sound = str(root["sound"])
	if not _number(root.get("volume_db")):
		return table._reject("volume_db must be a number")
	table.volume_db = float(root["volume_db"])
	return table


## Seconds between tones at `hull_fraction`; 0 above the threshold, where the
## warning is silent, and always 0 for a rejected file.
func interval_for(hull_fraction: float) -> float:
	if error != "" or hull_fraction > threshold:
		return 0.0
	return fast_interval_s if hull_fraction <= fast_threshold else interval_s


static func _number(value: Variant) -> bool:
	return value is float or value is int


static func _fraction(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= 1.0


func _reject(why: String) -> HullWarningTable:
	error = why
	return self
