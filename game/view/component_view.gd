class_name ComponentView
extends Node3D

## Draws the component heaps a sim holds (CRF-1, #1034), so a pilot can see
## what to fly through. One small glowing shape per heap, coloured by its
## component kind, so a heap reads in a dark tunnel (LGT-1) and never looks
## like a weapon part (`SalvageView` uses rings and rods).
##
## It only reads `Sim.components` and never writes to it (MP-2): a heap shows
## while it is in the list and not before or after. The slow spin is the
## view's own clock and is never written back. Nodes are pooled, as in
## `SalvageView`. The look lives in `res://view/component_look.json`, one
## colour per kind id and a fallback for an unknown kind, so a new kind needs a
## new entry there and no code (ARC-4). The optional `models` key gives a kind
## its own small shape (#1308, see `PickupModel`): a lit body with pieces
## glowing softly in the kind's colour, so kinds differ before any colour or
## label is read. A kind without a model keeps the single glowing shape.

const NODE_NAME: String = "ComponentView"
const MESH_PREFIX: String = "Heap"
const DEFAULT_LOOK_FILE: String = "res://view/component_look.json"
## Every key of the look file; all are required and no others are allowed.
const KEYS: Array[String] = ["shape", "size", "energy", "fallback", "kinds"]
const MODELS_KEY: String = "models"
const SIZE_RANGE: Array[float] = [0.05, 2.0]
const ENERGY_RANGE: Array[float] = [0.0, 10.0]
## Slow enough to read as resting, fast enough to catch the eye.
const SPIN_RADIANS_PER_SECOND: float = 0.8
## Used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = {
	"shape": "prism", "size": 0.35, "energy": 2.0, "fallback": Color(0.95, 0.95, 0.95), "kinds": {},
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Current spin about the vertical, in radians. View state only.
var spin_angle: float = 0.0

var _look: Dictionary = FALLBACK_LOOK
var _mesh: PrimitiveMesh = null
## One shared material per kind id (and "" for the fallback), built on first use.
var _materials: Dictionary[String, StandardMaterial3D] = {}
var _nodes: Array[MeshInstance3D] = []
var _models: PickupModel = PickupModel.new()


func _init() -> void:
	name = NODE_NAME
	load_look()


func _process(delta: float) -> void:
	advance_spin(delta)


func advance_spin(seconds: float) -> void:
	spin_angle = fposmod(spin_angle + SPIN_RADIANS_PER_SECOND * seconds, TAU)


## Parses the text of a look file: `{"shape": one of SalvageView.SHAPES,
## "size": metres, "energy": emission, "fallback": [r, g, b], "kinds": {<kind
## id>: [r, g, b]}}`. Returns the look with colours as `Color`s, or a
## dictionary holding only `"error"`, which names the key.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or key == MODELS_KEY):
			return {"error": "unknown key \"%s\"" % str(key)}
	for key: String in KEYS:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
	if typeof(data["shape"]) != TYPE_STRING or not SalvageView.SHAPES.has(data["shape"]):
		return {"error": "key \"shape\" must be one of %s" % ", ".join(PackedStringArray(SalvageView.SHAPES))}
	var look: Dictionary = {"shape": data["shape"]}
	var ranges: Dictionary = {"size": SIZE_RANGE, "energy": ENERGY_RANGE}
	for key: String in ranges:
		var problem: String = MinerView.check_number(key, data[key], ranges[key])
		if problem != "":
			return {"error": problem}
		look[key] = float(data[key])
	var fallback: Variant = MinerView.parse_color("fallback", data["fallback"])
	if typeof(fallback) == TYPE_STRING:
		return {"error": fallback}
	look["fallback"] = fallback
	if typeof(data["kinds"]) != TYPE_DICTIONARY:
		return {"error": "key \"kinds\" must be an object of kind id to colour"}
	var kinds: Dictionary = {}
	for id: Variant in data["kinds"]:
		var color: Variant = MinerView.parse_color("kinds.%s" % str(id), data["kinds"][id])
		if typeof(color) == TYPE_STRING:
			return {"error": color}
		kinds[str(id)] = color
	look["kinds"] = kinds
	var models: Dictionary = {}
	var given: Variant = data.get(MODELS_KEY, {})
	if typeof(given) != TYPE_DICTIONARY:
		return {"error": "key \"models\" must be an object of kind id to model"}
	for id: Variant in given:
		var model: Dictionary = PickupModel.parse("models.%s" % str(id), given[id])
		if model.has("error"):
			return model
		models[str(id)] = model
	look[MODELS_KEY] = models
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
		push_warning("ComponentView uses the fallback look; %s" % look_error)
	else:
		_look = look
	_materials.clear()
	_mesh = SalvageView.build_mesh(_look["shape"])
	_models = PickupModel.new()
	for instance: MeshInstance3D in _nodes:
		instance.mesh = _mesh
		_models.dress(instance, "", {}, null)
	return look_error


## The colour drawn for kind `id`: its own entry, or the fallback.
func color_for(id: String) -> Color:
	return (_look["kinds"] as Dictionary).get(id, _look["fallback"])


## The model drawn for kind `id`, or an empty one for the single shape.
func model_for(id: String) -> Dictionary:
	return (_look.get(MODELS_KEY, {}) as Dictionary).get(id, {})


## Kind ids the loaded look file lists.
func looked_kinds() -> Array[String]:
	var ids: Array[String] = []
	ids.assign((_look["kinds"] as Dictionary).keys())
	return ids


## Draws one node per heap of `sim.components`; none while component drops are
## off. Heaps do not move, so there is nothing to blend.
func show_heaps(sim: Sim) -> void:
	var heaps: Array[ComponentItem] = []
	if sim.component_rules != null:
		heaps = sim.components
	var size: float = _look["size"]
	var turn: Basis = Basis(Vector3.UP, spin_angle).scaled(Vector3.ONE * size)
	while _nodes.size() < heaps.size():
		_add_node()
	for index: int in heaps.size():
		var heap: ComponentItem = heaps[index]
		var instance: MeshInstance3D = _nodes[index]
		var model: Dictionary = model_for(heap.kind_id)
		instance.material_override = _material_for(heap.kind_id)
		instance.mesh = _mesh if model.is_empty() else null
		_models.dress(instance, heap.kind_id, model, instance.material_override)
		instance.transform = Transform3D(turn, heap.position)
		instance.visible = true
	for index: int in range(heaps.size(), _nodes.size()):
		_nodes[index].visible = false


## Heaps drawn now.
func shown_count() -> int:
	var shown: int = 0
	for instance: MeshInstance3D in _nodes:
		if instance.visible:
			shown += 1
	return shown


func node_count() -> int:
	return _nodes.size()


## The pooled node at `index`, for tests.
func node(index: int) -> MeshInstance3D:
	return _nodes[index]


func _material_for(id: String) -> StandardMaterial3D:
	var key: String = id if (_look["kinds"] as Dictionary).has(id) else ""
	if _materials.has(key):
		return _materials[key]
	var color: Color = color_for(id)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Emissive so the heap reads in the dark with no light on it (LGT-1).
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = _look["energy"]
	_materials[key] = material
	return material


func _add_node() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s%d" % [MESH_PREFIX, _nodes.size()]
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	add_child(instance)
	_nodes.append(instance)
