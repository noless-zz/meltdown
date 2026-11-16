class_name ProjectileView
extends Node3D

## Draws the simulation's projectiles as glowing bolts (CMB-1). Mines are dark
## by default and weapons are one of the main light sources (LGT-1), so the
## bolts are unshaded and emissive: they read without any light on them.
##
## It only reads the projectiles it is given and never writes to them, so the
## view cannot change what the authoritative simulation decided (MP-2).
## Bolts are pooled: a burst of fire reuses hidden nodes instead of creating
## and freeing them every frame.
##
## The look (length, radius, colour) is a guess for the first headset session
## and lives in `res://view/projectile_look.json` so the owner can change it.

const NODE_NAME: String = "ProjectileView"
const BOLT_PREFIX: String = "Bolt"
const DEFAULT_LOOK_FILE: String = "res://view/projectile_look.json"

const DEFAULT_BOLT_LENGTH_M: float = 0.6
const DEFAULT_BOLT_RADIUS_M: float = 0.03
const DEFAULT_EMISSION_COLOR: Color = Color(1.0, 0.55, 0.15)

## Every key of the look file, with the same name as the field it sets.
const KEYS: Array[String] = ["bolt_length_m", "bolt_radius_m", "emission_color"]

## Allowed range of each number, inclusive: [minimum, maximum]. For
## `emission_color` the range holds for each of its red, green and blue parts.
const RANGES: Dictionary[String, Array] = {
	"bolt_length_m": [0.05, 5.0],
	"bolt_radius_m": [0.005, 0.5],
	"emission_color": [0.0, 1.0],
}

## Bolt length along its flight direction, metres, 0.05..5.
var bolt_length_m: float = DEFAULT_BOLT_LENGTH_M
## Bolt radius, metres, 0.005..0.5.
var bolt_radius_m: float = DEFAULT_BOLT_RADIUS_M
## Colour the bolt glows with; each part 0..1.
var emission_color: Color = DEFAULT_EMISSION_COLOR
## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _bolts: Array[MeshInstance3D] = []
## Each projectile shown on the last call, with the position it had when it
## was first shown. Holding the projectile keeps its identity from being
## reused by a new one while it is still remembered.
var _first_seen: Dictionary[Projectile, Vector3] = {}
var _mesh: CylinderMesh = CylinderMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _init() -> void:
	name = NODE_NAME
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	# One draw call's worth of geometry per bolt; it is small and fast.
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_mesh.material = _material
	load_look()


## Parses the text of a look file: one JSON object holding every key in
## `KEYS`, the numbers in their ranges and `emission_color` as three numbers.
## Returns the values by key, or a dictionary holding only `"error"`, which
## names the field.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var values: Dictionary = {}
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var parts: Array = [data[key]]
		if key == "emission_color":
			if typeof(data[key]) != TYPE_ARRAY or (data[key] as Array).size() != 3:
				return _rejected("key \"%s\" must be [red, green, blue]" % key)
			parts = data[key]
		for value: Variant in parts:
			# A bool must not pass as 0 or 1.
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return _rejected("key \"%s\" must hold numbers" % key)
			var low: float = RANGES[key][0]
			var high: float = RANGES[key][1]
			if float(value) < low or float(value) > high:
				return _rejected("key \"%s\" has %s, must be within %s..%s" % [key, value, low, high])
		if key == "emission_color":
			values[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
		else:
			values[key] = float(data[key])
	return values


## Applies the look file at `path`. A missing or rejected file leaves the
## default look, sets `look_error` and pushes a warning naming the field.
## Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = parse_look(FileAccess.get_file_as_string(path))
	else:
		values = _rejected("file not found")
	bolt_length_m = DEFAULT_BOLT_LENGTH_M
	bolt_radius_m = DEFAULT_BOLT_RADIUS_M
	emission_color = DEFAULT_EMISSION_COLOR
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("ProjectileView uses the default look; %s" % look_error)
	else:
		for key: String in KEYS:
			set(key, values[key])
	_apply_look()
	return look_error


## Draws one bolt per projectile, `alpha` (0..1) of the way from the previous
## tick to the current one. A projectile that has not moved since it was first
## shown was fired on the current tick and has no previous position, so it is
## drawn where it is. Never writes to `projectiles` (MP-2).
func show_projectiles(projectiles: Array[Projectile], alpha: float) -> void:
	var blend: float = clampf(alpha, 0.0, 1.0)
	while _bolts.size() < projectiles.size():
		_add_bolt()
	var seen: Dictionary[Projectile, Vector3] = {}
	for index: int in projectiles.size():
		var projectile: Projectile = projectiles[index]
		var bolt: MeshInstance3D = _bolts[index]
		if projectile == null:
			bolt.visible = false
			continue
		var first_position: Vector3 = _first_seen.get(projectile, projectile.position)
		seen[projectile] = first_position
		var drawn: Vector3 = projectile.position
		if first_position != projectile.position:
			drawn += projectile.velocity * ShipState.TICK_DT * (blend - 1.0)
		bolt.transform = Transform3D(bolt_basis(projectile.velocity), drawn)
		bolt.visible = true
	for index: int in range(projectiles.size(), _bolts.size()):
		_bolts[index].visible = false
	_first_seen = seen


## Number of bolt nodes in the pool, shown or hidden.
func bolt_count() -> int:
	return _bolts.size()


## The pooled bolt at `index`, for tests and for the lights that follow (#187).
func bolt(index: int) -> MeshInstance3D:
	return _bolts[index]


## A rotation whose Y axis, the bolt mesh's long axis, points along
## `direction`. The identity for a projectile at rest.
static func bolt_basis(direction: Vector3) -> Basis:
	if direction.length_squared() < 1e-12:
		return Basis.IDENTITY
	var y: Vector3 = direction.normalized()
	# Any helper axis not parallel to the flight direction will do.
	var helper: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = helper.cross(y).normalized()
	return Basis(x, y, x.cross(y))


func _add_bolt() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s%d" % [BOLT_PREFIX, _bolts.size()]
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	add_child(instance)
	_bolts.append(instance)


func _apply_look() -> void:
	_mesh.height = bolt_length_m
	_mesh.top_radius = bolt_radius_m
	_mesh.bottom_radius = bolt_radius_m
	_material.albedo_color = emission_color
	_material.emission = emission_color


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
