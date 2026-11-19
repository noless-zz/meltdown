class_name CombatWiring
extends RefCounted

## Joins the session's combat state to what the main scene shows (CMB-1,
## CMB-2, CMB-3, LGT-1, SLV-1): the projectiles, the robots (#228), the
## floating salvage (#287), the shield and hull bars, the hold row (#316), and
## the weapon row and the pickup and slot messages (#605) on the status panel.
##
## It sits beside `main.gd`, like `ComfortWiring`, because it reads the `net/`
## session, which `view/` may not depend on. It hands the view copies from
## `LocalSession` and never writes simulation state (MP-2).

## The bolts, under the world node once `attach` has run, null before.
var projectile_view: ProjectileView = null
## The robots, beside the bolts once `attach` has run, null before.
var robot_view: RobotView = null
## The floating parts, beside the robots once `attach` has run, null before.
var salvage_view: SalvageView = null
## The rings that show when a part is within reach (#600), beside the parts.
var salvage_ring: SalvageRing = null
## Says on the hold row what was just picked up or slotted (#605).
var hold_messages: HoldMessages = HoldMessages.new()


## Puts the projectile, robot and salvage views under `world`, the node whose space is
## the simulation's: both are drawn at the simulated positions as they are.
## Calling it again adds nothing.
func attach(world: Node3D) -> void:
	if projectile_view != null:
		return
	projectile_view = ProjectileView.new()
	world.add_child(projectile_view)
	robot_view = RobotView.new()
	world.add_child(robot_view)
	salvage_view = SalvageView.new()
	world.add_child(salvage_view)
	salvage_ring = SalvageRing.new()
	world.add_child(salvage_ring)


## Shows this frame's projectiles, robots and salvage, blended by the session's interpolation
## fraction like the rig. The bolts nearest `camera` get the lights (#187).
## `panel`, if given, shows the ship's shield, hull, weapon and the part in its
## hold, and what just happened to the hold.
func update(session: LocalSession, camera: Node3D, panel: StatusPanel = null) -> void:
	if panel != null:
		var ship: ShipState = session.current_ship()
		show_defence(panel, ship)
		panel.show_hold(held_part(ship))
		panel.show_weapon(active_weapon(ship))
		panel.show_hold_message(hold_messages.update(ship.hold, ship.primary_ids))
	if projectile_view == null:
		return
	if camera != null:
		projectile_view.set_viewer(point_in(projectile_view, camera))
	# The eye sits at the ship's centre, so the muzzles hang off this frame's pose.
	var pose: Transform3D = ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction)
	projectile_view.show_projectiles(session.current_projectiles(), session.interpolation_fraction,
		[pose] as Array[Transform3D])
	robot_view.show_robots(session.previous_robots(), session.current_robots(),
		session.interpolation_fraction)
	salvage_view.show_salvage(session.previous_salvage(), session.current_salvage(),
		session.interpolation_fraction)
	# The rules are fixed before the first tick; reading them writes nothing.
	salvage_ring.show_rings(session.previous_salvage(), session.current_salvage(),
		session.interpolation_fraction, session.current_ship(), session.sim.salvage_rules)


## Hands `panel` the shield and hull of `ship`, a session copy, as fractions
## of their maximums; a maximum of zero shows an empty bar.
static func show_defence(panel: StatusPanel, ship: ShipState) -> void:
	var shield: float = ship.shield / ship.max_shield if ship.max_shield > 0.0 else 0.0
	var hull: float = ship.hull / ship.max_hull if ship.max_hull > 0.0 else 0.0
	panel.show_defence(shield, hull)


## The part `ship`, a session copy, would slot next: the first id in its hold,
## or "" when the hold is empty. Weapon data files carry no display name yet,
## so the id is what the panel shows.
static func held_part(ship: ShipState) -> String:
	return ship.hold[0] if not ship.hold.is_empty() else ""


## The part id of the weapon in `ship`'s selected primary slot, or "" when
## that slot is empty. Like the hold, the id is the name shown.
static func active_weapon(ship: ShipState) -> String:
	var slot: int = ship.selected_primary
	if slot < 0 or slot >= ship.primary_slots.size() or ship.primary_slots[slot] == null:
		return ""
	return ship.primary_ids[slot] if slot < ship.primary_ids.size() else ""


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
