class_name LookAimHead
extends RefCounted

## The headset half of look-aim (CMB-6, CMB-8, decision record 0010, #923):
## while the active comfort preset has `look_aim` on, the head's forward
## direction, in ship space, becomes the aim of the player's `ShipInput`; while
## it is off the aim is the nose. Named apart from `LookAim` (core), which
## holds the cone and gimbal rate and turns the simulated guns.
##
## The aim is player input, like thrust and fire: it reaches the core only
## through `ShipInput`, which the core clamps to its cone and records in the
## replay. Nothing here writes `ShipState` or `Sim` (ARC-3, MP-2), and the cone
## and gimbal rate are the same on every preset (CMF-6).
##
## The head is the rig camera's pose in tracked space, turned into ship space
## by the `HeadRecentre` offset, the same mapping that puts the eye point at
## the ship's centre. A head that cannot be trusted (tracking lost) aims at the
## nose rather than at the last pose.
##
## A fitted look-aim module (CMB-8, #1042) keeps look-aim on at every preset,
## through any `set_preset`; without it the preset decides (record 0010). The
## flag is read from the local ship's loadout and only changes which aim this
## player's input carries, never the cone or gimbal rate.

## Whether this player aims with the head: the preset's value, or on while the
## module is fitted. `set_preset` and `set_module` keep it.
var enabled: bool = false
## Whether the local ship carries the look-aim module; set with `set_module`.
var module_fitted: bool = false
## The active preset's own look-aim value, kept so removing the module restores it.
var preset_on: bool = false
## The headset camera under the rig, tracked space; null until `attach`.
var camera: Node3D = null
## Maps tracked space to the ship; null until `attach` (identity then).
var recentre: HeadRecentre = null
## Whether the camera's pose can be trusted this frame. Tests replace it.
var head_trusted: Callable = LookAimHead.head_pose_trusted


## Takes the look-aim value of `preset`, used from the next input handed on
## (CMB-8: a preset change, mid-run too, sets look-aim to the new preset's).
## With the module fitted look-aim stays on whatever the preset says.
func set_preset(preset: ComfortPreset) -> void:
	preset_on = preset != null and preset.look_aim
	enabled = preset_on or module_fitted


## Reads the module flag from `utility_ids`, the local ship's
## `ShipLoadout.utility_ids` (read only, MP-2), from the next input handed on.
func set_module(utility_ids: Array[String]) -> void:
	module_fitted = utility_ids.has(ShipLoadout.LOOK_AIM_MODULE)
	enabled = preset_on or module_fitted


## Reads the head from `rig`'s camera, mapped to ship space by `p_recentre`.
func attach(rig: Node3D, p_recentre: HeadRecentre) -> void:
	camera = rig.get_node_or_null("Camera") as Node3D
	recentre = p_recentre


## The head's forward direction in ship space; the nose without a camera.
func head_forward() -> Vector3:
	if camera == null:
		return LookAim.NOSE
	var offset: Transform3D = recentre.offset if recentre != null else Transform3D.IDENTITY
	return LookAimHead.forward_in_ship(offset, camera.transform)


## `input` with this frame's aim: the head's forward when look-aim is on and
## the head is tracked, the nose otherwise. An input already on the nose that
## stays there is handed back as it is, so replays fly bit for bit as before.
func aimed(input: ShipInput) -> ShipInput:
	var aim_q: Vector3i = ShipInput.NOSE_AIM_Q
	if enabled and bool(head_trusted.call()):
		aim_q = ShipInput.aim_q_from(head_forward())
	if aim_q == input.aim_q:
		return input
	var out: ShipInput = ComfortInputFilter.copy_input(input)
	out.aim_q = aim_q
	return out


## Where `head` (tracked space) looks, in the ship's space given the recentre
## `offset` (tracked space relative to the ship). Godot's forward is -z.
static func forward_in_ship(offset: Transform3D, head: Transform3D) -> Vector3:
	return ((offset.basis * head.basis) * Vector3.FORWARD).normalized()


## True for the flat camera, and in an XR session while the head is tracked.
static func head_pose_trusted() -> bool:
	var xr: XRInterface = XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		return true
	return HeadRecentre.head_tracked()
