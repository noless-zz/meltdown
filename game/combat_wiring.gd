class_name CombatWiring
extends RefCounted

## Joins the session's combat state to what the main scene shows (CMB-1,
## CMB-2, CMB-3, LGT-1, SLV-1): the projectiles, the robots (#228), the
## floating salvage (#287), the component heaps and trapped miners (#1034), the shield and hull bars, the hold row (#316), and
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
## The component heaps (#1034), beside the parts once `attach` has run.
var component_view: ComponentView = null
## The trapped miners and their rescue rings (#1034), beside the heaps.
var miner_view: MinerView = null
## Says on the hold row what was just picked up or slotted (#605).
var hold_messages: HoldMessages = HoldMessages.new()
## The hit cue on every preset (#618): which side and bar flash. Null when its
## file was rejected; the pulses still go.
var hit_flash: HitFlash = load_hit_flash(HitFlash.DEFAULT_FILE)
## The hit and pickup pulses; the hands are found by `attach`.
var hit_haptics: HitHaptics = HitHaptics.load_shipped()
## The edge strips under the rig's camera, once `attach` found one.
var hit_overlay: HitFlashOverlay = null
## Where the guns point, on every preset (#923, #1211), beside the bolts once `attach` has run.
var aim_reticle: AimReticle = null


## Puts the projectile, robot and salvage views under `world`, the node whose space is
## the simulation's: both are drawn at the simulated positions as they are.
## The hit cue finds the rig's hands and camera under `world`, as the main
## scene names them. Calling it again adds nothing.
func attach(world: Node3D) -> void:
	if projectile_view != null:
		return
	hit_haptics.left_controller = world.get_node_or_null("XRRig/LeftHand") as XRController3D
	hit_haptics.right_controller = world.get_node_or_null("XRRig/RightHand") as XRController3D
	var camera: Node3D = world.get_node_or_null("XRRig/Camera") as Node3D
	if camera != null and hit_flash != null:
		hit_overlay = HitFlashOverlay.new(hit_flash)
		camera.add_child(hit_overlay)
	projectile_view = ProjectileView.new()
	world.add_child(projectile_view)
	robot_view = RobotView.new()
	world.add_child(robot_view)
	salvage_view = SalvageView.new()
	world.add_child(salvage_view)
	salvage_ring = SalvageRing.new()
	world.add_child(salvage_ring)
	component_view = ComponentView.new()
	world.add_child(component_view)
	miner_view = MinerView.new()
	world.add_child(miner_view)
	aim_reticle = AimReticle.new()
	world.add_child(aim_reticle)


## Shows this frame's projectiles, robots and salvage, blended by the session's interpolation
## fraction like the rig. The bolts nearest `camera` get the lights (#187).
## `panel`, if given, shows the ship's shield, hull, weapon and the part in its
## hold, and what just happened to the hold. The hit flashes run by `delta`.
## The aim reticle shows along the ship's gun direction on every preset
## (#1211), so `_look_aim` no longer changes anything; `main.gd` still passes it.
func update(session: LocalSession, camera: Node3D, panel: StatusPanel = null, delta: float = 0.0,
		_look_aim: bool = false) -> void:
	show_hit_flash(delta)
	if panel != null:
		var ship: ShipState = session.current_ship()
		show_defence(panel, ship)
		if hit_flash != null:
			panel.flash_bar(false, hit_flash.bar_color, hit_flash.bar_amount(HitFlash.SHIELD))
			panel.flash_bar(true, hit_flash.bar_color, hit_flash.bar_amount(HitFlash.HULL))
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
	aim_reticle.show_aim(pose, session.current_ship().gun_direction, session.current_robots(),
		weapon_range(session.current_ship()))
	robot_view.show_robots(session.previous_robots(), session.current_robots(),
		session.interpolation_fraction)
	salvage_view.show_salvage(session.previous_salvage(), session.current_salvage(),
		session.interpolation_fraction)
	# The rules are fixed before the first tick; reading them writes nothing.
	salvage_ring.show_rings(session.previous_salvage(), session.current_salvage(),
		session.interpolation_fraction, session.current_ship(), session.sim.salvage_rules)
	# Heaps and miners do not move; the views read the sim's lists and write nothing.
	component_view.show_heaps(session.sim)
	miner_view.show_miners(session.sim.rescue, session.current_ship(), session.sim.walls, delta)


## Takes in the events of one session advance and `ship`, the local ship (0)
## after it, a session copy (#618). Every shot that hit it starts the flash on
## its side and pulses that side's hand; every part it picked up pulses both.
## The strongest wall impact of the advance pulses the hand on that wall's side
## (#828), so a corner hit reported twice is still one pulse.
## Call it after every advance, so a frame split for a snap loses no event.
func feed_events(events: Array[SimEvent], ship: ShipState, xr_running: bool) -> void:
	if hit_flash != null:
		for side: String in hit_flash.feed(events, 0, ship.orientation, ship.shield, ship.hull):
			hit_haptics.hit(side, xr_running)
	else:
		for event: SimEvent in events:
			if event.ship == 0 and event.kind == SimEvent.Kind.SHIP_HIT:
				hit_haptics.hit(HitFlash.side_for(event.vector, ship.orientation), xr_running)
	for event: SimEvent in events:
		if event.ship == 0 and event.kind == SimEvent.Kind.SALVAGE_COLLECTED:
			hit_haptics.pickup(xr_running)
	var strongest: SimEvent = null
	for event: SimEvent in events:
		if event.ship == 0 and event.kind == SimEvent.Kind.WALL_IMPACT \
				and (strongest == null or event.magnitude > strongest.magnitude):
			strongest = event
	if strongest != null:
		# The normal points back into the tunnel, as a shot from the wall would fly.
		hit_haptics.wall(HitFlash.side_for(strongest.vector, ship.orientation),
			strongest.magnitude, xr_running)


## Runs the hit flash by `delta` and shows its edge on the overlay.
func show_hit_flash(delta: float) -> void:
	if hit_flash == null:
		return
	hit_flash.advance(delta)
	if hit_overlay != null:
		hit_overlay.show_flash(hit_flash.side, hit_flash.edge_opacity(), hit_flash.edge_color)


## Reads the hit-flash file at `path`. A rejected file is printed once and
## gives null, so no edge or bar flashes rather than one with guessed values.
static func load_hit_flash(path: String) -> HitFlash:
	var flash: HitFlash = HitFlash.load_file(path)
	if flash.error != "":
		print("Meltdown: hit flash off: %s" % flash.error)
		return null
	return flash


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


## How far a shot from `ship`'s selected primary weapon flies, in metres:
## its speed times its lifetime, or 0 when the slot is empty.
static func weapon_range(ship: ShipState) -> float:
	var slot: int = ship.selected_primary
	if slot < 0 or slot >= ship.primary_slots.size() or ship.primary_slots[slot] == null:
		return 0.0
	var weapon: WeaponDef = ship.primary_slots[slot]
	return weapon.projectile_speed * weapon.lifetime


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
