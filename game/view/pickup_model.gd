class_name PickupModel
extends RefCounted

## A pickup drawn as a few primitives (GFX-2, #1308): a physically based body
## and glowing pieces, so a dropped part, a component heap or a trapped miner
## reads as an object worth flying to rather than a lone glowing shape.
## `SalvageView`, `ComponentView` and `MinerPod` share it, so each look is data
## (ARC-4) and the meshes are primitives built here, no binary assets (ARC-5).
##
## A model, as it sits in a look file:
##
##     {"body": {"albedo": [r, g, b], "roughness": 0..1, "metallic": 0..1},
##      "pieces": [{"shape", "size": [x, y, z], "offset": [x, y, z],
##                  "turn": [x, y, z] degrees (optional), "glow": bool (optional)}]}
##
## Sizes and offsets are in the units of the node the model hangs under (the
## item's drawn size for parts and heaps, metres for a miner). A glow piece
## takes the glowing material its view hands in (the part's or kind's colour),
## so the core reads in the dark with no light on it (LGT-1); body pieces are
## lit only by the level's lights. The model adds no light of its own (GFX-4).

const NODE_NAME: String = "Model"
const KEYS: Array[String] = ["body", "pieces"]
const BODY_KEYS: Array[String] = ["albedo", "roughness", "metallic"]
const PIECE_KEYS: Array[String] = ["shape", "size", "offset"]
const OPTIONAL_PIECE_KEYS: Array[String] = ["turn", "glow"]
const SHAPES: Array[String] = ["sphere", "box", "capsule", "prism", "cylinder", "cone", "torus"]
const SIZE_RANGE: Array[float] = [0.01, 4.0]
const OFFSET_RANGE: Array[float] = [-4.0, 4.0]
const TURN_RANGE: Array[float] = [-360.0, 360.0]
const UNIT_RANGE: Array[float] = [0.0, 1.0]
## Few enough that one pickup stays a handful of draw calls.
const MAX_PIECES: int = 8
## Meta on the model node: the key it was built for, so a pooled node rebuilds
## only when it is handed a different look.
const BUILT_FOR: String = "built_for"

## One shared mesh per shape and one body material per look key.
var _meshes: Dictionary[String, PrimitiveMesh] = {}
var _bodies: Dictionary[String, StandardMaterial3D] = {}


## Parses `value` as a model; `{"body": {...}, "pieces": [...]}` with colours
## as `Color` and vectors as `Vector3`, or `{"error": ...}` naming `field`.
static func parse(field: String, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "\"%s\" must be an object" % field}
	var data: Dictionary = value
	var problem: String = _keys(field, data, KEYS, [])
	if problem != "":
		return {"error": problem}
	var body: Variant = data["body"]
	if typeof(body) != TYPE_DICTIONARY:
		return {"error": "\"%s.body\" must be an object" % field}
	problem = _keys(field + ".body", body, BODY_KEYS, [])
	var albedo: Variant = MinerLook.parse_color(field + ".body.albedo", body.get("albedo"))
	if problem == "" and typeof(albedo) == TYPE_STRING:
		problem = albedo
	for key: String in ["roughness", "metallic"]:
		if problem == "":
			problem = MinerLook.check_number("%s.body.%s" % [field, key], body[key], UNIT_RANGE)
	if problem != "":
		return {"error": problem}
	var parsed: Dictionary = {"body": {"albedo": albedo, "roughness": float(body["roughness"]),
		"metallic": float(body["metallic"])}, "pieces": []}
	if typeof(data["pieces"]) != TYPE_ARRAY or (data["pieces"] as Array).is_empty():
		return {"error": "\"%s.pieces\" must be a list of at least one piece" % field}
	if (data["pieces"] as Array).size() > MAX_PIECES:
		return {"error": "\"%s.pieces\" has more than %d pieces" % [field, MAX_PIECES]}
	for index: int in (data["pieces"] as Array).size():
		var piece: Dictionary = _parse_piece("%s.pieces[%d]" % [field, index], data["pieces"][index])
		if piece.has("error"):
			return piece
		(parsed["pieces"] as Array).append(piece)
	return parsed


