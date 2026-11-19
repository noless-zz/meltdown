extends RefCounted

## Mine room modules as data (#293, GEN-1, GEN-5, ARC-4, ARC-1): every shipped
## module parses, its connectors sit on outer box faces and point out of the
## module (checked here by sampling points, apart from `ModuleDef`'s own
## integer checks), and each kind of bad module is rejected, naming the
## problem and keeping nothing.

const MODULES_DIR: String = "res://data/modules/"
const WARDEN_FILE: String = "res://data/robots/warden.json"
const STARTER_IDS: Array[String] = [
	"corner_90", "room_four_way", "straight_tunnel", "t_junction", "vertical_shaft",
]
## Modules meant to end a branch, with a single connector (#395).
const DEAD_END_IDS: Array[String] = ["dead_end_alcove"]
## How far the sample points sit off a face and in from an opening's edges.
const STEP_M: float = 0.01


func _shipped() -> Array[ModuleDef]:
	var modules: Array[ModuleDef] = []
	var files: PackedStringArray = DirAccess.get_files_at(MODULES_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".json"):
			modules.append(ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + file)))
	return modules


func _inside_any(module: ModuleDef, point: Vector3) -> bool:
	for box: BoxBounds in module.boxes:
		var inside: bool = true
		for axis: int in 3:
			if point[axis] <= box.min_corner[axis] or point[axis] >= box.max_corner[axis]:
				inside = false
		if inside:
			return true
	return false


## The opening's centre and its four corners pulled in by `STEP_M`, metres.
func _opening_points(connector: ModuleConnector) -> Array[Vector3]:
	var half: float = connector.size_mm() / 2000.0 - STEP_M
	var across: Array[int] = []
	for axis: int in 3:
		if axis != connector.axis():
			across.append(axis)
	var points: Array[Vector3] = [connector.position()]
	for a: float in [-half, half]:
		for b: float in [-half, half]:
			var point: Vector3 = connector.position()
			point[across[0]] += a
			point[across[1]] += b
			points.append(point)
	return points


## A module text: the straight tunnel, with `changes` merged over its top level.
func _text(changes: Dictionary) -> String:
	var data: Dictionary = {
		"id": "probe",
		"boxes": [{"min": [-5, -5, -30], "max": [5, 5, 0]}],
		"connectors": [
			{"position": [0, 0, 0], "axis": "+z", "size": "small"},
			{"position": [0, 0, -30], "axis": "-z", "size": "small"},
		],
	}
	data.merge(changes, true)
	return JSON.stringify(data)


func test_every_shipped_module_parses() -> String:
	var ids: Array[String] = []
	for module: ModuleDef in _shipped():
		if module.error != "":
			return "a shipped module is rejected: %s" % module.error
		ids.append(module.id)
		if not FileAccess.file_exists(MODULES_DIR + module.id + ".json"):
			return "module \"%s\" is not in a file named after its id" % module.id
	ids.sort()
	for id: String in STARTER_IDS:
		if not ids.has(id):
			return "starter module \"%s\" is missing; found %s" % [id, ids]
	return ""


func test_starter_connectors_are_on_faces_and_point_outward() -> String:
	for module: ModuleDef in _shipped():
		var needed: int = 1 if DEAD_END_IDS.has(module.id) else 2
		if module.connectors.size() < needed:
			return "%s: a module needs at least two connectors to chain, has %d" \
					% [module.id, module.connectors.size()]
		if DEAD_END_IDS.has(module.id) and module.connectors.size() != 1:
			return "%s: a dead end has one connector, has %d" % [module.id, module.connectors.size()]
		for index: int in module.connectors.size():
			var connector: ModuleConnector = module.connectors[index]
			for point: Vector3 in _opening_points(connector):
				if not _inside_any(module, point - connector.outward() * STEP_M):
					return "%s connector %d: %s just inside the face is rock" % [module.id, index, point]
				if _inside_any(module, point + connector.outward() * STEP_M):
					return "%s connector %d: %s just outside the face is still in the module" \
							% [module.id, index, point]
	return ""


func test_the_room_has_a_connector_on_each_of_four_sides() -> String:
	var room: ModuleDef = ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + "room_four_way.json"))
	var axes: Array[String] = []
	for connector: ModuleConnector in room.connectors:
		if not axes.has(connector.axis_name):
			axes.append(connector.axis_name)
	return "" if axes.size() >= 4 else "room connectors face only %s" % [axes]


