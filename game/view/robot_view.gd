class_name RobotView
extends Node3D

## Draws the simulation's robots as placeholder shapes, one look per robot type
## (CMB-3). Real art comes later; for now each type gets a primitive shape and
## a glowing colour so the types can be told apart in a dark tunnel.
##
## It only reads the robots it is given and never writes to them, so the view
## cannot change what the authoritative simulation decided (MP-2). Meshes are
## pooled: robots appearing and disappearing reuse hidden nodes instead of
## creating and freeing them every frame.
##
## The look per type lives in `res://view/robot_look.json`, keyed by the robot
## data file's id, so a new robot type needs a new entry there and no code
## (ARC-4).

const NODE_NAME: String = "RobotView"
const MESH_PREFIX: String = "Robot"
const DEFAULT_LOOK_FILE: String = "res://view/robot_look.json"

const SHAPES: Array[String] = ["sphere", "box", "capsule", "prism"]
## Keys of one look entry.
const ENTRY_KEYS: Array[String] = ["shape", "scale", "emission_color"]
## Keys of the file's top level.
const TOP_KEYS: Array[String] = ["default", "robots"]
## Size relative to the robot's collision radius, inclusive.
const SCALE_RANGE: Array[float] = [0.1, 4.0]

## A robot whose position jumped further than this many ticks of its top speed
## (plus `JUMP_MARGIN_M`) is not the same robot as the one at the same index on
## the previous tick: an earlier robot was removed and the array shifted. It is
## drawn where it is rather than sliding across the tunnel.
const JUMP_TICKS: float = 2.0
const JUMP_MARGIN_M: float = 0.1

## Look used for an id the file does not list, and when the file is rejected.
const FALLBACK_LOOK: Dictionary = {"shape": "sphere", "scale": 1.0, "emission_color": Color(0.8, 0.8, 0.8)}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

## Look per robot id: {"shape", "scale", "emission_color"}.
var _looks: Dictionary[String, Dictionary] = {}
var _default_look: Dictionary = FALLBACK_LOOK
## One shared mesh per robot id (and "" for the default), built on first use.
var _meshes: Dictionary[String, PrimitiveMesh] = {}
var _nodes: Array[MeshInstance3D] = []


func _init() -> void:
	name = NODE_NAME
	load_look()


## Parses the text of a look file: `{"default": <entry>, "robots": {<id>:
## <entry>, ...}}`, where an entry is `{"shape": one of SHAPES, "scale":
## number, "emission_color": [r, g, b]}`. Returns `{"default": <look>,
## "robots": {<id>: <look>}}` with the colour as a `Color`, or a dictionary
## holding only `"error"`, which names the field.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not TOP_KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in TOP_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var default_look: Dictionary = _parse_entry("default", data["default"])
	if default_look.has("error"):
		return default_look
	if typeof(data["robots"]) != TYPE_DICTIONARY:
		return _rejected("key \"robots\" must be an object of robot id to look")
	var robots: Dictionary = {}
	var given: Dictionary = data["robots"]
	for id: Variant in given:
		var look: Dictionary = _parse_entry("robots.%s" % str(id), given[id])
		if look.has("error"):
			return look
		robots[str(id)] = look
	return {"default": default_look, "robots": robots}


## Applies the look file at `path`. A missing or rejected file leaves every
## robot with the fallback look, sets `look_error` and pushes a warning naming
## the field. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = parse_look(FileAccess.get_file_as_string(path))
	else:
		values = _rejected("file not found")
	_looks.clear()
	_meshes.clear()
	_default_look = FALLBACK_LOOK
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("RobotView uses the fallback look; %s" % look_error)
	else:
		_default_look = values["default"]
		var robots: Dictionary = values["robots"]
		for id: String in robots:
			_looks[id] = robots[id]
	return look_error


## The look drawn for robot type `id`: its own entry, or the default.
func look_for(id: String) -> Dictionary:
	return _looks.get(id, _default_look)


## Ids the loaded look file lists.
func looked_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_looks.keys())
	return ids


