class_name NodePoints
extends RefCounted
## Where one node sits in another's space, in or out of the scene tree. Moved
## out of `CombatWiring` (#1375) so that file stays under 300 lines.


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
