class_name MinerLabel
extends Node3D

## A short label over a trapped miner the first time it comes into sight in a
## run (SLV-3, PLT-2, #1220): in the owner's playtest (#1208) a pilot met a
## miner and did not know what it was or what to do with it. The beacon alone
## says "something is here"; the label says what and how, once, and then gets
## out of the way.
##
## A miner is in sight when the ship is within `sight_distance_m` of it and a
## straight line between them stays in open space (`LineOfSight`, the rule
## robots see by). Its label then shows for `show_seconds`, `height_above_m`
## over the miner, turned to face the head. It never shows again for that
## miner in the run, and goes at once if the miner is rescued, since it then
## leaves `MinerRescue.trapped`.
##
## Presentation only: it reads the rescue state, the walls and the ship and
## never writes them (ARC-3, MP-2). Miners are known by their position, which
## is fixed for the run; a new rescue state is a new run, and forgets what
## was seen. The text and timing live in `res://view/miner_label_look.json`
## (ARC-4).

const NODE_NAME: String = "MinerLabel"
const DEFAULT_LOOK_FILE: String = "res://view/miner_label_look.json"
## Inclusive ranges of the number keys.
const RANGES: Dictionary = {
	"sight_distance_m": [2.0, 100.0],
	"show_seconds": [1.0, 30.0],
	"height_above_m": [0.0, 3.0],
	"font_size": [16.0, 256.0],
	"pixel_size": [0.0005, 0.02],
}
## Longer text would not fit a tunnel's width at a readable size.
const TEXT_MAX: int = 60
## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK_LOOK: Dictionary = {
	"text": "Trapped miner: hold near to rescue",
	"sight_distance_m": 25.0,
	"show_seconds": 6.0,
	"height_above_m": 1.6,
	"font_size": 96.0,
	"pixel_size": 0.0035,
	"color": Color(0.85, 1.0, 0.9),
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
## The rescue state the seen miners belong to; another one is another run.
var _rescue: MinerRescue = null
## Miners whose label has shown this run, by position: miner -> true.
var _seen: Dictionary = {}
## Seconds left for each label showing now, by miner.
var _left: Dictionary = {}
## The pooled labels, by miner.
var _labels: Dictionary = {}


func _init() -> void:
	name = NODE_NAME
	load_look()


## Parses the text of a look file: `{"text", "sight_distance_m",
## "show_seconds", "height_above_m", "font_size", "pixel_size", "color"}`, the
## colour as [r, g, b] within 0..1. Returns the look, or a dictionary holding
## only `"error"`, which names the key.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not FALLBACK_LOOK.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	for key: String in FALLBACK_LOOK:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
	var look: Dictionary = {}
	var label_text: Variant = data["text"]
	if typeof(label_text) != TYPE_STRING or (label_text as String).strip_edges() == "" \
			or (label_text as String).length() > TEXT_MAX:
		return {"error": "\"text\" must be a text of 1..%d characters" % TEXT_MAX}
	look["text"] = label_text
	var color: Variant = MinerLook.parse_color("color", data["color"])
	if typeof(color) == TYPE_STRING:
		return {"error": color}
	look["color"] = color
	for key: String in RANGES:
		var problem: String = MinerLook.check_number(key, data[key], RANGES[key])
		if problem != "":
			return {"error": problem}
		look[key] = float(data[key])
	return look


## Applies the look file at `path`. A missing or rejected file keeps the
## fallback look, sets `look_error` and pushes a warning. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var look: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		look = parse_look(FileAccess.get_file_as_string(path))
	_look = FALLBACK_LOOK
	look_error = ""
	if look.has("error"):
		look_error = "%s: %s" % [path, look["error"]]
		push_warning("MinerLabel uses the fallback look; %s" % look_error)
	else:
		_look = look
	for label: Label3D in _labels.values():
		label.free()
	_labels.clear()
	return look_error


## The look in use.
func look() -> Dictionary:
	return _look


## Shows the labels for this frame: starts one for every trapped miner first in
## sight from `ship` through `walls` (null walls are open space), counts
## `delta` seconds off those showing, and hides those whose time is up or whose
## miner was rescued. Nothing shows while rescue is off or without a ship.
func show_labels(rescue: MinerRescue, ship: ShipState, walls: BoxUnion, delta: float) -> void:
	if rescue != _rescue:
		_rescue = rescue
		_seen.clear()
		_left.clear()
	var trapped: Array[Vector3i] = rescue.trapped if rescue != null else ([] as Array[Vector3i])
	for miner: Variant in _left.keys():
		_left[miner] = float(_left[miner]) - delta
		if float(_left[miner]) <= 0.0 or not trapped.has(miner):
			_left.erase(miner)
	if ship != null:
		for miner: Vector3i in trapped:
			if not _seen.has(miner) and in_sight(miner, ship.position, walls):
				_seen[miner] = true
				_left[miner] = float(_look["show_seconds"])
	for miner: Variant in _labels:
		(_labels[miner] as Label3D).visible = false
	for miner: Variant in _left:
		_label_for(miner).visible = true


## Whether `miner` is in sight from `eye`: near enough, and a clear line.
func in_sight(miner: Vector3i, eye: Vector3, walls: BoxUnion) -> bool:
	var at: Vector3 = MinerRescue.position_of(miner)
	if eye.distance_to(at) > float(_look["sight_distance_m"]):
		return false
	return LineOfSight.clear(walls, eye, at)


## Labels showing now.
func shown_count() -> int:
	return _left.size()


## Whether `miner`'s label shows now.
func showing(miner: Vector3i) -> bool:
	return _left.has(miner)


## The pooled label of `miner`, null if it never showed; for tests.
func label_of(miner: Vector3i) -> Label3D:
	return _labels.get(miner, null)


func _label_for(miner: Vector3i) -> Label3D:
	if _labels.has(miner):
		return _labels[miner]
	var label: Label3D = Label3D.new()
	label.name = "Label%d" % _labels.size()
	label.text = _look["text"]
	label.font_size = int(_look["font_size"])
	label.pixel_size = _look["pixel_size"]
	label.modulate = _look["color"]
	label.outline_size = maxi(4, int(_look["font_size"]) / 8)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# Turned to the head every frame, so it reads from any side of the miner
	# and at every comfort preset (the label sits by the beacon, which the
	# pilot is looking at when it first comes into sight).
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.double_sided = true
	label.position = MinerRescue.position_of(miner) + Vector3.UP * float(_look["height_above_m"])
	add_child(label)
	_labels[miner] = label
	return label
