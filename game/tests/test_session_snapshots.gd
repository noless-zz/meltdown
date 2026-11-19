extends RefCounted

## The snapshot helpers moved out of `LocalSession` still hand the view copies,
## never the simulation's own objects (#296, MP-2).

const ROBOT_FILE: String = "res://data/robots/drone.json"


func test_ship_is_a_copy() -> String:
	var source: ShipState = ShipState.new()
	source.position = Vector3(1.0, 2.0, 3.0)
	var copy: ShipState = SessionSnapshots.ship(source)
	if copy == source:
		return "ship() returned the simulation's ship"
	if copy.position != source.position:
		return "the copy is at %s, the ship at %s" % [copy.position, source.position]
	copy.position = Vector3.ZERO
	if source.position != Vector3(1.0, 2.0, 3.0):
		return "writing to the copy moved the ship"
	return ""


func test_projectiles_are_copies_kept_across_ticks() -> String:
	var first: Projectile = Projectile.new(Vector3(0.0, 0.0, -1.0))
	var second: Projectile = Projectile.new(Vector3(0.0, 0.0, -2.0))
	var source: Array[Projectile] = [first, second]
	var empty: Dictionary[Projectile, Projectile] = {}
	var copies: Dictionary[Projectile, Projectile] = SessionSnapshots.projectiles(source, empty)
	if copies.size() != 2:
		return "%d copies for 2 projectiles" % copies.size()
	for projectile: Projectile in source:
		if copies[projectile] == projectile:
			return "projectiles() returned the simulation's projectile"
		if copies[projectile].position != projectile.position:
			return "a copy is at %s, its projectile at %s" % [copies[projectile].position, projectile.position]
	if copies.keys() != [first, second]:
		return "the copies are not in the simulation's order"
	var kept: Projectile = copies[second]
	second.position = Vector3(0.0, 0.0, -3.0)
	var later: Array[Projectile] = [second]
	var next: Dictionary[Projectile, Projectile] = SessionSnapshots.projectiles(later, copies)
	if next.size() != 1 or next.has(first):
		return "the removed projectile's copy was kept"
	if next[second] != kept:
		return "a live projectile got a new copy"
	if kept.position != Vector3(0.0, 0.0, -3.0):
		return "the kept copy was not refreshed"
	return ""


func test_robots_are_copies_sharing_the_type() -> String:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(ROBOT_FILE))
	if def.error != "":
		return "drone.json rejected: %s" % def.error
	var robot: RobotState = RobotState.new(def, Vector3(4.0, 0.0, -10.0))
	var source: Array[RobotState] = [robot]
	var copies: Array[RobotState] = SessionSnapshots.robots(source)
	if copies.size() != 1 or copies[0] == robot:
		return "robots() did not return one new copy"
	if copies[0].def != def:
		return "the copy does not share the robot's type"
	copies[0].hull = -1.0
	if robot.hull == -1.0:
		return "writing to the copy changed the robot"
	return ""


func test_salvage_is_copied() -> String:
	var item: SalvageItem = SalvageItem.new("pulse_cannon", Vector3(1.0, 1.0, 1.0))
	var source: Array[SalvageItem] = [item]
	var copies: Array[SalvageItem] = SessionSnapshots.salvage(source)
	if copies.size() != 1 or copies[0] == item:
		return "salvage() did not return one new copy"
	if copies[0].part_id != "pulse_cannon" or copies[0].position != item.position:
		return "the copy differs from the part"
	copies[0].position = Vector3.ZERO
	if item.position != Vector3(1.0, 1.0, 1.0):
		return "writing to the copy moved the part"
	return ""


func test_session_still_hands_out_copies() -> String:
	var session: LocalSession = LocalSession.new(0, null, null,
			LocalSession.load_tuning("res://data/ships/default_ship.json"))
	session.advance(1.0 / 60.0)
	if session.current_ship() == session.sim.ships[0]:
		return "current_ship() is the simulation's ship"
	if session.current_robots().size() != session.sim.robots.size():
		return "current_robots() lists %d robots for %d" % [
			session.current_robots().size(), session.sim.robots.size()]
	return ""


func test_session_forwards_the_data_paths() -> String:
	if LocalSession.WEAPON_DIR != SpawnLoader.WEAPON_DIR or LocalSession.ROBOT_DIR != SpawnLoader.ROBOT_DIR:
		return "LocalSession's data folders differ from SpawnLoader's"
	return ""
