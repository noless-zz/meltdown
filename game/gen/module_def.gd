class_name ModuleDef
extends RefCounted

## A hand-authored mine module: a room, tunnel or shaft made of a few boxes,
## with connectors where another module can join (GEN-1, GEN-5, ARC-4). The
## generator (#294) chains modules at matching connectors. The caller reads
## the file and hands over its text: like `core/`, `gen/` never opens files.
##
## The file is one JSON object:
##
##     {"id": "straight_tunnel",
##      "boxes": [{"min": [-5, -5, -30], "max": [5, 5, 0]}],
##      "connectors": [{"position": [0, 0, 0], "axis": "+z", "size": "small"}, ...]}
##
## Corners and positions are metres in module space, read in whole millimetres
## like `LevelDef` boxes, so a module reads the same on every run (ARC-1).
## `axis` is one of `ModuleConnector.AXES`, `size` one of its `SIZE_CLASSES`.
##
## A module is rejected, with a message naming the problem, when a key is
## unknown or missing, the id is not a valid id, a box's min is not below its
## max, the boxes are not joined into one piece (`LevelDef.joined`), there is
## no connector, or a connector is not on an outer face of a box: the opening
## must lie in the face of some box on the connector's outward side, fit
## inside that face, and not be covered by another box beyond it. A face that
## another box continues past opens into this module itself, so a module
## joined there would overlap it.

const TOP_KEYS: Array[String] = ["id", "boxes", "connectors"]
const BOX_KEYS: Array[String] = ["min", "max"]
const CONNECTOR_KEYS: Array[String] = ["position", "axis", "size"]

## Empty when the text was rejected.
var id: String = ""
## The module's boxes in metres, module space; empty when rejected.
var boxes: Array[BoxBounds] = []
## Empty when rejected.
var connectors: Array[ModuleConnector] = []
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""

# Box corners in millimetres, kept so connector checks are exact.
var _min_mm: Array[Vector3i] = []
var _max_mm: Array[Vector3i] = []


## Parses the text of a module file. On failure `error` is set and the module
## is empty, so nothing half-read reaches the generator.
static func parse_json(text: String) -> ModuleDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	var problem: String = LevelDef._check_keys(data, TOP_KEYS)
	if problem != "":
		return _failed(problem)
	var module: ModuleDef = ModuleDef.new()
	problem = module._read_id(data["id"])
	if problem == "":
		problem = module._read_boxes(data["boxes"])
	if problem == "":
		problem = module._check_joined()
	if problem == "":
		problem = module._read_connectors(data["connectors"])
	if problem != "":
		return _failed(problem)
	return module


## The module's boxes as one union, for flying and drawing.
func union() -> BoxUnion:
	return BoxUnion.new(boxes.duplicate())


