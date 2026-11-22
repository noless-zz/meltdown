class_name ProjectileView
extends Node3D

## Draws the simulation's projectiles as glowing bolts (CMB-1). Mines are dark
## and weapons are a main light source (LGT-1), so bolts are unshaded and
## emissive. It only reads the projectiles it is given, so the view cannot
## change what the authoritative simulation decided (MP-2). Bolts are pooled,
## so a burst of fire reuses hidden nodes.
##
## The bolts nearest the viewer carry real lights from a budgeted pool
## (`BoltLights`, PRF-1). A ship's bolts are drawn from its muzzles
## (`BoltMuzzles`, #602) with a flash there, and a bolt that ends on something
## gets an impact flash (`BoltFlashes`). The look lives in
## `res://view/projectile_look.json` (`ProjectileLook`) so the owner can change it.

const NODE_NAME: String = "ProjectileView"
const BOLT_PREFIX: String = "Bolt"
const LIGHT_PREFIX: String = BoltLights.LIGHT_PREFIX
const DEFAULT_LOOK_FILE: String = ProjectileLook.DEFAULT_FILE
const MUZZLE_FLASHES_NAME: String = "MuzzleFlashes"
const IMPACT_FLASHES_NAME: String = "ImpactFlashes"
## A robot's bolt ending this close to a ship (radius 1 m, plus room for its
## move) hit the pilot, whose hit the cockpit shake shows: no flash in the face.
const SHIP_HIT_RADIUS_M: float = 1.5

# The fields below, `muzzles` and the two flash pools are set from the look
# file; see `ProjectileLook` for each key's meaning and range.
var bolt_length_m: float = ProjectileLook.DEFAULTS["bolt_length_m"]
var bolt_radius_m: float = ProjectileLook.DEFAULTS["bolt_radius_m"]
var emission_color: Color = ProjectileLook.DEFAULTS["emission_color"]
## Most bolts that carry a light at once; 0 turns the lights off.
var max_lights: int = ProjectileLook.DEFAULTS["max_lights"]
var light_range: float = ProjectileLook.DEFAULTS["light_range"]
## Brightness of each bolt light. The light uses `emission_color`.
var light_energy: float = ProjectileLook.DEFAULTS["light_energy"]
## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Flashes at the muzzles, riding on the ship.
var muzzle_flashes: BoltFlashes = BoltFlashes.new(MUZZLE_FLASHES_NAME)
## Flashes where a bolt ended on something before its range ran out.
var impact_flashes: BoltFlashes = BoltFlashes.new(IMPACT_FLASHES_NAME)

var _bolts: Array[MeshInstance3D] = []
var _lamps: BoltLights = null
## Each projectile shown on the last call, with the position it had when it
## was first shown. Holding it keeps its identity from being reused meanwhile.
var _first_seen: Dictionary[Projectile, Vector3] = {}
## Each ship bolt's muzzle offset from the simulated line, in this node's
## space, fixed when it was first shown; zero for robot bolts.
var _offsets: Dictionary[Projectile, Vector3] = {}
## The muzzles ship bolts are drawn from, shaped by the look file.
var muzzles: BoltMuzzles = BoltMuzzles.new()
var _mesh: CylinderMesh = CylinderMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _init() -> void:
	name = NODE_NAME
	_lamps = BoltLights.new(self)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	# One draw call's worth of geometry per bolt; it is small and fast.
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_mesh.material = _material
	add_child(muzzle_flashes)
	add_child(impact_flashes)
	load_look()


## Parses the text of a look file; see `ProjectileLook.parse`.
static func parse_look(text: String) -> Dictionary:
	return ProjectileLook.parse(text)


## Applies the look file at `path`. A missing or rejected file leaves the default
## look, sets `look_error` (returned) and pushes a warning naming the field.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = ProjectileLook.parse(FileAccess.get_file_as_string(path))
	look_error = ""
	var look: Dictionary = values
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("ProjectileView uses the default look; %s" % look_error)
		look = ProjectileLook.DEFAULTS
	for key: String in ["bolt_length_m", "bolt_radius_m", "emission_color", "max_lights",
			"light_range", "light_energy"]:
		set(key, look[key])
	muzzles.set_look(look)
	muzzle_flashes.set_look(look["muzzle_flash_radius_m"], look["muzzle_flash_s"], emission_color)
	impact_flashes.set_look(look["impact_flash_radius_m"], look["impact_flash_s"], look["impact_color"])
	_apply_look()
	return look_error


