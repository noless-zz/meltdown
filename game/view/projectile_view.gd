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
## The nearest few bolts to the viewer also carry a real light, so fire lights
## the tunnel walls (LGT-1). The lights have a fixed budget and are pooled, so a
## burst of fire cannot blow the Quest 3 frame budget (PRF-1).
##
## The look (length, radius, colour, light budget) is a guess for the first
## headset session and lives in `res://view/projectile_look.json` so the owner
## can change it.

const NODE_NAME: String = "ProjectileView"
const BOLT_PREFIX: String = "Bolt"
const LIGHT_PREFIX: String = "BoltLight"
const DEFAULT_LOOK_FILE: String = "res://view/projectile_look.json"

const DEFAULT_BOLT_LENGTH_M: float = 0.6
const DEFAULT_BOLT_RADIUS_M: float = 0.03
const DEFAULT_EMISSION_COLOR: Color = Color(1.0, 0.55, 0.15)
const DEFAULT_MAX_LIGHTS: int = 4
const DEFAULT_LIGHT_RANGE_M: float = 6.0
const DEFAULT_LIGHT_ENERGY: float = 1.5

## Every key of the look file, with the same name as the field it sets.
const KEYS: Array[String] = [
	"bolt_length_m", "bolt_radius_m", "emission_color", "max_lights", "light_range", "light_energy",
]
## Keys that must hold a whole number.
const WHOLE_KEYS: Array[String] = ["max_lights"]

## Allowed range of each number, inclusive: [minimum, maximum]. For
## `emission_color` the range holds for each of its red, green and blue parts.
const RANGES: Dictionary[String, Array] = {
	"bolt_length_m": [0.05, 5.0],
	"bolt_radius_m": [0.005, 0.5],
	"emission_color": [0.0, 1.0],
	# The mobile renderer the Quest uses lights a mesh with at most 8 omni
	# lights, so a larger budget would only cost time without lighting more.
	"max_lights": [0, 8],
	"light_range": [0.5, 30.0],
	"light_energy": [0.0, 16.0],
}

## Bolt length along its flight direction, metres, 0.05..5.
var bolt_length_m: float = DEFAULT_BOLT_LENGTH_M
## Bolt radius, metres, 0.005..0.5.
var bolt_radius_m: float = DEFAULT_BOLT_RADIUS_M
## Colour the bolt glows with; each part 0..1.
var emission_color: Color = DEFAULT_EMISSION_COLOR
## Most bolts that carry a light at once, 0..8; 0 turns the lights off.
var max_lights: int = DEFAULT_MAX_LIGHTS
## How far each bolt light reaches, metres, 0.5..30.
var light_range: float = DEFAULT_LIGHT_RANGE_M
## Brightness of each bolt light, 0..16. The light uses `emission_color`.
var light_energy: float = DEFAULT_LIGHT_ENERGY
## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _bolts: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
## Bolt index each pooled light sits on, in light order; -1 when unused.
var _lit: Array[int] = []
var _viewer: Vector3 = Vector3.ZERO
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
			if WHOLE_KEYS.has(key) and float(value) != floorf(float(value)):
				return _rejected("key \"%s\" must be a whole number" % key)
			var low: float = RANGES[key][0]
			var high: float = RANGES[key][1]
			if float(value) < low or float(value) > high:
				return _rejected("key \"%s\" has %s, must be within %s..%s" % [key, value, low, high])
		if key == "emission_color":
			values[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
		elif WHOLE_KEYS.has(key):
			values[key] = int(data[key])
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
	max_lights = DEFAULT_MAX_LIGHTS
	light_range = DEFAULT_LIGHT_RANGE_M
	light_energy = DEFAULT_LIGHT_ENERGY
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
	_light_nearest(projectiles)


## Where the camera is, in this node's space; the bolts nearest to it get the
## lights on the next `show_projectiles`.
func set_viewer(at: Vector3) -> void:
	_viewer = at


## Indices of the bolts carrying a light, nearest to the viewer first.
func lit_bolts() -> Array[int]:
	var lit: Array[int] = []
	for index: int in _lit:
		if index >= 0:
			lit.append(index)
	return lit


## Number of light nodes in the pool, lit or hidden.
func light_count() -> int:
	return _lights.size()


## The pooled light at `index`, for tests.
func light(index: int) -> OmniLight3D:
	return _lights[index]


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


## Puts the pooled lights on the `max_lights` shown bolts nearest the viewer.
## Equal distances keep the order of `projectiles`, so the choice is the same
## for the same input.
func _light_nearest(projectiles: Array[Projectile]) -> void:
	var chosen: Array[int] = []
	var distances: Array[float] = []
	for index: int in projectiles.size():
		if projectiles[index] == null:
			continue
		var distance: float = _viewer.distance_squared_to(_bolts[index].position)
		var slot: int = distances.size()
		# Strictly nearer only, so an equal distance stays behind earlier bolts.
		while slot > 0 and distance < distances[slot - 1]:
			slot -= 1
		if slot >= max_lights:
			continue  # Also skips every bolt when the budget is 0.
		chosen.insert(slot, index)
		distances.insert(slot, distance)
		if chosen.size() > max_lights:
			chosen.pop_back()
			distances.pop_back()
	while _lights.size() < chosen.size():
		_add_light()
	_lit.resize(_lights.size())
	for slot: int in _lights.size():
		var lamp: OmniLight3D = _lights[slot]
		if slot < chosen.size():
			_lit[slot] = chosen[slot]
			lamp.position = _bolts[chosen[slot]].position
			lamp.visible = true
		else:
			_lit[slot] = -1
			lamp.visible = false


func _add_light() -> void:
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "%s%d" % [LIGHT_PREFIX, _lights.size()]
	lamp.shadow_enabled = false
	lamp.visible = false
	_style_light(lamp)
	add_child(lamp)
	_lights.append(lamp)


func _style_light(lamp: OmniLight3D) -> void:
	lamp.omni_range = light_range
	lamp.light_energy = light_energy
	lamp.light_color = emission_color


func _apply_look() -> void:
	# A smaller budget frees the lights above it, so no more than `max_lights`
	# light nodes ever exist.
	while _lights.size() > max_lights:
		var lamp: OmniLight3D = _lights.pop_back()
		remove_child(lamp)
		lamp.free()
	_lit.resize(_lights.size())
	for lamp: OmniLight3D in _lights:
		_style_light(lamp)
	_mesh.height = bolt_length_m
	_mesh.top_radius = bolt_radius_m
	_mesh.bottom_radius = bolt_radius_m
	_material.albedo_color = emission_color
	_material.emission = emission_color


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
