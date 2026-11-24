class_name RoomReverbTable
extends RefCounted

## The room reverb table (#1291, AUD-1, ARC-4), read from
## `res://data/audio/reverb.json`:
##
##     {
##       "blend_seconds": 0.8,      # how long a change of room takes to blend in
##       "points": [{"span_m": 8, "room_size": 0.15, "damping": 0.7, "wet": 0.12}, ...]
##     }
##
## No module names a reverb: every room, tunnel and shaft is a box, and the
## reverb comes from the box's span (`span_of`), read off the points by
## straight lines between them and held flat past the first and last. So a new
## module file, or a hand-built level, gets its reverb without a row of its
## own. Points are listed by rising `span_m`; each value is 0..1.

const DEFAULT_FILE: String = "res://data/audio/reverb.json"
const POINT_KEYS: Array[String] = ["span_m", "room_size", "damping", "wet"]

var blend_seconds: float = 0.8
## By rising span.
var spans: Array[float] = []
var settings: Array[ReverbSetting] = []
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## The table at `path`; on a missing or rejected file it has no points and `error` says why.
static func load_file(path: String = DEFAULT_FILE) -> RoomReverbTable:
	if not FileAccess.file_exists(path):
		return RoomReverbTable.new()._reject("%s: no such file" % path)
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; see the class comment for the format.
static func parse(text: String) -> RoomReverbTable:
	var table: RoomReverbTable = RoomReverbTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not _is_number(root.get("blend_seconds")) or float(root["blend_seconds"]) < 0.0:
		return table._reject("blend_seconds must be a number of at least 0")
	table.blend_seconds = float(root["blend_seconds"])
	if not root.get("points") is Array or (root["points"] as Array).is_empty():
		return table._reject("points must be a list of at least one point")
	var points: Array = root["points"]
	for index: int in points.size():
		var point: Variant = points[index]
		if not point is Dictionary:
			return table._reject("points[%d] must be an object" % index)
		for key: String in POINT_KEYS:
			if not _is_number((point as Dictionary).get(key)):
				return table._reject("points[%d].%s must be a number" % [index, key])
		var row: Dictionary = point
		var span: float = float(row["span_m"])
		if not table.spans.is_empty() and span <= table.spans[-1]:
			return table._reject("points[%d].span_m must be above the point before it" % index)
		for key: String in ["room_size", "damping", "wet"]:
			if float(row[key]) < 0.0 or float(row[key]) > 1.0:
				return table._reject("points[%d].%s must be 0..1" % [index, key])
		table.spans.append(span)
		table.settings.append(ReverbSetting.new(float(row["room_size"]), float(row["damping"]),
			float(row["wet"])))
	return table


## The setting for a space `span` metres across.
func setting_for_span(span: float) -> ReverbSetting:
	if settings.is_empty():
		return ReverbSetting.new()
	if span <= spans[0]:
		return settings[0]
	for index: int in range(1, spans.size()):
		if span <= spans[index]:
			var weight: float = (span - spans[index - 1]) / (spans[index] - spans[index - 1])
			return settings[index - 1].lerp_to(settings[index], weight)
	return settings[-1]


## The setting heard at `point` in `walls`, or null where no box holds the
## point (inside rock, which the ship never is; the caller keeps what it had).
func setting_at(walls: BoxUnion, point: Vector3) -> ReverbSetting:
	var box: BoxBounds = room_box(walls, point)
	return setting_for_span(span_of(box)) if box != null else null


## The box whose sound is heard at `point`: of the boxes holding it, the one
## with the widest span, ties to the lower index. Where a tunnel reaches into a
## room the room is heard, so the change comes at the room's wall, the same
## place whichever way the ship flies.
static func room_box(walls: BoxUnion, point: Vector3) -> BoxBounds:
	var best: BoxBounds = null
	var best_span: float = -1.0
	if walls == null:
		return null
	for box: BoxBounds in walls.boxes:
		if box.holds(point, 0.0):
			var span: float = span_of(box)
			if span > best_span:
				best_span = span
				best = box
	return best


## How wide a box sounds, metres: the geometric mean of its two shorter sides.
## The longest side is left out because a long tunnel is still a narrow one; its
## echo comes back from the near walls.
static func span_of(box: BoxBounds) -> float:
	var size: Vector3 = (box.max_corner - box.min_corner).abs()
	var sides: Array[float] = [size.x, size.y, size.z]
	sides.sort()
	return sqrt(sides[0] * sides[1])


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> RoomReverbTable:
	error = why
	spans = []
	settings = []
	return self
