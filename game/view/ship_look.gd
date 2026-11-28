class_name ShipLook
extends RefCounted

## The ship's exterior as data (#1362, GFX-2, ARC-4, ARC-5, NAM-3): named
## physically based materials, an engine glow and up to `MAX_PIECES`
## primitive pieces, read from `view/ship_look.json`. `ShipModel` builds the
## ship from it for the base cradle, the stress scene's extra ships and later
## co-op, so the design changes without code.
##
##     {"materials": {"<name>": {"albedo": [r, g, b], "roughness": 0..1, "metallic": 0..1}},
##      "engine": {"color": [r, g, b], "idle_energy": e, "full_energy": e},
##      "pieces": [{"shape", "size": [x, y, z], "offset": [x, y, z],
##                  "turn": [x, y, z] degrees (optional), "material": "<name>" or "engine"}]}
##
## Metres, ship space: -Z is the nose, +Y the top, as the simulation's ship.
## Shapes and their unit sizes are `RobotMeshes.build_mesh`'s. A file that
## cannot be read keeps the plain hull below and names the bad field in
## `error`, as the pickup looks do (#1308).

const PATH: String = "res://view/ship_look.json"
const ENGINE: String = "engine"
const KEYS: Array[String] = ["materials", "engine", "pieces"]
const MATERIAL_KEYS: Array[String] = ["albedo", "roughness", "metallic"]
const ENGINE_KEYS: Array[String] = ["color", "idle_energy", "full_energy"]
const PIECE_KEYS: Array[String] = ["shape", "size", "offset", "material"]
const OPTIONAL_PIECE_KEYS: Array[String] = ["turn"]
const SIZE_RANGE: Array[float] = [0.01, 3.0]
const OFFSET_RANGE: Array[float] = [-3.0, 3.0]
const TURN_RANGE: Array[float] = [-360.0, 360.0]
const UNIT_RANGE: Array[float] = [0.0, 1.0]
const ENERGY_RANGE: Array[float] = [0.0, 16.0]
## One draw call per piece; PRF-4's per-ship share (#1362).
const MAX_PIECES: int = 12
## A capsule hull and an engine glow: still a ship with a front and a thrust.
const PLAIN: Dictionary = {
	"materials": {"hull": {"albedo": [0.55, 0.56, 0.58], "roughness": 0.45, "metallic": 0.7}},
	"engine": {"color": [0.4, 0.75, 1.0], "idle_energy": 0.5, "full_energy": 5.0},
	"pieces": [
		{"shape": "capsule", "size": [0.6, 0.9, 0.5], "offset": [0.0, 0.0, 0.0], "turn": [90.0, 0.0, 0.0], "material": "hull"},
		{"shape": "cylinder", "size": [0.2, 0.02, 0.2], "offset": [0.0, 0.0, 0.92], "turn": [90.0, 0.0, 0.0], "material": "engine"},
	],
}

## Parsed: `{"materials": {name: {albedo: Color, roughness, metallic}},
## "engine": {color: Color, idle_energy, full_energy}, "pieces": [...]}`.
var look: Dictionary = {}
## Why the file was refused, naming the field; "" when it was read.
var error: String = ""

var _materials: Dictionary[String, StandardMaterial3D] = {}


## The shipped look, or the plain hull with a warning naming the bad field.
static func load_file(path: String = PATH) -> ShipLook:
	var result: ShipLook = ShipLook.new()
	var raw: Variant = null
	var problem: String = ""
	if not FileAccess.file_exists(path):
		problem = "%s is missing" % path
	else:
		raw = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw == null:
			problem = "%s is not valid JSON" % path
	result.use(raw if problem == "" else PLAIN)
	if problem != "":
		result.error = problem
	if result.error != "":
		push_warning("ShipModel uses the plain hull; %s" % result.error)
	return result


## Reads `raw`; on a bad field keeps the plain hull and sets `error`.
func use(raw: Variant) -> void:
	_materials.clear()
	error = ""
	var parsed: Dictionary = parse(raw)
	if parsed.has("error"):
		error = parsed["error"]
		parsed = parse(PLAIN)
	look = parsed


## The shared lit material named `name`, one per look, so ships of one look
## draw with the same few materials.
func material(name: String) -> StandardMaterial3D:
	if not _materials.has(name):
		var data: Dictionary = look["materials"][name]
		var made: StandardMaterial3D = StandardMaterial3D.new()
		made.albedo_color = data["albedo"]
		made.roughness = data["roughness"]
		made.metallic = data["metallic"]
		_materials[name] = made
	return _materials[name]


