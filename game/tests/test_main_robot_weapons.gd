extends RefCounted

## The main scene's robots are spawned with the weapons their data files name,
## so they shoot back, and the session's replay reproduces being shot
## (#269, CMB-2, CMB-3, ARC-4, MP-2).

const SPAWN_FILE: String = "res://data/levels/test_tunnel_robots.json"
const WEAPONS_DIR: String = "res://data/weapons"
## A scratch weapon folder with one good, one broken and the rest missing.
const PARTIAL_DIR: String = "user://test_main_robot_weapons"
const TICKS: int = 120
## Forward flight that brings the drone's wake range over the ship.
const WAKE_TICKS: int = 60


func _main_session() -> Array:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	return [main, main.get("session")]


func _robot_index(session: LocalSession, id: String) -> int:
	for index: int in session.sim.robots.size():
		if session.sim.robots[index].def.id == id:
			return index
	return -1


func test_every_main_scene_robot_carries_its_data_file_weapon() -> String:
	var parts: Array = _main_session()
	var main: Node = parts[0]
	var session: LocalSession = parts[1]
	var problem: String = ""
	for robot: RobotState in session.sim.robots:
		var expected: String = WEAPONS_DIR.path_join(robot.def.weapon + ".json")
		var want: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(expected))
		if robot.weapon == null:
			problem = "%s spawned unarmed" % robot.def.id
		elif robot.weapon.values_hash() != want.values_hash():
			problem = "%s carries a weapon other than %s" % [robot.def.id, expected]
		if problem != "":
			break
	main.free()
	if session.sim.robots.size() != 6:
		return "%d robots spawned, expected 6" % session.sim.robots.size()
	return problem


func test_the_drone_fires_at_the_ship_and_the_replay_reproduces_it() -> String:
	var parts: Array = _main_session()
	var main: Node = parts[0]
	var session: LocalSession = parts[1]
	var drone: int = _robot_index(session, "drone")
	if drone < 0:
		main.free()
		return "no drone in the main scene"
	# The ship starts about 16 m from the drone and in front of it, well
	# inside the pulse cannon's 180 m. The drone waits for the ship to come
	# within its wake range (#301), so the ship flies forward for WAKE_TICKS
	# and then lets go of the stick.
	var distance: float = session.sim.robots[drone].position.distance_to(session.sim.ships[0].position)
	var range_m: float = session.sim.robots[drone].weapon_range()
	var start_defence: float = session.sim.ships[0].shield + session.sim.ships[0].hull
	var source: LatestInputSource = main.get("input_source")
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	var fired_at: int = -1
	for tick: int in TICKS:
		if tick == WAKE_TICKS:
			source.set_input(ShipInput.new())
		session.advance(ShipState.TICK_DT)
		for projectile: Projectile in session.sim.projectiles:
			if fired_at < 0 and projectile.owner_index == Projectile.robot_owner(drone):
				fired_at = session.sim.tick
	var end_defence: float = session.sim.ships[0].shield + session.sim.ships[0].hull
	var live_hash: int = session.sim.state_hash()
	var text: String = session.replay.to_text()
	var ticks: int = session.sim.tick
	main.free()
	if distance > range_m:
		return "the ship starts %s m from the drone, out of its %s m range" % [distance, range_m]
	if ticks != TICKS:
		return "%d frames ran %d ticks" % [TICKS, ticks]
	if fired_at < 0:
		return "the drone never fired in %d ticks" % TICKS
	if end_defence >= start_defence:
		return "the robots' shots never hit the ship"
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return "the saved replay does not read back: %s" % reread.error
	for spawn: RobotSpawn in reread.robots:
		if spawn.weapon == null:
			return "the replay records %s unarmed" % spawn.id
	var replayed: Sim = reread.run()
	if replayed == null:
		return reread.run_error
	if replayed.state_hash() != live_hash:
		return "the replay ends on %d, the session on %d" % [replayed.state_hash(), live_hash]
	# Without the weapons the run must end differently, or this proves nothing.
	for spawn: RobotSpawn in reread.robots:
		spawn.weapon = null
	if reread.run().state_hash() == live_hash:
		return "the run ends the same with every robot unarmed"
	return ""


func test_a_missing_or_broken_weapon_file_disarms_only_its_robots() -> String:
	DirAccess.make_dir_recursive_absolute(PARTIAL_DIR)
	for file: String in DirAccess.get_files_at(PARTIAL_DIR):
		DirAccess.remove_absolute(PARTIAL_DIR.path_join(file))
	var good: FileAccess = FileAccess.open(PARTIAL_DIR.path_join("pulse_cannon.json"), FileAccess.WRITE)
	good.store_string(FileAccess.get_file_as_string(WEAPONS_DIR.path_join("pulse_cannon.json")))
	good.close()
	var broken: FileAccess = FileAccess.open(PARTIAL_DIR.path_join("arc_lance.json"), FileAccess.WRITE)
	broken.store_string("{\"damage\": ")
	broken.close()
	var spawns: Array[RobotSpawn] = LocalSession.load_spawns(SPAWN_FILE, LocalSession.ROBOT_DIR, PARTIAL_DIR)
	if spawns.size() != 6:
		return "%d robots loaded, expected all 6" % spawns.size()
	for spawn: RobotSpawn in spawns:
		var armed: bool = spawn.weapon != null
		if armed != (spawn.def.weapon == "pulse_cannon"):
			return "%s (fires %s) loaded %s" % [spawn.id, spawn.def.weapon, "armed" if armed else "unarmed"]
	var session: LocalSession = LocalSession.new(0, null, null, null, spawns)
	if session.sim.robots.size() != 6:
		return "the session spawned %d of 6 robots" % session.sim.robots.size()
	return ""