## Hangs `model` under `holder` as one child, the pieces built with `glow` on
## the glowing ones; `key` names the look, so the body material is shared and
## an unchanged holder is left alone. An empty `model` removes the child, which
## brings back the holder's own mesh as before.
func dress(holder: Node3D, key: String, model: Dictionary, glow: Material) -> void:
	var built: Node3D = holder.get_node_or_null(NODE_NAME) as Node3D
	if built != null and (model.is_empty() or str(built.get_meta(BUILT_FOR, "")) != key):
		holder.remove_child(built)
		built.free()
		built = null
	if model.is_empty() or built != null:
		return
	built = Node3D.new()
	built.name = NODE_NAME
	built.set_meta(BUILT_FOR, key)
	for piece: Dictionary in model["pieces"]:
		var part: MeshInstance3D = MeshInstance3D.new()
		part.mesh = _mesh(piece["shape"])
		var turn: Vector3 = piece["turn"] * (PI / 180.0)
		part.transform = Transform3D(Basis.from_euler(turn) * Basis.from_scale(piece["size"]), piece["offset"])
		part.material_override = glow if piece["glow"] else _body(key, model["body"])
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		built.add_child(part)
	holder.add_child(built)


## The model hanging under `holder`, or null.
static func model_of(holder: Node3D) -> Node3D:
	return holder.get_node_or_null(NODE_NAME) as Node3D


## Draw calls and triangles one copy of `model` adds: one surface per piece.
func cost(model: Dictionary) -> Dictionary:
	var triangles: int = 0
	for piece: Dictionary in model.get("pieces", []):
		var arrays: Array = _mesh(piece["shape"]).surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return {"draw_calls": (model.get("pieces", []) as Array).size(), "triangles": triangles}


func _mesh(shape: String) -> PrimitiveMesh:
	if not _meshes.has(shape):
		_meshes[shape] = RobotMeshes.build_mesh(shape)
	return _meshes[shape]


func _body(key: String, body: Dictionary) -> StandardMaterial3D:
	if not _bodies.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = body["albedo"]
		material.roughness = body["roughness"]
		material.metallic = body["metallic"]
		_bodies[key] = material
	return _bodies[key]


static func _parse_piece(field: String, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "\"%s\" must be an object" % field}
	var data: Dictionary = value
	var problem: String = _keys(field, data, PIECE_KEYS, OPTIONAL_PIECE_KEYS)
	if problem == "" and (typeof(data["shape"]) != TYPE_STRING or not SHAPES.has(data["shape"])):
		problem = "\"%s.shape\" must be one of %s" % [field, ", ".join(PackedStringArray(SHAPES))]
	if problem == "" and data.has("glow") and typeof(data["glow"]) != TYPE_BOOL:
		problem = "\"%s.glow\" must be true or false" % field
	var piece: Dictionary = {"shape": data.get("shape"), "glow": data.get("glow", false), "turn": Vector3.ZERO}
	var vectors: Dictionary = {"size": SIZE_RANGE, "offset": OFFSET_RANGE, "turn": TURN_RANGE}
	for key: String in vectors:
		if problem != "" or not data.has(key):
			continue
		var vector: Variant = _vector("%s.%s" % [field, key], data[key], vectors[key])
		if typeof(vector) == TYPE_STRING:
			problem = vector
		else:
			piece[key] = vector
	return {"error": problem} if problem != "" else piece


## `[x, y, z]` within `limits` as a `Vector3`, or a String naming `field`.
static func _vector(field: String, value: Variant, limits: Array[float]) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "\"%s\" must be [x, y, z]" % field
	for part: Variant in value:
		var problem: String = MinerLook.check_number(field, part, limits)
		if problem != "":
			return problem
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _keys(field: String, data: Dictionary, required: Array[String], optional: Array[String]) -> String:
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (required.has(key) or optional.has(key)):
			return "\"%s\" has unknown key \"%s\"" % [field, str(key)]
	for key: String in required:
		if not data.has(key):
			return "\"%s\" is missing key \"%s\"" % [field, key]
	return ""