static func parse(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"error": "the ship look must be an object"}
	var data: Dictionary = raw
	var problem: String = PickupModel._keys("ship look", data, KEYS, [])
	if problem != "":
		return {"error": problem}
	var parsed: Dictionary = {"materials": {}, "pieces": []}
	if typeof(data["materials"]) != TYPE_DICTIONARY or (data["materials"] as Dictionary).is_empty():
		return {"error": "\"materials\" must be an object with at least one material"}
	for name: Variant in data["materials"]:
		if str(name) == ENGINE:
			return {"error": "\"materials.%s\" is reserved for the engine glow" % ENGINE}
		var made: Variant = _parse_material("materials.%s" % name, data["materials"][name])
		if typeof(made) == TYPE_STRING:
			return {"error": made}
		parsed["materials"][str(name)] = made
	var engine: Variant = _parse_engine(data["engine"])
	if typeof(engine) == TYPE_STRING:
		return {"error": engine}
	parsed["engine"] = engine
	if typeof(data["pieces"]) != TYPE_ARRAY or (data["pieces"] as Array).is_empty():
		return {"error": "\"pieces\" must be a list of at least one piece"}
	if (data["pieces"] as Array).size() > MAX_PIECES:
		return {"error": "\"pieces\" has more than %d pieces" % MAX_PIECES}
	for index: int in (data["pieces"] as Array).size():
		var piece: Variant = _parse_piece("pieces[%d]" % index, data["pieces"][index], parsed["materials"])
		if typeof(piece) == TYPE_STRING:
			return {"error": piece}
		(parsed["pieces"] as Array).append(piece)
	return parsed


static func _parse_material(field: String, value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"%s\" must be an object" % field
	var problem: String = PickupModel._keys(field, value, MATERIAL_KEYS, [])
	var albedo: Variant = MinerLook.parse_color(field + ".albedo", (value as Dictionary).get("albedo"))
	if problem == "" and typeof(albedo) == TYPE_STRING:
		problem = albedo
	for key: String in ["roughness", "metallic"]:
		if problem == "":
			problem = MinerLook.check_number("%s.%s" % [field, key], value[key], UNIT_RANGE)
	if problem != "":
		return problem
	return {"albedo": albedo, "roughness": float(value["roughness"]), "metallic": float(value["metallic"])}


static func _parse_engine(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"engine\" must be an object"
	var problem: String = PickupModel._keys("engine", value, ENGINE_KEYS, [])
	var color: Variant = MinerLook.parse_color("engine.color", (value as Dictionary).get("color"))
	if problem == "" and typeof(color) == TYPE_STRING:
		problem = color
	for key: String in ["idle_energy", "full_energy"]:
		if problem == "":
			problem = MinerLook.check_number("engine.%s" % key, value[key], ENERGY_RANGE)
	if problem == "" and float(value["full_energy"]) <= float(value["idle_energy"]):
		problem = "\"engine.full_energy\" must be above \"engine.idle_energy\", so thrust shows"
	if problem != "":
		return problem
	return {"color": color, "idle_energy": float(value["idle_energy"]), "full_energy": float(value["full_energy"])}


static func _parse_piece(field: String, value: Variant, materials: Dictionary) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"%s\" must be an object" % field
	var data: Dictionary = value
	var problem: String = PickupModel._keys(field, data, PIECE_KEYS, OPTIONAL_PIECE_KEYS)
	if problem == "" and (typeof(data["shape"]) != TYPE_STRING or not PickupModel.SHAPES.has(data["shape"])):
		problem = "\"%s.shape\" must be one of %s" % [field, ", ".join(PackedStringArray(PickupModel.SHAPES))]
	if problem == "" and (typeof(data["material"]) != TYPE_STRING
			or not (data["material"] == ENGINE or materials.has(data["material"]))):
		problem = "\"%s.material\" must be \"%s\" or a name under \"materials\"" % [field, ENGINE]
	if problem != "":
		return problem
	var piece: Dictionary = {"shape": data["shape"], "material": data["material"], "turn": Vector3.ZERO}
	var vectors: Dictionary = {"size": SIZE_RANGE, "offset": OFFSET_RANGE, "turn": TURN_RANGE}
	for key: String in vectors:
		if not data.has(key):
			continue
		var vector: Variant = PickupModel._vector("%s.%s" % [field, key], data[key], vectors[key])
		if typeof(vector) == TYPE_STRING:
			return vector
		piece[key] = vector
	return piece
