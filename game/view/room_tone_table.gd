class_name RoomToneTable
extends RefCounted

## The room tone table (#1399, AUD-1, ARC-4), read from
## `res://data/audio/room_tones.json`:
##
##     {
##       "fade_seconds": 1.0,          # how long a change of tone takes to crossfade
##       "spaces": [                   # by rising from_span_m; the first starts at 0
##         {"id": "tunnel", "from_span_m": 0.0, "sound": "res://...", "volume_db": -38.0}, ...
##       ],
##       "reactor": {"sound": "res://...", "volume_db": -36.0, "near_m": 30.0, "full_m": 10.0},
##       "meltdown": {"sound": "res://...", "volume_db": -33.0},
##       "hangar": {"sound": "res://...", "volume_db": -38.0}
##     }
##
## No module names a tone: as the reverb does (#1291), the tone comes from
## the span of the box the ship is in (`RoomReverbTable.span_of`), so a new
## module or a hand-built level gets its tone without a row of its own. The
## reactor's pulse rises from nothing at `near_m` from the reactor to full at
## `full_m`. Every key is required; a rejected file names the field in
## `error`, and the tones then stay silent rather than play guessed levels.

const DEFAULT_FILE: String = "res://data/audio/room_tones.json"
const REACTOR: String = "reactor"
const MELTDOWN: String = "meltdown"
const HANGAR: String = "hangar"
const SINGLE_LAYERS: Array[String] = [REACTOR, MELTDOWN, HANGAR]

var fade_seconds: float = 1.0
## Space tone ids, by rising span.
var space_ids: Array[String] = []
var space_spans: Array[float] = []
## Every layer's sound and level, by id: the spaces, the reactor, the meltdown and the hangar.
var sounds: Dictionary[String, String] = {}
var volumes: Dictionary[String, float] = {}
var reactor_near_m: float = 30.0
var reactor_full_m: float = 10.0
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## The table at `path`; on a missing or rejected file `error` says why.
static func load_file(path: String = DEFAULT_FILE) -> RoomToneTable:
	if not FileAccess.file_exists(path):
		return RoomToneTable.new()._reject("%s: no such file" % path)
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; see the class comment for the format.
static func parse(text: String) -> RoomToneTable:
	var table: RoomToneTable = RoomToneTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not _is_number(root.get("fade_seconds")) or float(root["fade_seconds"]) <= 0.0:
		return table._reject("fade_seconds must be a number above 0")
	table.fade_seconds = float(root["fade_seconds"])
	if not root.get("spaces") is Array or (root["spaces"] as Array).is_empty():
		return table._reject("spaces must be a list of at least one space")
	var spaces: Array = root["spaces"]
	for index: int in spaces.size():
		var why: String = table._read_space(spaces[index], index)
		if why != "":
			return table._reject(why)
	for layer: String in SINGLE_LAYERS:
		var why: String = table._read_layer(root.get(layer), layer, layer)
		if why != "":
			return table._reject(why)
	var reactor: Dictionary = root[REACTOR]
	for key: String in ["near_m", "full_m"]:
		if not _is_number(reactor.get(key)) or float(reactor[key]) < 0.0:
			return table._reject("reactor.%s must be a number of at least 0" % key)
	table.reactor_near_m = float(reactor["near_m"])
	table.reactor_full_m = float(reactor["full_m"])
	if table.reactor_full_m >= table.reactor_near_m:
		return table._reject("reactor.full_m must be below reactor.near_m")
	return table


## The space tone for a box `span` metres across: the last space starting at or below it.
func space_for_span(span: float) -> String:
	var found: String = ""
	for index: int in space_ids.size():
		if span >= space_spans[index]:
			found = space_ids[index]
	return found


## The space tone heard at `point` in `walls`, from the box whose sound is
## heard there (`RoomReverbTable.room_box`), or empty where no box holds it.
func space_at(walls: BoxUnion, point: Vector3) -> String:
	var box: BoxBounds = RoomReverbTable.room_box(walls, point)
	return space_for_span(RoomReverbTable.span_of(box)) if box != null else ""


## The reactor pulse's share, 0..1, at `distance` metres from the reactor.
func reactor_share(distance: float) -> float:
	if error != "":
		return 0.0
	return clampf((reactor_near_m - distance) / (reactor_near_m - reactor_full_m), 0.0, 1.0)


## Every layer id: the spaces by rising span, then the reactor, meltdown and hangar.
func layer_ids() -> Array[String]:
	var ids: Array[String] = space_ids.duplicate()
	if error == "":
		ids.append_array(SINGLE_LAYERS)
	return ids


## The loudest any one layer plays, dB; the space under it and the reactor
## pulse together are at most 3 dB more.
func loudest_db() -> float:
	var loudest: float = -INF
	for id: String in volumes:
		loudest = maxf(loudest, volumes[id])
	return loudest


func _read_space(value: Variant, index: int) -> String:
	var field: String = "spaces[%d]" % index
	if not value is Dictionary:
		return "%s must be an object" % field
	var row: Dictionary = value
	if not row.get("id") is String or (row["id"] as String) == "":
		return "%s.id must be a name" % field
	var id: String = row["id"]
	if volumes.has(id) or SINGLE_LAYERS.has(id):
		return "%s.id %s is already used" % [field, id]
	if not _is_number(row.get("from_span_m")):
		return "%s.from_span_m must be a number" % field
	var span: float = float(row["from_span_m"])
	if index == 0 and span != 0.0:
		return "%s.from_span_m must be 0 for the first space" % field
	if index > 0 and span <= space_spans[-1]:
		return "%s.from_span_m must be above the space before it" % field
	var why: String = _read_layer(row, id, field)
	if why != "":
		return why
	space_ids.append(id)
	space_spans.append(span)
	return ""


func _read_layer(value: Variant, id: String, field: String) -> String:
	if not value is Dictionary:
		return "%s must be an object" % field
	var row: Dictionary = value
	if not row.get("sound") is String or not (row["sound"] as String).begins_with("res://"):
		return "%s.sound must be a res:// path" % field
	if not _is_number(row.get("volume_db")) or float(row["volume_db"]) > 0.0:
		return "%s.volume_db must be a number of at most 0" % field
	sounds[id] = row["sound"]
	volumes[id] = float(row["volume_db"])
	return ""


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> RoomToneTable:
	error = why
	space_ids = []
	space_spans = []
	sounds = {}
	volumes = {}
	return self
