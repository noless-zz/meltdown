class_name RobotView
extends Node3D

## Draws the simulation's robots as placeholder shapes, one look per robot type
## (CMB-3): a body and extra parts for a silhouette that reads at 20 m, a lean
## or skid drawn from the robot's velocity and an eye that dims when it loses
## sight of its target (`RobotTells`, #638), a flash on every hit, a dim sputter below
## half hull, a glow that grows over the wind-up before a burst of fire and a
## burst where one is destroyed (#604).
##
## It only reads the robots it is given and never writes to them, so the view
## cannot change what the authoritative simulation decided (MP-2). Nodes are
## pooled: robots appearing and disappearing reuse hidden nodes instead of
## creating and freeing them every frame.
##
## The look per type lives in `res://view/robot_look.json` (`RobotLook`), keyed
## by the robot data file's id, so a new robot type needs a new entry there and
## no code (ARC-4).

const NODE_NAME: String = "RobotView"
const MESH_PREFIX: String = "Robot"
const DEFAULT_LOOK_FILE: String = "res://view/robot_look.json"
const SHAPES: Array[String] = RobotLook.SHAPES
## Look used for an id the file does not list, and when the file is rejected.
const FALLBACK_LOOK: Dictionary = RobotLook.FALLBACK
## How bright an eye part is while its robot sleeps (not yet awake).
const ASLEEP_EYE: float = 0.08
## A hit flash adds up to this much emission energy, so it reads in the dark.
const FLASH_ENERGY: float = 3.0

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Seconds on the clock the flashes and bursts run on. Negative: the engine's
## clock. Tests set it to step time by hand.
var clock_s: float = -1.0

var _looks: Dictionary[String, Dictionary] = {}
var _default_look: Dictionary = FALLBACK_LOOK
var _effects: Dictionary = RobotLook.DEFAULT_EFFECTS
## One shared unit mesh per shape, built on first use.
var _meshes: Dictionary[String, PrimitiveMesh] = {}
## Pooled robot nodes. The root carries the pose and no mesh of its own; its
## children are the body and the parts of the type in `_node_ids`.
var _nodes: Array[MeshInstance3D] = []
var _node_ids: Array[String] = []
var _body_materials: Array[StandardMaterial3D] = []
var _eye_materials: Array[StandardMaterial3D] = []
var _bursts: RobotBursts = RobotBursts.new()
var _tracker: RobotHitTracker = RobotHitTracker.new()


func _init() -> void:
	name = NODE_NAME
	add_child(_bursts)
	load_look()


## See `RobotLook.parse`.
static func parse_look(text: String) -> Dictionary:
	return RobotLook.parse(text)


## Applies the look file at `path`. A missing or rejected file leaves every
## robot with the fallback look, sets `look_error` and pushes a warning naming
## the field. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = parse_look(FileAccess.get_file_as_string(path))
	else:
		values = {"error": "file not found"}
	_looks.clear()
	_node_ids.fill("")
	_default_look = FALLBACK_LOOK
	_effects = RobotLook.DEFAULT_EFFECTS
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("RobotView uses the fallback look; %s" % look_error)
	else:
		_default_look = values["default"]
		_effects = values["effects"]
		var robots: Dictionary = values["robots"]
		for id: String in robots:
			_looks[id] = robots[id]
	return look_error


## The look drawn for robot type `id`: its own entry, or the default.
func look_for(id: String) -> Dictionary:
	return _looks.get(id, _default_look)


## The flash, damage and burst settings in use.
func effects() -> Dictionary:
	return _effects


## Ids the loaded look file lists.
func looked_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_looks.keys())
	return ids


## Draws every robot in `current`, `alpha` (0..1) of the way from its pose in
## `previous` to its pose in `current`. Both are copies of the simulation's
## ordered robot array on consecutive ticks. A robot with no partner in
## `previous` (new, or too far from any) is drawn where it is; a robot of
## `previous` with none in `current` was destroyed and bursts. Never writes to
## either array (MP-2).
func show_robots(previous: Array[RobotState], current: Array[RobotState], alpha: float) -> void:
	var now: float = now_s()
	var blend: float = clampf(alpha, 0.0, 1.0)
	_tracker.observe(previous, current, now)
	while _nodes.size() < current.size():
		_add_node()
	for index: int in current.size():
		var robot: RobotState = current[index]
		var node: MeshInstance3D = _nodes[index]
		if robot == null or robot.def == null:
			node.visible = false
			continue
		var at: int = _tracker.partner(index)
		var before: RobotState = previous[at] if at >= 0 and at < previous.size() else robot
		var look: Dictionary = look_for(robot.def.id)
		if _node_ids[index] != robot.def.id:
			_build_parts(index, look)
			_node_ids[index] = robot.def.id
		var size: float = robot.def.radius * float(look["scale"])
		var from_rotation: Quaternion = before.orientation.orthonormalized().get_rotation_quaternion()
		var to_rotation: Quaternion = robot.orientation.orthonormalized().get_rotation_quaternion()
		var rotation: Quaternion = from_rotation.slerp(to_rotation, blend)
		var leaned: Basis = RobotTells.drawn_basis(rotation, robot, look["tell"])
		node.transform = Transform3D(leaned.scaled(Vector3.ONE * size),
				before.position.lerp(robot.position, blend))
		var hull_fraction: float = robot.hull / robot.def.hull if robot.def.hull > 0.0 else 1.0
		_paint(index, look, RobotHitTracker.glow(_effects, hull_fraction, _tracker.since_hit(index, now), now,
				RobotHitTracker.windup_fraction(robot)), robot.awake, RobotTells.eye_share(robot, look["tell"]))
		node.visible = true
	for index: int in range(current.size(), _nodes.size()):
		_nodes[index].visible = false
	_tracker.prune_bursts(now, _effects["burst_seconds"])
	_bursts.show_bursts(_tracker.bursts, _effects, now)


