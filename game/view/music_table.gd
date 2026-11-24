class_name MusicTable
extends RefCounted

## The music table (#1303, AUD-3, ARC-4), read from `res://data/audio/music.json`:
##
##     {
##       "volume_db": -12.0,          # the music's own volume, apart from the cues'
##       "crossfade_seconds": 2.5,    # layers join and leave over this
##       "meltdown_seconds": 0.6,     # the meltdown track takes over within this, at most 1
##       "end_fade_seconds": 2.0,     # the escape and destroyed screens fade out over this
##       "layers": [{"id": "calm", "plays": "run", "from_alarm": 0.0,
##                   "sound": "res://...", "volume_db": -2.0}, ...]
##     }
##
## There is at least one `run` layer from alarm 0, one `meltdown` layer and
## one `hub` layer. Every fade is longer than zero, so nothing is ever cut.

const DEFAULT_FILE: String = "res://data/audio/music.json"
## The meltdown switch must be heard within a second of the reactor's end.
const MELTDOWN_SECONDS_MAX: float = 1.0

var volume_db: float = -12.0
var crossfade_seconds: float = 2.5
var meltdown_seconds: float = 0.6
var end_fade_seconds: float = 2.0
var layers: Array[MusicLayer] = []
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## The table at `path`; on a missing or rejected file it has no layers and `error` says why.
static func load_file(path: String = DEFAULT_FILE) -> MusicTable:
	if not FileAccess.file_exists(path):
		var missing: MusicTable = MusicTable.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; see the class comment for the format.
static func parse(text: String) -> MusicTable:
	var table: MusicTable = MusicTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not _is_number(root.get("volume_db")):
		return table._reject("volume_db must be a number")
	table.volume_db = float(root["volume_db"])
	for key: String in ["crossfade_seconds", "meltdown_seconds", "end_fade_seconds"]:
		if not _is_number(root.get(key)) or float(root[key]) <= 0.0:
			return table._reject("%s must be a number above 0" % key)
	table.crossfade_seconds = float(root["crossfade_seconds"])
	table.meltdown_seconds = float(root["meltdown_seconds"])
	table.end_fade_seconds = float(root["end_fade_seconds"])
	if table.meltdown_seconds > MELTDOWN_SECONDS_MAX:
		return table._reject("meltdown_seconds must be at most %.1f" % MELTDOWN_SECONDS_MAX)
	if not root.get("layers") is Array:
		return table._reject("layers must be a list")
	var seen: Dictionary[String, bool] = {}
	for index: int in (root["layers"] as Array).size():
		var layer: MusicLayer = MusicLayer.parse(root["layers"][index])
		if layer == null:
			return table._reject("layers[%d] needs an id, plays (run, meltdown or hub), a res:// sound, 0 <= from_alarm <= 1 and a volume_db" % index)
		if seen.has(layer.id):
			return table._reject("layers[%d]: %s is listed twice" % [index, layer.id])
		seen[layer.id] = true
		table.layers.append(layer)
	if table.layers_playing(MusicLayer.RUN).filter(func(l: MusicLayer) -> bool: return l.from_alarm == 0.0).is_empty():
		return table._reject("layers needs a run layer from alarm 0, the calm layer")
	for plays: String in [MusicLayer.MELTDOWN, MusicLayer.HUB]:
		if table.layers_playing(plays).is_empty():
			return table._reject("layers needs a %s layer" % plays)
	return table


## The layers that play `plays` (`MusicLayer.RUN`, `MELTDOWN` or `HUB`), in file order.
func layers_playing(plays: String) -> Array[MusicLayer]:
	var found: Array[MusicLayer] = []
	for layer: MusicLayer in layers:
		if layer.plays == plays:
			found.append(layer)
	return found


## The layer named `id`, or null.
func layer(id: String) -> MusicLayer:
	for each: MusicLayer in layers:
		if each.id == id:
			return each
	return null


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> MusicTable:
	error = why
	layers = []
	return self