## Draws one mesh per robot in `current`, `alpha` (0..1) of the way from its
## pose in `previous` to its pose in `current`. Both are copies of the
## simulation's ordered robot array on consecutive ticks, so robots are paired
## by index. A robot with no partner (new, or an earlier one was removed and
## the array shifted) is drawn where it is. Never writes to either array (MP-2).
func show_robots(previous: Array[RobotState], current: Array[RobotState], alpha: float) -> void:
	var blend: float = clampf(alpha, 0.0, 1.0)
	while _nodes.size() < current.size():
		_add_node()
	for index: int in current.size():
		var robot: RobotState = current[index]
		var node: MeshInstance3D = _nodes[index]
		if robot == null or robot.def == null:
			node.visible = false
			continue
		var before: RobotState = previous[index] if index < previous.size() else null
		if not is_same_robot(before, robot):
			before = robot
		var look: Dictionary = look_for(robot.def.id)
		var size: float = robot.def.radius * float(look["scale"])
		var from_rotation: Quaternion = before.orientation.orthonormalized().get_rotation_quaternion()
		var to_rotation: Quaternion = robot.orientation.orthonormalized().get_rotation_quaternion()
		var rotation: Quaternion = from_rotation.slerp(to_rotation, blend)
		node.mesh = _mesh_for(robot.def.id)
		node.transform = Transform3D(Basis(rotation).scaled(Vector3.ONE * size),
				before.position.lerp(robot.position, blend))
		node.visible = true
	for index: int in range(current.size(), _nodes.size()):
		_nodes[index].visible = false


## Whether `before` can be the previous tick's copy of `robot`: same type, and
## no further away than it could have moved.
static func is_same_robot(before: RobotState, robot: RobotState) -> bool:
	if before == null or before.def == null or before.def.id != robot.def.id:
		return false
	var reach: float = robot.def.max_speed * ShipState.TICK_DT * JUMP_TICKS + JUMP_MARGIN_M
	return before.position.distance_to(robot.position) <= reach


## Number of mesh nodes in the pool, shown or hidden.
func node_count() -> int:
	return _nodes.size()


## The pooled mesh node at `index`, for tests.
func node(index: int) -> MeshInstance3D:
	return _nodes[index]


## A unit-sized mesh for `shape`: about 1 m from the centre to the surface
## along its widest axes, so the node's scale is the robot's size directly.
static func build_mesh(shape: String) -> PrimitiveMesh:
	match shape:
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(2.0, 2.0, 2.0)
			return box
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = 0.6
			capsule.height = 2.0
			capsule.radial_segments = 12
			capsule.rings = 4
			return capsule
		"prism":
			var prism: PrismMesh = PrismMesh.new()
			prism.size = Vector3(2.0, 2.0, 2.0)
			return prism
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere


func _mesh_for(id: String) -> PrimitiveMesh:
	var key: String = id if _looks.has(id) else ""
	if _meshes.has(key):
		return _meshes[key]
	var look: Dictionary = look_for(id)
	var mesh: PrimitiveMesh = build_mesh(look["shape"])
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var color: Color = look["emission_color"]
	# Shaded, so the shape still reads under the ship's and the bolts' lights,
	# and emissive, so the colour reads in a dark tunnel with no light on it.
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	mesh.material = material
	_meshes[key] = mesh
	return mesh


func _add_node() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s%d" % [MESH_PREFIX, _nodes.size()]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	add_child(instance)
	_nodes.append(instance)


static func _parse_entry(field: String, entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return _rejected("\"%s\" must be an object" % field)
	var data: Dictionary = entry
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not ENTRY_KEYS.has(key):
			return _rejected("\"%s\" has unknown key \"%s\"" % [field, str(key)])
	for key: String in ENTRY_KEYS:
		if not data.has(key):
			return _rejected("\"%s\" is missing key \"%s\"" % [field, key])
	if typeof(data["shape"]) != TYPE_STRING or not SHAPES.has(data["shape"]):
		return _rejected("\"%s.shape\" is %s, must be one of %s" % [field, JSON.stringify(data["shape"]), ", ".join(PackedStringArray(SHAPES))])
	var scale: Variant = data["scale"]
	# A bool must not pass as 0 or 1.
	if typeof(scale) != TYPE_FLOAT and typeof(scale) != TYPE_INT:
		return _rejected("\"%s.scale\" must be a number" % field)
	if float(scale) < SCALE_RANGE[0] or float(scale) > SCALE_RANGE[1]:
		return _rejected("\"%s.scale\" is %s, must be within %s..%s" % [field, scale, SCALE_RANGE[0], SCALE_RANGE[1]])
	var parts: Variant = data["emission_color"]
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return _rejected("\"%s.emission_color\" must be [red, green, blue]" % field)
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return _rejected("\"%s.emission_color\" must hold numbers" % field)
		if float(part) < 0.0 or float(part) > 1.0:
			return _rejected("\"%s.emission_color\" has %s, must be within 0..1" % [field, part])
	return {
		"shape": data["shape"],
		"scale": float(scale),
		"emission_color": Color(float(parts[0]), float(parts[1]), float(parts[2])),
	}


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