func test_every_size_class_fits_the_warden() -> String:
	var warden: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(WARDEN_FILE))
	for size_class: String in ModuleConnector.SIZE_CLASSES:
		var side_m: float = ModuleConnector.SIZE_CLASSES[size_class] / 1000.0
		if side_m < 8.0:
			return "size class %s is %s m, below 8 m" % [size_class, side_m]
		if side_m < 2.0 * (warden.radius + LevelDef.CLEARANCE_M):
			return "size class %s (%s m) is too narrow for the warden" % [size_class, side_m]
	return ""


func test_positions_are_read_in_millimetres() -> String:
	var module: ModuleDef = ModuleDef.parse_json(_text({"connectors": [
		{"position": [0.0004, -0.0006, 0], "axis": "+z", "size": "small"},
	]}))
	if module.error != "":
		return "rejected: %s" % module.error
	var at: Vector3i = module.connectors[0].position_mm
	return "" if at == Vector3i(0, -1, 0) else "position read as %s mm" % at


func test_rejections_name_the_problem_and_keep_nothing() -> String:
	var tunnel: Dictionary = {"min": [-5, -5, -30], "max": [5, 5, 0]}
	var cases: Array[Array] = [
		[_text({}), ""],
		["[1, 2]", "top level must be a JSON object"],
		[_text({"music": 1}), "unknown key \"music\""],
		[JSON.stringify({"id": "probe", "boxes": [tunnel]}), "missing key \"connectors\""],
		[_text({"id": "Big Room"}), "\"id\" is \"Big Room\", must use only a-z, 0-9 and _"],
		[_text({"boxes": [{"min": [-5, -5, -30], "max": [5, 5, 0], "door": 1}]}),
			"box 0: unknown key \"door\""],
		[_text({"boxes": [tunnel, {"min": [0, 0, -40], "max": [3, 0, -20]}]}),
			"box 1: min must be below max on every axis"],
		# Overlaps the tunnel by only 1 m across x: touching, not joined.
		[_text({"boxes": [tunnel, {"min": [4, -5, -20], "max": [20, 5, -10]}]}),
			"box 1: not joined to box 0"],
		[_text({"connectors": []}), "key \"connectors\" must be a non-empty list"],
		[_text({"connectors": [{"position": [0, 0, 0], "axis": "+z"}]}),
			"connector 0: missing key \"size\""],
		[_text({"connectors": [{"position": [0, 0, 0], "axis": "up", "size": "small"}]}),
			"connector 0: axis must be one of +x, -x, +y, -y, +z, -z"],
		[_text({"connectors": [{"position": [0, 0, 0], "axis": "+z", "size": "huge"}]}),
			"connector 0: size must be one of small, large"],
		# Mid-tunnel: no box face at z = -10.
		[_text({"connectors": [{"position": [0, 0, -10], "axis": "+z", "size": "small"}]}),
			"connector 0: not on the +z face of any box"],
		# The +z face is at z = 0, but this says the opening faces -z there.
		[_text({"connectors": [{"position": [0, 0, 0], "axis": "-z", "size": "small"}]}),
			"connector 0: not on the -z face of any box"],
		# A 12 m opening in a 10 m face.
		[_text({"connectors": [{"position": [0, 0, 0], "axis": "+z", "size": "large"}]}),
			"connector 0: opening (large) does not fit inside the +z face of box 0"],
		# Off-centre: the 8 m opening pokes 2 m past the face's side.
		[_text({"connectors": [{"position": [3, 0, 0], "axis": "+z", "size": "small"}]}),
			"connector 0: opening (small) does not fit inside the +z face of box 0"],
		# A second box carries on past the first box's +z face.
		[_text({"boxes": [tunnel, {"min": [-5, -5, -10], "max": [5, 5, 20]}],
				"connectors": [{"position": [0, 0, 0], "axis": "+z", "size": "small"}]}),
			"connector 0: opening is covered by box 1, so the +z face of box 0 is not an outer face"],
	]
	for c: Array in cases:
		var module: ModuleDef = ModuleDef.parse_json(c[0])
		if module.error != c[1]:
			return "%s gave \"%s\", expected \"%s\"" % [c[0], module.error, c[1]]
		if c[1] != "" and (module.id != "" or not module.boxes.is_empty() or not module.connectors.is_empty()):
			return "the rejected %s kept something" % c[0]
	return ""


func test_the_union_holds_the_module_boxes() -> String:
	var module: ModuleDef = ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + "t_junction.json"))
	var union: BoxUnion = module.union()
	if union.boxes.size() != module.boxes.size():
		return "union has %d boxes, module %d" % [union.boxes.size(), module.boxes.size()]
	if not union.holds(Vector3(0, 0, -20), 2.0) or union.holds(Vector3(0, 0, 10), 0.5):
		return "union does not match the T-junction's shape"
	return ""
