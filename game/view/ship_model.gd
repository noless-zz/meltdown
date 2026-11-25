class_name ShipModel
extends Node3D

## A ship's exterior built from a `ShipLook` (#1362, GFX-2, PRF-4, MP-2): one
## primitive per piece, the look's shared lit materials, and an engine glow
## that brightens with thrust. The base cradle, the stress scene's extra ships
## and later the co-op view each hang one and move it with `show_at`.
##
## It is handed a transform and a thrust value and nothing else: it reads no
## simulation object and writes none (MP-2), so drawing other ships can never
## change the simulation. It adds no light of its own (GFX-4); the glow is
## emission only.

## One mesh per shape, shared by every ship model.
static var _meshes: Dictionary[String, PrimitiveMesh] = {}

var _look: ShipLook = null
var _engine: StandardMaterial3D = StandardMaterial3D.new()
var _pieces: Array[MeshInstance3D] = []
var _thrust: float = 0.0


## A model of `look` (the shipped file when null), its engine at idle.
static func create(look: ShipLook = null) -> ShipModel:
	var model: ShipModel = ShipModel.new()
	model.name = "ShipModel"
	model.build(look if look != null else ShipLook.load_file())
	return model


## Builds the pieces of `look`, replacing any built before.
func build(look: ShipLook) -> void:
	for piece: MeshInstance3D in _pieces:
		remove_child(piece)
		piece.free()
	_pieces.clear()
	_look = look
	var engine: Dictionary = look.look["engine"]
	_engine = StandardMaterial3D.new()
	_engine.albedo_color = engine["color"]
	_engine.emission_enabled = true
	_engine.emission = engine["color"]
	for spec: Dictionary in look.look["pieces"]:
		var piece: MeshInstance3D = MeshInstance3D.new()
		piece.mesh = mesh_for(spec["shape"])
		var turn: Vector3 = spec["turn"] * (PI / 180.0)
		piece.transform = Transform3D(Basis.from_euler(turn) * Basis.from_scale(spec["size"]), spec["offset"])
		piece.material_override = _engine if spec["material"] == ShipLook.ENGINE else look.material(spec["material"])
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pieces.append(piece)
		add_child(piece)
	set_thrust(_thrust)


## Places the ship at `pose` with its engines at `thrust` (0 idle, 1 full).
func show_at(pose: Transform3D, thrust: float) -> void:
	transform = pose
	set_thrust(thrust)


func set_thrust(thrust: float) -> void:
	_thrust = clampf(thrust, 0.0, 1.0)
	if _look == null:
		return
	var engine: Dictionary = _look.look["engine"]
	_engine.emission_energy_multiplier = lerpf(engine["idle_energy"], engine["full_energy"], _thrust)


func thrust() -> float:
	return _thrust


func engine_energy() -> float:
	return _engine.emission_energy_multiplier


func engine_material() -> StandardMaterial3D:
	return _engine


func pieces() -> Array[MeshInstance3D]:
	return _pieces


## What one ship costs to draw: a draw call per piece, the distinct materials
## they share, and triangles.
func cost() -> Dictionary:
	var materials: Array[Material] = []
	var triangles: int = 0
	for piece: MeshInstance3D in _pieces:
		if not materials.has(piece.material_override):
			materials.append(piece.material_override)
		triangles += triangles_of(piece.mesh)
	return {"pieces": _pieces.size(), "draw_calls": _pieces.size(), "materials": materials.size(),
		"triangles": triangles}


static func mesh_for(shape: String) -> PrimitiveMesh:
	if not _meshes.has(shape):
		_meshes[shape] = RobotMeshes.build_mesh(shape)
	return _meshes[shape]


static func triangles_of(mesh: Mesh) -> int:
	var arrays: Array = mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if not indices.is_empty():
		return indices.size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