func _read_id(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"id\" must be a string"
	var problem: String = ShipLoadout.check_id("id", value)
	if problem != "":
		return problem
	id = value
	return ""


func _read_boxes(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "key \"boxes\" must be a non-empty list"
	var entries: Array = value
	for index: int in entries.size():
		var what: String = "box %d" % index
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return "%s: must be a JSON object" % what
		var entry: Dictionary = entries[index]
		var problem: String = LevelDef._check_keys(entry, BOX_KEYS)
		var read: Array[Vector3i] = []
		if problem == "":
			problem = RobotSpawn.read_mm(entry["min"], "min", read)
		if problem == "":
			problem = RobotSpawn.read_mm(entry["max"], "max", read)
		if problem != "":
			return "%s: %s" % [what, problem]
		for axis: int in 3:
			if read[0][axis] >= read[1][axis]:
				return "%s: min must be below max on every axis" % what
		_min_mm.append(read[0])
		_max_mm.append(read[1])
		var scale: float = float(RobotSpawn.SCALE)
		boxes.append(BoxBounds.new(Vector3(read[0]) / scale, Vector3(read[1]) / scale))
	return ""


## Every box reachable from box 0 through joined boxes, the `LevelDef` rule.
func _check_joined() -> String:
	var reached: Array[bool] = []
	reached.resize(boxes.size())
	reached.fill(false)
	reached[0] = true
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for other: int in boxes.size():
			if not reached[other] and LevelDef.joined(boxes[index], boxes[other]):
				reached[other] = true
				queue.append(other)
	for index: int in reached.size():
		if not reached[index]:
			return "box %d: not joined to box 0" % index
	return ""


func _read_connectors(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "key \"connectors\" must be a non-empty list"
	var entries: Array = value
	for index: int in entries.size():
		var what: String = "connector %d" % index
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return "%s: must be a JSON object" % what
		var problem: String = _read_connector(entries[index])
		if problem != "":
			return "%s: %s" % [what, problem]
	return ""


func _read_connector(entry: Dictionary) -> String:
	var problem: String = LevelDef._check_keys(entry, CONNECTOR_KEYS)
	if problem != "":
		return problem
	var read: Array[Vector3i] = []
	problem = RobotSpawn.read_mm(entry["position"], "position", read)
	if problem != "":
		return problem
	if typeof(entry["axis"]) != TYPE_STRING or not ModuleConnector.AXES.has(entry["axis"]):
		return "axis must be one of %s" % ", ".join(ModuleConnector.AXES.keys())
	if typeof(entry["size"]) != TYPE_STRING or not ModuleConnector.SIZE_CLASSES.has(entry["size"]):
		return "size must be one of %s" % ", ".join(ModuleConnector.SIZE_CLASSES.keys())
	var connector: ModuleConnector = ModuleConnector.new(read[0], entry["axis"], entry["size"])
	problem = _check_on_outer_face(connector)
	if problem != "":
		return problem
	connectors.append(connector)
	return ""


func _check_on_outer_face(connector: ModuleConnector) -> String:
	var axis: int = connector.axis()
	var at: Vector3i = connector.position_mm
	var half: int = connector.size_mm() / 2
	var in_plane: int = -1
	var face: int = -1
	for index: int in boxes.size():
		var plane: int = _max_mm[index][axis] if connector.axis_sign() > 0 else _min_mm[index][axis]
		if plane != at[axis]:
			continue
		if in_plane < 0:
			in_plane = index
		if _opening_fits(index, connector, half):
			face = index
			break
	if in_plane < 0:
		return "not on the %s face of any box" % connector.axis_name
	if face < 0:
		return "opening (%s) does not fit inside the %s face of box %d" \
				% [connector.size_class, connector.axis_name, in_plane]
	for index: int in boxes.size():
		if _covers(index, connector, half):
			return "opening is covered by box %d, so the %s face of box %d is not an outer face" \
					% [index, connector.axis_name, face]
	return ""


## True if the square opening lies within box `index` on the two axes across
## the connector's axis.
func _opening_fits(index: int, connector: ModuleConnector, half: int) -> bool:
	for other: int in 3:
		if other == connector.axis():
			continue
		var centre: int = connector.position_mm[other]
		if centre - half < _min_mm[index][other] or centre + half > _max_mm[index][other]:
			return false
	return true


## True if box `index` reaches past the opening's plane on the outward side and
## overlaps the opening with some area, so the opening leads into the module.
func _covers(index: int, connector: ModuleConnector, half: int) -> bool:
	var axis: int = connector.axis()
	var plane: int = connector.position_mm[axis]
	if connector.axis_sign() > 0:
		if not (_min_mm[index][axis] <= plane and plane < _max_mm[index][axis]):
			return false
	elif not (_min_mm[index][axis] < plane and plane <= _max_mm[index][axis]):
		return false
	for other: int in 3:
		if other == axis:
			continue
		var centre: int = connector.position_mm[other]
		if _min_mm[index][other] >= centre + half or _max_mm[index][other] <= centre - half:
			return false
	return true


static func _failed(message: String) -> ModuleDef:
	var module: ModuleDef = ModuleDef.new()
	module.error = message
	return module