## Draws one bolt per projectile, `alpha` (0..1) of the way from the previous
## tick to the current one; one fired this tick, not yet moved, is drawn where
## it is. Never writes to `projectiles` (MP-2). `ship_poses[i]`, when given, is
## ship `i`'s pose (eye at its origin): its bolts start at its muzzles, left and
## right in turn, and close onto the simulated line within `converge_m` (#602).
## A bolt that vanishes with range left ended on something: an impact flash.
func show_projectiles(projectiles: Array[Projectile], alpha: float,
		ship_poses: Array[Transform3D] = []) -> void:
	var blend: float = clampf(alpha, 0.0, 1.0)
	while _bolts.size() < projectiles.size():
		_add_bolt()
	var seen: Dictionary[Projectile, Vector3] = {}
	var offsets: Dictionary[Projectile, Vector3] = {}
	var positions: Array[Vector3] = []
	var shown: Array[bool] = []
	for index: int in projectiles.size():
		var projectile: Projectile = projectiles[index]
		var bolt: MeshInstance3D = _bolts[index]
		shown.append(projectile != null)
		if projectile == null:
			bolt.visible = false
			positions.append(bolt.position)
			continue
		var first_position: Vector3 = _first_seen.get(projectile, projectile.position)
		seen[projectile] = first_position
		offsets[projectile] = _offsets[projectile] if _offsets.has(projectile) \
			else _new_bolt_offset(projectile, ship_poses)
		var drawn: Vector3 = projectile.position
		if first_position != projectile.position:
			drawn += projectile.velocity * ShipState.TICK_DT * (blend - 1.0)
		drawn += offsets[projectile] * muzzles.weight(drawn.distance_to(first_position))
		bolt.transform = Transform3D(bolt_basis(projectile.velocity), drawn)
		bolt.visible = true
		positions.append(drawn)
	for index: int in range(projectiles.size(), _bolts.size()):
		_bolts[index].visible = false
	for gone: Projectile in _first_seen:
		if not seen.has(gone):
			_on_bolt_gone(gone, ship_poses)
	_first_seen = seen
	_offsets = offsets
	muzzle_flashes.follow(ship_poses)
	_lamps.light_nearest(positions, shown, max_lights, light_range, light_energy, emission_color)


## Where the camera is, in this node's space; the bolts nearest to it get the
## lights on the next `show_projectiles`.
func set_viewer(at: Vector3) -> void:
	_lamps.viewer = at


## Indices of the bolts carrying a light, nearest to the viewer first.
func lit_bolts() -> Array[int]:
	return _lamps.lit_bolts()


## Number of light nodes in the pool, lit or hidden.
func light_count() -> int:
	return _lamps.count()


## The pooled light at `index`, for tests.
func light(index: int) -> OmniLight3D:
	return _lamps.light(index)


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
	_lamps.apply_look(max_lights, light_range, light_energy, emission_color)
	_mesh.height = bolt_length_m
	_mesh.top_radius = bolt_radius_m
	_mesh.bottom_radius = bolt_radius_m
	_material.albedo_color = emission_color
	_material.emission = emission_color


## The muzzle offset of a bolt shown for the first time: the next muzzle of
## the ship that fired it, turned by that ship's pose, or none. Starts that
## muzzle's flash.
func _new_bolt_offset(projectile: Projectile, ship_poses: Array[Transform3D]) -> Vector3:
	var ship: int = projectile.owner_index
	if projectile.is_robot_owned() or ship >= ship_poses.size():
		return Vector3.ZERO
	var local: Vector3 = muzzles.take(ship)
	muzzle_flashes.flash(ship_poses[ship] * local, ship, local)
	return ship_poses[ship].basis * local


## A bolt shown last call is gone. With a tick of range left it ended on a
## robot, the reactor, debris or a wall, somewhere along that tick, so the flash
## goes half a tick on. A robot's bolt that ends on a ship gets no flash.
func _on_bolt_gone(gone: Projectile, ship_poses: Array[Transform3D]) -> void:
	if gone.ticks_left <= 1:
		return  # Its range ran out in open space.
	var step: Vector3 = gone.velocity * ShipState.TICK_DT
	if gone.is_robot_owned():
		for pose: Transform3D in ship_poses:
			if Projectile.segment_entry(gone.position, gone.position + step, pose.origin,
					SHIP_HIT_RADIUS_M) >= 0.0:
				return
	impact_flashes.flash(gone.position + step * 0.5)
