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
## A ship's bolts are drawn from its muzzles, not its centre where the eye is
## (`BoltMuzzles`, #602), with a flash there; a bolt that ends on something
## gets an impact flash (`BoltFlashes`).
##
## The look is a guess for the headset and lives in
## `res://view/projectile_look.json` (`ProjectileLook`) so the owner can change it.

const NODE_NAME: String = "ProjectileView"
const BOLT_PREFIX: String = "Bolt"
const LIGHT_PREFIX: String = "BoltLight"
const DEFAULT_LOOK_FILE: String = ProjectileLook.DEFAULT_FILE
const MUZZLE_FLASHES_NAME: String = "MuzzleFlashes"
const IMPACT_FLASHES_NAME: String = "ImpactFlashes"
## A robot's bolt that ends this close to a ship hit the ship, not a wall: the
## ship's radius (1 m) with some room for the ship having moved. Its impact is
## the pilot's own hit, shown by the cockpit shake, so it gets no flash in the
## pilot's face.
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
var _lights: Array[OmniLight3D] = []
## Bolt index each pooled light sits on, in light order; -1 when unused.
var _lit: Array[int] = []
var _viewer: Vector3 = Vector3.ZERO
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


## Applies the look file at `path`. A missing or rejected file leaves the
## default look, sets `look_error` and pushes a warning naming the field.
## Returns `look_error`.
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
## tick to the current one. A projectile that has not moved since it was first
## shown was fired on the current tick and has no previous position, so it is
## drawn where it is. Never writes to `projectiles` (MP-2).
##
## `ship_poses[i]`, when given, is ship `i`'s pose this frame, with the eye at
## its origin. A bolt that ship fires is drawn from its muzzles, left and right
## in turn, and closes onto the simulated line within `converge_m` (#602); the
## simulation still fires from the ship's centre. A bolt that vanishes with
## range left ended on something and gets an impact flash.
func show_projectiles(projectiles: Array[Projectile], alpha: float,
		ship_poses: Array[Transform3D] = []) -> void:
	var blend: float = clampf(alpha, 0.0, 1.0)
	while _bolts.size() < projectiles.size():
		_add_bolt()
	var seen: Dictionary[Projectile, Vector3] = {}
	var offsets: Dictionary[Projectile, Vector3] = {}
	for index: int in projectiles.size():
		var projectile: Projectile = projectiles[index]
		var bolt: MeshInstance3D = _bolts[index]
		if projectile == null:
			bolt.visible = false
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
	for index: int in range(projectiles.size(), _bolts.size()):
		_bolts[index].visible = false
	for gone: Projectile in _first_seen:
		if not seen.has(gone):
			_on_bolt_gone(gone, ship_poses)
	_first_seen = seen
	_offsets = offsets
	muzzle_flashes.follow(ship_poses)
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


## A bolt shown last call is gone. With a tick of range left it ended on
## something: a robot, the reactor, debris or a wall. The simulation does not
## say where along that tick, so the flash goes half a tick on from where it
## was last seen. A robot's bolt that ends on a ship gets no flash.
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
