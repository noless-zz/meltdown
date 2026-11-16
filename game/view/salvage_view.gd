class_name SalvageView
extends Node3D

## Draws the parts floating in the mine (SLV-1), so the player can see what a
## destroyed robot dropped. Placeholder shapes like `RobotView`, but in shapes
## no robot uses (rings and rods) and brighter, so a part reads in a dark
## tunnel (LGT-1) and is never mistaken for a robot.
##
## It only reads the items it is given and never writes to them (MP-2). The
## slow spin is the view's own clock and is never written back. Meshes are
## pooled, as in `RobotView`.
##
## The look per part lives in `res://view/salvage_look.json`, keyed by the
## part's data file id, so a new part needs a new entry there and no code
## (ARC-4).

const NODE_NAME: String = "SalvageView"
const MESH_PREFIX: String = "Salvage"
const DEFAULT_LOOK_FILE: String = "res://view/salvage_look.json"

const SHAPES: Array[String] = ["sphere", "box", "capsule", "prism", "cylinder", "torus"]
## Keys of one look entry.
const ENTRY_KEYS: Array[String] = ["shape", "scale", "emission_color"]
## Keys of the file's top level.
const TOP_KEYS: Array[String] = ["default", "parts"]
## Size relative to `SalvageItem.RADIUS`, inclusive.
const SCALE_RANGE: Array[float] = [0.25, 4.0]

## Slow enough to read as floating, fast enough to catch the eye.
const SPIN_RADIANS_PER_SECOND: float = 1.2
## Tilt of the spin axis off vertical, so a ring shows its hole while turning.
const TILT_RADIANS: float = 0.5
## Brighter than robots, so a part stands out as a pickup.
const EMISSION_ENERGY: float = 2.0

## As in `RobotView`: an item further from its partner than it could have
## moved in this many ticks (plus the margin) is a different item; an earlier
## one was picked up and the array shifted.
const JUMP_TICKS: float = 2.0
const JUMP_MARGIN_M: float = 0.1

## Look used for an id the file does not list, and when the file is rejected.
const FALLBACK_LOOK: Dictionary = {"shape": "torus", "scale": 1.0, "emission_color": Color(0.9, 0.9, 0.9)}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Current spin about the tilted axis, in radians. View state only.
var spin_angle: float = 0.0

var _looks: Dictionary[String, Dictionary] = {}
var _default_look: Dictionary = FALLBACK_LOOK
## One shared mesh per part id (and "" for the default), built on first use.
var _meshes: Dictionary[String, PrimitiveMesh] = {}
var _nodes: Array[MeshInstance3D] = []


func _init() -> void:
	name = NODE_NAME
	load_look()


func _process(delta: float) -> void:
	advance_spin(delta)


## Turns the spin on by `seconds` of view time, wrapped to one turn.
func advance_spin(seconds: float) -> void:
	spin_angle = fposmod(spin_angle + SPIN_RADIANS_PER_SECOND * seconds, TAU)


## Parses the text of a look file: `{"default": <entry>, "parts": {<id>:
## <entry>, ...}}`, where an entry is `{"shape": one of SHAPES, "scale":
## number, "emission_color": [r, g, b]}`. Returns `{"default": <look>,
## "parts": {<id>: <look>}}` with the colour as a `Color`, or a dictionary
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
	if typeof(data["parts"]) != TYPE_DICTIONARY:
		return _rejected("key \"parts\" must be an object of part id to look")
	var parts: Dictionary = {}
	var given: Dictionary = data["parts"]
	for id: Variant in given:
		var look: Dictionary = _parse_entry("parts.%s" % str(id), given[id])
		if look.has("error"):
			return look
		parts[str(id)] = look
	return {"default": default_look, "parts": parts}


## Applies the look file at `path`. A missing or rejected file leaves every
## part with the fallback look, sets `look_error` and pushes a warning naming
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
		push_warning("SalvageView uses the fallback look; %s" % look_error)
	else:
		_default_look = values["default"]
		var parts: Dictionary = values["parts"]
		for id: String in parts:
			_looks[id] = parts[id]
	return look_error


## The look drawn for part `id`: its own entry, or the default.
func look_for(id: String) -> Dictionary:
	return _looks.get(id, _default_look)


## Ids the loaded look file lists.
func looked_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_looks.keys())
	return ids


## Draws one mesh per item in `current`, `alpha` (0..1) of the way from its
## position in `previous` to its position in `current`. Both are copies of
## `Sim.salvage` on consecutive ticks, paired by index; an item with no
## partner is drawn where it is. Never writes to either array (MP-2).
func show_salvage(previous: Array[SalvageItem], current: Array[SalvageItem], alpha: float) -> void:
	var blend: float = clampf(alpha, 0.0, 1.0)
	var spin: Basis = Basis(Vector3.RIGHT, TILT_RADIANS) * Basis(Vector3.UP, spin_angle)
	while _nodes.size() < current.size():
		_add_node()
	for index: int in current.size():
		var item: SalvageItem = current[index]
		var node: MeshInstance3D = _nodes[index]
		if item == null:
			node.visible = false
			continue
		var before: SalvageItem = previous[index] if index < previous.size() else null
		if not is_same_item(before, item):
			before = item
		var size: float = SalvageItem.RADIUS * float(look_for(item.part_id)["scale"])
		node.mesh = _mesh_for(item.part_id)
		node.transform = Transform3D(spin.scaled(Vector3.ONE * size),
				before.position.lerp(item.position, blend))
		node.visible = true
	for index: int in range(current.size(), _nodes.size()):
		_nodes[index].visible = false


## Whether `before` can be the previous tick's copy of `item`: same part, and
## no further away than either copy's speed could carry it.
static func is_same_item(before: SalvageItem, item: SalvageItem) -> bool:
	if before == null or before.part_id != item.part_id:
		return false
	var speed: float = maxf(before.velocity.length(), item.velocity.length())
	var reach: float = speed * ShipState.TICK_DT * JUMP_TICKS + JUMP_MARGIN_M
	return before.position.distance_to(item.position) <= reach


## Number of mesh nodes in the pool, shown or hidden.
func node_count() -> int:
	return _nodes.size()


## The pooled mesh node at `index`, for tests.
func node(index: int) -> MeshInstance3D:
	return _nodes[index]


## A unit-sized mesh for `shape`: about 1 m from the centre to the surface
## along its widest axes, so the node's scale is the item's size directly.
static func build_mesh(shape: String) -> PrimitiveMesh:
	match shape:
		"cylinder":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 0.35
			cylinder.bottom_radius = 0.35
			cylinder.height = 2.0
			cylinder.radial_segments = 10
			cylinder.rings = 1
			return cylinder
		"torus":
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = 0.6
			torus.outer_radius = 1.0
			torus.rings = 16
			torus.ring_segments = 8
			return torus
	return RobotView.build_mesh(shape)


func _mesh_for(id: String) -> PrimitiveMesh:
	var key: String = id if _looks.has(id) else ""
	if _meshes.has(key):
		return _meshes[key]
	var look: Dictionary = look_for(id)
	var mesh: PrimitiveMesh = build_mesh(look["shape"])
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var color: Color = look["emission_color"]
	# Emissive so the part reads in the dark with no light on it (LGT-1).
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = EMISSION_ENERGY
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
