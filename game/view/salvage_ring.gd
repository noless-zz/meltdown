class_name SalvageRing
extends Node3D

## A ring around every floating part that brightens as the ship comes within
## reach of it (SLV-1, #600): dim while out of reach, brighter through the pull
## range and brightest where flying on would take it. The owner could not tell
## when or from how far a part is picked up; the ring shows both.
##
## Each ring faces the ship, so it reads as a hoop to fly through. It only
## reads the items, the ship copy and the rules it is given and never writes to
## them (MP-2). The look lives under the `ring` key of `salvage_look.json`, so
## it is tuned without code (ARC-4).

const NODE_NAME: String = "SalvageRing"
const MESH_PREFIX: String = "Ring"
## Key of the ring's entry in the salvage look file.
const LOOK_KEY: String = "ring"
const LOOK_KEYS: Array[String] = ["radius", "color", "far_energy", "near_energy"]
## Used when the file has no ring entry or it is rejected.
const FALLBACK_LOOK: Dictionary = {
	"radius": 0.8, "color": Color(0.9, 0.9, 0.9), "far_energy": 0.3, "near_energy": 3.0,
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
var _look: Dictionary = FALLBACK_LOOK
var _mesh: TorusMesh = null
## The boxes drawn this frame (#1382); null draws everything.
var boxes: VisibleBoxes = null
var _nodes: Array[MeshInstance3D] = []


func _init() -> void:
	name = NODE_NAME
	load_look()


## Parses the `ring` entry of a salvage look file's text: `{"radius": metres
## 0.1..5, "color": [r, g, b], "far_energy": 0..10, "near_energy":
## far_energy..20}`. Returns the look, with the colour as a `Color`, or a
## dictionary holding only `"error"`, which names the field.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "the look file is not a JSON object"}
	var entry: Variant = (json.data as Dictionary).get(LOOK_KEY, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "\"%s\" must be an object" % LOOK_KEY}
	var data: Dictionary = entry
	for key: Variant in data:
		if not LOOK_KEYS.has(key):
			return {"error": "\"%s\" has unknown key \"%s\"" % [LOOK_KEY, str(key)]}
	var look: Dictionary = {}
	var ranges: Dictionary = {"radius": [0.1, 5.0], "far_energy": [0.0, 10.0], "near_energy": [0.0, 20.0]}
	for key: String in ranges:
		var value: Variant = data.get(key, null)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s.%s\" must be a number" % [LOOK_KEY, key]}
		if float(value) < ranges[key][0] or float(value) > ranges[key][1]:
			return {"error": "\"%s.%s\" is %s, must be within %s..%s" % [LOOK_KEY, key, value,
				ranges[key][0], ranges[key][1]]}
		look[key] = float(value)
	if look["near_energy"] < look["far_energy"]:
		return {"error": "\"%s.near_energy\" must be at least far_energy" % LOOK_KEY}
	var color: Variant = data.get("color", null)
	if typeof(color) != TYPE_ARRAY or (color as Array).size() != 3:
		return {"error": "\"%s.color\" must be [red, green, blue]" % LOOK_KEY}
	for part: Variant in color:
		if (typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT) or float(part) < 0.0 \
				or float(part) > 1.0:
			return {"error": "\"%s.color\" must hold numbers within 0..1" % LOOK_KEY}
	look["color"] = Color(float(color[0]), float(color[1]), float(color[2]))
	return look


## Applies the ring entry of the look file at `path`. A missing or rejected
## entry keeps the fallback look and sets `look_error`. Returns `look_error`.
func load_look(path: String = SalvageView.DEFAULT_LOOK_FILE) -> String:
	var look: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		look = parse_look(FileAccess.get_file_as_string(path))
	_look = FALLBACK_LOOK
	look_error = ""
	if look.has("error"):
		look_error = "%s: %s" % [path, look["error"]]
		push_warning("SalvageRing uses the fallback look; %s" % look_error)
	else:
		_look = look
	_mesh = TorusMesh.new()
	_mesh.inner_radius = float(_look["radius"]) * 0.92
	_mesh.outer_radius = float(_look["radius"])
	_mesh.rings = 24
	_mesh.ring_segments = 6
	return look_error


## How bright a part's ring is for `ship`: `near_energy` within pickup reach,
## `far_energy` beyond pull reach or when the ship cannot take a part (no
## hull, gone, hold full), and in between through the pull range.
func energy_for(item: SalvageItem, ship: ShipState, rules: SalvageRules) -> float:
	var far: float = _look["far_energy"]
	var near: float = _look["near_energy"]
	if ship == null or ship.hull <= 0.0 or ship.escaped or not ship.hold_has_room():
		return far
	var distance: float = item.position.distance_to(ship.position) - ship.radius
	if distance <= rules.pickup_reach:
		return near
	if distance >= rules.pull_reach:
		return far
	return lerpf(near, far, (distance - rules.pickup_reach) / (rules.pull_reach - rules.pickup_reach))


## Draws one ring per item of `current`, blended from `previous` by `alpha` as
## `SalvageView` blends the parts, facing `ship` and lit by `energy_for`.
func show_rings(previous: Array[SalvageItem], current: Array[SalvageItem], alpha: float,
		ship: ShipState, rules: SalvageRules) -> void:
	var blend: float = clampf(alpha, 0.0, 1.0)
	while _nodes.size() < current.size():
		_add_node()
	for index: int in current.size():
		var item: SalvageItem = current[index]
		var node: MeshInstance3D = _nodes[index]
		var before: SalvageItem = previous[index] if index < previous.size() else null
		if not SalvageView.is_same_item(before, item):
			before = item
		var at: Vector3 = before.position.lerp(item.position, blend)
		node.transform = Transform3D(_facing(at, ship), at)
		var material: StandardMaterial3D = node.material_override as StandardMaterial3D
		material.emission_energy_multiplier = energy_for(item, ship, rules)
		node.visible = VisibleBoxes.allows(boxes, at, float(_look["radius"]))
	for index: int in range(current.size(), _nodes.size()):
		_nodes[index].visible = false


func node_count() -> int:
	return _nodes.size()


## The pooled ring node at `index`, for tests.
func node(index: int) -> MeshInstance3D:
	return _nodes[index]


## A basis turning the torus's axis (+Y) towards the ship, so the ring is
## seen as a hoop. Without a ship, or with the ship on the ring, it stays level.
static func _facing(at: Vector3, ship: ShipState) -> Basis:
	if ship == null or at.is_equal_approx(ship.position):
		return Basis.IDENTITY
	var direction: Vector3 = at.direction_to(ship.position)
	if direction.dot(Vector3.UP) < -0.999:
		return Basis.IDENTITY
	return Basis(Quaternion(Vector3.UP, direction))


func _add_node() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s%d" % [MESH_PREFIX, _nodes.size()]
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var color: Color = _look["color"]
	# Emissive so it reads in the dark with no light on it (LGT-1).
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	instance.material_override = material
	instance.visible = false
	add_child(instance)
	_nodes.append(instance)
