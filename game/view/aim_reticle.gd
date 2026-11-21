class_name AimReticle
extends Node3D

## The look-aim reticle (CMB-6, #923): a ring, world-locked, where the guns
## point. Its direction is the simulated gun direction read back from a copy
## of the ship's state, not the head, so it shows where a shot will go while
## the gimbal is still turning, and stays inside the core's cone. Drawn only
## while look-aim is on; with it off the guns stay on the nose and the cockpit
## needs no marker. Only reads state (ARC-3, MP-2). The look is a data file
## (`AimReticleLook`, ARC-4).

var look: Dictionary = AimReticleLook.FALLBACK

var _ring: MeshInstance3D = null


## With no `p_look`, the shipped look file (or its fallback).
func _init(p_look: Dictionary = {}) -> void:
	name = "AimReticle"
	look = p_look if not p_look.is_empty() else AimReticleLook.load_file()
	visible = false
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
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawn over the walls, so the ring never hides behind a corner it aims past.
	material.no_depth_test = true
	material.albedo_color = look["color"]
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The torus lies in its xz plane; turned a quarter about x, it faces along -z.
	_ring.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	add_child(_ring)


## Places the ring for a ship at `pose` (the frame's shown pose, world space)
## whose guns point along `gun_direction` (ship space, from `ShipState`), and
## shows it only while `shown`.
func show_aim(pose: Transform3D, gun_direction: Vector3, shown: bool) -> void:
	visible = shown
	if shown:
		transform = AimReticle.placed(pose, gun_direction, float(look["distance_m"]))


## The ring's transform: `distance` metres from the ship along the guns, its
## face (-z) pointing the way the guns do and its up the ship's up.
static func placed(pose: Transform3D, gun_direction: Vector3, distance: float) -> Transform3D:
	var along: Vector3 = (pose.basis.orthonormalized() * gun_direction).normalized()
	if along.is_zero_approx():
		along = pose.basis.orthonormalized() * LookAim.NOSE
	var up: Vector3 = pose.basis.orthonormalized().y
	if absf(along.dot(up)) > 0.999:
		up = pose.basis.orthonormalized().z
	return Transform3D(Basis.looking_at(along, up), pose.origin + along * distance)
