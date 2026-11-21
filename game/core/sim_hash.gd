class_name SimHash
extends RefCounted

## Hash of a whole `Sim`, compared by replay tests and network desync checks
## (ARC-2, MP-2). Split out of `Sim` to keep that file under its size limit.
## Projectiles, robots, salvage, the part catalogue, the reactor, with the
## run's outcome, debris and components join only while there are any (for
## components and miner rescue: while their rules are set), so runs recorded before them keep
## their hashes.


static func of(sim: Sim) -> int:
	var parts: Array[int] = [sim.run_seed, sim.tick]
	for ship: ShipState in sim.ships:
		parts.append(ship.state_hash())
	if not sim.projectiles.is_empty():
		parts.append(hash("projectiles"))
		for projectile: Projectile in sim.projectiles:
			parts.append(projectile.state_hash())
	if not sim.robots.is_empty():
		parts.append(hash("robots"))
		for robot: RobotState in sim.robots:
			parts.append(robot.state_hash())
	if not sim.salvage.is_empty():
		parts.append(hash("salvage"))
		for item: SalvageItem in sim.salvage:
			parts.append(item.state_hash())
	var ids: Array[String] = sim.part_ids()
	if not ids.is_empty():
		parts.append(hash("parts"))
		for id: String in ids:
			parts.append(hash(id))
			parts.append(sim.part(id).values_hash())
	if sim.reactor != null:
		parts.append(hash("reactor"))
		parts.append(sim.reactor.state_hash())
		parts.append(ExitRule.state_hash(sim))
	if sim.debris != null:
		parts.append(sim.debris.state_hash())
	if sim.component_rules != null:
		parts.append(ComponentPickup.state_hash(sim))
	if sim.rescue != null:
		parts.append(MinerRescue.state_hash(sim))
	return hash(parts)
