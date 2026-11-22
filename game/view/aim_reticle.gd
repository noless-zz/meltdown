class_name AimReticle
extends Node3D

## The aiming reticle (CMB-6, #923, #1211): a ring, world-locked, where the
## guns point. Its direction is the simulated gun direction read back from a
## copy of the ship's state, not the head, so it shows where a shot will go
## while the gimbal is still turning, and stays inside the core's cone. That
## direction is the nose without look-aim, so the same ring serves every
## comfort preset: the owner lined up by eye on preset 4 before (#1211).
##
## A live robot within the active weapon's range and inside the look's cone
## around the aim draws the ring onto it, at its distance and full alpha, so
## the stereo depth of the ring matches the target's. Otherwise the ring floats
## at the look's distance, dimmed. It is scaled with its distance, so it keeps
## one apparent size. Only reads state (ARC-3, MP-2). The look is a data file
## (`AimReticleLook`, ARC-4).

var look: Dictionary = AimReticleLook.FALLBACK
## Whether the last `show_aim` found a robot to sit on (full alpha).
var on_target: bool = false
## The ring's distance from the ship after the last `show_aim`, in metres.
var shown_distance: float = 0.0

var _ring: MeshInstance3D = null
var _material: StandardMaterial3D = null


## With no `p_look`, the shipped look file (or its fallback).
func _init(p_look: Dictionary = {}) -> void:
	name = "AimReticle"
	look = p_look if not p_look.is_empty() else AimReticleLook.load_file()
	visible = false
	shown_distance = float(look["distance_m"])
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var torus: TorusMesh = TorusMesh.new()
	var radius: float = float(look["radius_m"])
	var thickness: float = float(look["thickness_m"])
	torus.outer_radius = radius
	torus.inner_radius = radius - thickness
	torus.rings = 32
	torus.ring_segments = 8
	_ring.mesh = torus
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawn over the walls, so the ring never hides behind a corner it aims past.
	_material.no_depth_test = true
	_material.albedo_color = dimmed_color()
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The torus lies in its xz plane; turned a quarter about x, it faces along -z.
	_ring.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	add_child(_ring)


## Places the ring for a ship at `pose` (the frame's shown pose, world space)
## whose guns point along `gun_direction` (ship space, from `ShipState`), on
## the nearest of `robots` (session copies) within `weapon_range` metres and
## the look's cone, or at the look's distance, dimmed, when there is none.
## A `weapon_range` of 0 (no weapon in the slot) never finds one.
func show_aim(pose: Transform3D, gun_direction: Vector3, robots: Array[RobotState] = [],
		weapon_range: float = 0.0) -> void:
	visible = true
	var along: Vector3 = AimReticle.aim_axis(pose, gun_direction)
	var target: float = AimReticle.target_distance(pose.origin, along, robots, weapon_range,
		float(look["cone_degrees"]))
	on_target = target > 0.0
	shown_distance = target if on_target else float(look["distance_m"])
	var at: Transform3D = AimReticle.placed(pose, gun_direction, shown_distance)
	# One apparent size at any depth: the ring is drawn for the look's distance.
	at.basis = at.basis * Basis.from_scale(Vector3.ONE * (shown_distance / float(look["distance_m"])))
	transform = at
	_material.albedo_color = look["color"] if on_target else dimmed_color()


## The look's colour with its alpha scaled by `dim_alpha`.
func dimmed_color() -> Color:
	var color: Color = look["color"]
	color.a *= float(look["dim_alpha"])
	return color


## The colour the ring is drawn in now.
func shown_color() -> Color:
	return _material.albedo_color


## The world direction of the guns for a ship at `pose`: `gun_direction`
## turned into world space, or the nose when it is zero.
static func aim_axis(pose: Transform3D, gun_direction: Vector3) -> Vector3:
	var along: Vector3 = (pose.basis.orthonormalized() * gun_direction).normalized()
	if along.is_zero_approx():
		along = pose.basis.orthonormalized() * LookAim.NOSE
	return along


## The distance from `origin` to the nearest live robot of `robots` no further
## than `weapon_range` and within `cone_degrees` of `along` (unit, world), or
## -1 when there is none.
static func target_distance(origin: Vector3, along: Vector3, robots: Array[RobotState],
		weapon_range: float, cone_degrees: float) -> float:
	var best: float = -1.0
	var limit: float = deg_to_rad(cone_degrees)
	for robot: RobotState in robots:
		if not robot.is_alive():
			continue
		var offset: Vector3 = robot.position - origin
		var length: float = offset.length()
		if length < 0.0001 or length > weapon_range or along.angle_to(offset) > limit:
			continue
		if best < 0.0 or length < best:
			best = length
	return best


## The ring's transform: `distance` metres from the ship along the guns, its
## face (-z) pointing the way the guns do and its up the ship's up.
static func placed(pose: Transform3D, gun_direction: Vector3, distance: float) -> Transform3D:
	var along: Vector3 = AimReticle.aim_axis(pose, gun_direction)
	var up: Vector3 = pose.basis.orthonormalized().y
	if absf(along.dot(up)) > 0.999:
		up = pose.basis.orthonormalized().z
	return Transform3D(Basis.looking_at(along, up), pose.origin + along * distance)
