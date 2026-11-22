class_name BoltLights
extends RefCounted

## The pooled lights that the bolts nearest the viewer carry (LGT-1, CMB-1),
## moved out of `ProjectileView` (#1160) so lighting can grow in M6 apart from
## drawing bolts. Weapons are one of the main light sources in a dark mine, but
## the lights have a fixed budget and are pooled, so a burst of fire cannot blow
## the Quest 3 frame budget (PRF-1).
##
## The light nodes are children of `host` (the projectile view), so the scene
## tree is as it was before the move. Pure view: it reads bolt positions and
## writes nothing back to the simulation (MP-2).

const LIGHT_PREFIX: String = "BoltLight"

## Where the camera is, in the host's space; the bolts nearest to it get lights.
var viewer: Vector3 = Vector3.ZERO

var _host: Node3D = null
var _lights: Array[OmniLight3D] = []
## Bolt index each pooled light sits on, in light order; -1 when unused.
var _lit: Array[int] = []


func _init(host: Node3D) -> void:
	_host = host


## Indices into `positions` of the at most `budget` shown entries nearest to
## `from`, nearest first. Equal distances keep the order of `positions`, so
## the choice is the same for the same input.
static func nearest(from: Vector3, positions: Array[Vector3], shown: Array[bool],
		budget: int) -> Array[int]:
	var chosen: Array[int] = []
	var distances: Array[float] = []
	for index: int in positions.size():
		if not shown[index]:
			continue
		var distance: float = from.distance_squared_to(positions[index])
		var slot: int = distances.size()
		# Strictly nearer only, so an equal distance stays behind earlier bolts.
		while slot > 0 and distance < distances[slot - 1]:
			slot -= 1
		if slot >= budget:
			continue  # Also skips every bolt when the budget is 0.
		chosen.insert(slot, index)
		distances.insert(slot, distance)
		if chosen.size() > budget:
			chosen.pop_back()
			distances.pop_back()
	return chosen


## Puts the lights on the `budget` shown bolts nearest `viewer`, adding pooled
## lights styled with `light_range`, `energy` and `color` as needed, and hides
## the rest.
func light_nearest(positions: Array[Vector3], shown: Array[bool], budget: int,
		light_range: float, energy: float, color: Color) -> void:
	var chosen: Array[int] = nearest(viewer, positions, shown, budget)
	while _lights.size() < chosen.size():
		_add_light(light_range, energy, color)
	_lit.resize(_lights.size())
	for slot: int in _lights.size():
		var lamp: OmniLight3D = _lights[slot]
		if slot < chosen.size():
			_lit[slot] = chosen[slot]
			lamp.position = positions[chosen[slot]]
			lamp.visible = true
		else:
			_lit[slot] = -1
			lamp.visible = false


## Frees the lights above `budget`, so no more than that many light nodes ever
## exist, and restyles the rest.
func apply_look(budget: int, light_range: float, energy: float, color: Color) -> void:
	while _lights.size() > budget:
		var lamp: OmniLight3D = _lights.pop_back()
		_host.remove_child(lamp)
		lamp.free()
	_lit.resize(_lights.size())
	for lamp: OmniLight3D in _lights:
		_style(lamp, light_range, energy, color)


## Indices of the bolts carrying a light, nearest to the viewer first.
func lit_bolts() -> Array[int]:
	var lit: Array[int] = []
	for index: int in _lit:
		if index >= 0:
			lit.append(index)
	return lit


## Number of light nodes in the pool, lit or hidden.
func count() -> int:
	return _lights.size()


## The pooled light at `index`.
func light(index: int) -> OmniLight3D:
	return _lights[index]


func _add_light(light_range: float, energy: float, color: Color) -> void:
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "%s%d" % [LIGHT_PREFIX, _lights.size()]
	lamp.shadow_enabled = false
	lamp.visible = false
	_style(lamp, light_range, energy, color)
	_host.add_child(lamp)
	_lights.append(lamp)


static func _style(lamp: OmniLight3D, light_range: float, energy: float, color: Color) -> void:
	lamp.omni_range = light_range
	lamp.light_energy = energy
	lamp.light_color = color
