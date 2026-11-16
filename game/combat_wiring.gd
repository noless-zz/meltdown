class_name CombatWiring
extends RefCounted

## Joins the session's combat state to what the main scene draws (CMB-1,
## LGT-1): for now the projectiles, later the robots (#228).
##
## It sits beside `main.gd`, like `ComfortWiring`, because it reads the `net/`
## session, which `view/` may not depend on. It hands the view copies from
## `LocalSession` and never writes simulation state (MP-2).

## The bolts, under the world node once `attach` has run, null before.
var projectile_view: ProjectileView = null


## Puts the projectile view under `world`, the node whose space is the
## simulation's: the bolts are drawn at the simulated positions as they are.
## Calling it again adds nothing.
func attach(world: Node3D) -> void:
	if projectile_view != null:
		return
	projectile_view = ProjectileView.new()
	world.add_child(projectile_view)


## Shows this frame's projectiles, blended by the session's interpolation
## fraction like the rig. The bolts nearest `camera` get the lights (#187).
func update(session: LocalSession, camera: Node3D) -> void:
	if projectile_view == null:
		return
	if camera != null:
		projectile_view.set_viewer(point_in(projectile_view, camera))
	projectile_view.show_projectiles(session.current_projectiles(), session.interpolation_fraction)


## Where `node` is, in `space`'s coordinates: its global position seen from
## `space`. Outside the scene tree (tests, the first frame) global transforms
## cannot be read, so the parents' transforms are multiplied up instead.
static func point_in(space: Node3D, node: Node3D) -> Vector3:
	if space.is_inside_tree() and node.is_inside_tree():
		return space.to_local(node.global_position)
	return _to_top(space).affine_inverse() * _to_top(node).origin


## `node`'s transform in the space of its topmost 3D ancestor.
static func _to_top(node: Node3D) -> Transform3D:
	var total: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current is Node3D:
		total = (current as Node3D).transform * total
		current = current.get_parent()
	return total