## Seconds on the flash and burst clock.
func now_s() -> float:
	return clock_s if clock_s >= 0.0 else Time.get_ticks_usec() / 1_000_000.0


## See `RobotTells.lean_degrees`.
static func lean_degrees(robot: RobotState, tell: Dictionary) -> Vector2:
	return RobotTells.lean_degrees(robot, tell)


## See `RobotHitTracker.is_same_robot`.
static func is_same_robot(before: RobotState, robot: RobotState) -> bool:
	return RobotHitTracker.is_same_robot(before, robot)


## Number of robot nodes in the pool, shown or hidden.
func node_count() -> int:
	return _nodes.size()


## The pooled robot node at `index`, for tests. Its children are the body and parts.
func node(index: int) -> MeshInstance3D:
	return _nodes[index]


## The body material of the robot node at `index`, for tests.
func body_material(index: int) -> StandardMaterial3D:
	return _body_materials[index]


## Bursts drawn on the last `show_robots`.
func visible_burst_count() -> int:
	return _bursts.visible_count()


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
		"cylinder", "cone":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 1.0 if shape == "cylinder" else 0.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 2.0
			cylinder.radial_segments = 12
			cylinder.rings = 1
			return cylinder
		"torus":
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = 0.7
			torus.outer_radius = 1.0
			torus.rings = 16
			torus.ring_segments = 6
			return torus
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere


func _mesh(shape: String) -> PrimitiveMesh:
	if not _meshes.has(shape):
		_meshes[shape] = build_mesh(shape)
	return _meshes[shape]


## Rebuilds the children of node `index` for `look`: the body, then each part.
func _build_parts(index: int, look: Dictionary) -> void:
	var root: MeshInstance3D = _nodes[index]
	for child: Node in root.get_children():
		root.remove_child(child)
		child.free()
	var pieces: Array = [{"shape": look["shape"], "size": look["stretch"], "offset": Vector3.ZERO, "eye": false}]
	pieces.append_array(look["parts"])
	for piece: Dictionary in pieces:
		var part: MeshInstance3D = MeshInstance3D.new()
		part.mesh = _mesh(piece["shape"])
		part.transform = Transform3D(Basis.from_scale(piece["size"]), piece["offset"])
		part.material_override = _eye_materials[index] if piece["eye"] else _body_materials[index]
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(part)


## `eye_share` (0..1) scales an awake eye, from `RobotTells.eye_share`.
func _paint(index: int, look: Dictionary, glow: Dictionary, awake: bool, eye_share: float = 1.0) -> void:
	var base: Color = look["emission_color"]
	var flash: float = glow["flash"]
	var flash_color: Color = _effects["hit_flash_color"]
	var body: StandardMaterial3D = _body_materials[index]
	# Shaded, so the shape still reads under the ship's and the bolts' lights,
	# and emissive, so the colour reads in a dark tunnel with no light on it.
	body.albedo_color = (base * float(glow["brightness"])).lerp(flash_color, flash)
	body.emission = body.albedo_color
	# The glow grows over the wind-up, so the pilot sees a burst coming (#612).
	var windup: float = float(glow["windup"]) * float(_effects["windup_energy"])
	body.emission_energy_multiplier = 1.0 + FLASH_ENERGY * flash + windup
	var eye: Color = look["eye_color"]
	_eye_materials[index].emission = eye * eye_share if awake else eye * ASLEEP_EYE
	_eye_materials[index].albedo_color = _eye_materials[index].emission
	_eye_materials[index].emission_energy_multiplier = 1.0 + 2.0 * windup


func _add_node() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s%d" % [MESH_PREFIX, _nodes.size()]
	instance.visible = false
	add_child(instance)
	_nodes.append(instance)
	_node_ids.append("")
	var body: StandardMaterial3D = StandardMaterial3D.new()
	body.emission_enabled = true
	_body_materials.append(body)
	var eye: StandardMaterial3D = StandardMaterial3D.new()
	eye.emission_enabled = true
	_eye_materials.append(eye)
