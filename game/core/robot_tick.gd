class_name RobotTick
extends RefCounted

## The robots' part of a tick (CMB-3): moving, firing and removing the
## destroyed. Kept out of `Sim` so the tick there stays short, like
## `ProjectileHits`; `Sim.step` calls `advance` after the ships and
## `remove_destroyed` last.


## Moves every robot in `sim.robots` one tick towards its target, keeps it
## inside the box of `sim.walls` picked where it ends up, and fires at its
## target if it can. The shot leaves the robot's centre along its facing at the
## weapon's speed, like a ship's.
static func advance(sim: Sim) -> void:
	for r: int in sim.robots.size():
		var robot: RobotState = sim.robots[r]
		robot.step(sim.nearest_live_ship(robot.position))
		if sim.walls != null:
			robot.keep_inside(sim.walls.box_for(robot.position, robot.def.radius))
		var weapon: WeaponDef = robot.fire_at(sim.nearest_live_ship(robot.position))
		if weapon != null:
			sim.projectiles.append(Projectile.new(robot.position,
				robot.forward() * weapon.projectile_speed, Projectile.robot_owner(r),
				weapon.lifetime_ticks(), weapon.damage))


## Removes robots whose hull reached zero this tick, keeping the order of
## the rest, so robot indices stay in spawn order. Each leaves its salvage, in
## robot order, with a SALVAGE_DROPPED event after the tick's other events,
## credited to the ship `killers` names (robot index to ship index).
static func remove_destroyed(sim: Sim, killers: Dictionary) -> void:
	var kept: Array[RobotState] = []
	for r: int in sim.robots.size():
		var robot: RobotState = sim.robots[r]
		if robot.is_alive():
			kept.append(robot)
			continue
		var item: SalvageItem = SalvageItem.dropped_by(robot)
		if item != null:
			sim.salvage.append(item)
			sim.last_events.append(SimEvent.new(SimEvent.Kind.SALVAGE_DROPPED,
				killers.get(r, 0), sim.salvage.size() - 1, item.position))
	sim.robots = kept
