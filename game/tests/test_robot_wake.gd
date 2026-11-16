extends RefCounted

## Robots with a wake range wait idle until a ship comes near or hits them,
## then stay awake; robots without one behave exactly as before
## (#301, CMB-2, CMB-3, ARC-2, ARC-4).

const NEEDLER: String = "res://data/robots/needler.json"
const NEEDLE_GUN: String = "res://data/weapons/needle_gun.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const SPAWN_FILE: String = "res://data/levels/test_tunnel_robots.json"
## A robot turned half a turn about the vertical faces +Z, towards a ship
## sitting at the origin when the robot is further along -Z.
const FACING_PLUS_Z: Basis = Basis(Vector3.UP, PI)
const WAKE_M: float = 10.0
## Further from the origin than WAKE_M, well inside the needle gun's range.
const ROBOT_AT: Vector3 = Vector3(0.0, 0.0, -15.0)


func _needler(wake_range: float = WAKE_M) -> RobotDef:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(NEEDLER))
	if wake_range > 0.0:
		def.set_wake_range(wake_range)
	return def


func _weapon(path: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(path))


## One ship at rest at the origin, facing -Z towards the robot, and one armed
## needler at ROBOT_AT facing the ship.
func _sim(def: RobotDef) -> Sim:
	var sim: Sim = Sim.new(4, 1)
	sim.spawn_robot(def, ROBOT_AT, FACING_PLUS_Z, _weapon(NEEDLE_GUN))
	return sim


func _step(sim: Sim, fire: bool = false) -> void:
	var inputs: Array[ShipInput] = [ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, fire)]
	sim.step(inputs)


func _robot_shots(sim: Sim) -> int:
	var count: int = 0
	for projectile: Projectile in sim.projectiles:
		if projectile.is_robot_owned():
			count += 1
	return count


func test_a_robot_with_a_wake_range_stays_idle_while_the_ship_is_out_of_range() -> String:
	var sim: Sim = _sim(_needler())
	var robot: RobotState = sim.robots[0]
	if robot.awake:
		return "spawned awake"
	var orientation: Basis = robot.orientation
	for tick: int in 300:
		_step(sim)
		if _robot_shots(sim) > 0:
			return "fired at tick %d while asleep" % sim.tick
	if robot.awake:
		return "woke with the ship %s m away" % robot.position.distance_to(sim.ships[0].position)
	if robot.position != ROBOT_AT or robot.velocity != Vector3.ZERO or robot.orientation != orientation:
		return "moved while asleep: %s" % str(robot.position)
	if sim.ships[0].shield != sim.ships[0].max_shield:
		return "the ship took damage"
	return ""


func test_the_ship_coming_within_range_wakes_it_and_it_stays_awake() -> String:
	var sim: Sim = _sim(_needler())
	var robot: RobotState = sim.robots[0]
	# Just outside, then just inside: the edge is inclusive.
	sim.ships[0].position = ROBOT_AT + Vector3(0.0, 0.0, WAKE_M + 0.01)
	_step(sim)
	if robot.awake:
		return "woke 1 cm outside its range"
	sim.ships[0].position = ROBOT_AT + Vector3(0.0, 0.0, WAKE_M)
	sim.ships[0].velocity = Vector3.ZERO
	_step(sim)
	if not robot.awake:
		return "did not wake with the ship on its range"
	# Back to the start, far out of range: the needler stays awake and chases.
	sim.ships[0].position = Vector3.ZERO
	sim.ships[0].velocity = Vector3.ZERO
	var fired: bool = false
	for tick: int in 60:
		_step(sim)
		fired = fired or _robot_shots(sim) > 0
	if not robot.awake:
		return "fell asleep again"
	if robot.position.distance_to(ROBOT_AT) < 1.0:
		return "awake but did not chase: %s" % str(robot.position)
	if not fired:
		return "awake but never fired"
	return ""


func test_a_hit_wakes_it() -> String:
	var sim: Sim = _sim(_needler())
	sim.ships[0].primary_slots[0] = _weapon(PULSE_CANNON)
	var robot: RobotState = sim.robots[0]
	_step(sim, true)
	for tick: int in 10:
		if robot.hull < robot.def.hull:
			break
		_step(sim)
	if robot.hull >= robot.def.hull:
		return "the ship's shot never hit"
	if not robot.awake:
		return "hit but still asleep"
	_step(sim)
	if robot.position == ROBOT_AT:
		return "woken by the hit but did not move"
	return ""


func test_without_a_wake_range_a_robot_is_awake_from_tick_0() -> String:
	var sim: Sim = _sim(_needler(0.0))
	if not sim.robots[0].awake:
		return "spawned asleep"
	_step(sim)
	if sim.robots[0].position == ROBOT_AT:
		return "did not move on the first tick"
	return ""


func test_the_awake_flag_joins_the_hash_only_with_a_wake_range() -> String:
	var plain: RobotState = RobotState.new(_needler(0.0), ROBOT_AT)
	var before: int = plain.state_hash()
	plain.awake = false
	if plain.state_hash() != before:
		return "the flag changed the hash of a robot without a wake range"
	var waking: RobotState = RobotState.new(_needler(), ROBOT_AT)
	var asleep: int = waking.state_hash()
	waking.awake = true
	if waking.state_hash() == asleep:
		return "waking left the hash unchanged"
	return ""


func test_values_hash_without_a_wake_range_is_unchanged() -> String:
	var def: RobotDef = _needler(0.0)
	var old: int = hash([def.id, def.hull, def.radius, def.max_speed, def.acceleration,
		def.turn_rate, def.movement, def.weapon, def.salvage, def.standoff_radii,
		def.strafe_min_distance, def.strafe_max_distance, def.strafe_radial_gain])
	if def.values_hash() != old:
		return "a robot without a wake range hashes differently"
	if _needler().values_hash() == old:
		return "a wake range left the values hash unchanged"
	return ""


func test_the_wake_range_is_read_in_whole_millimetres() -> String:
	var def: RobotDef = RobotDef.new()
	if def.set_wake_range(8.00049) != "" or def.wake_range != 8.0:
		return "8.00049 read as %s" % def.wake_range
	if def.set_wake_range(8.0006) != "" or def.wake_range != 8.001:
		return "8.0006 read as %s" % def.wake_range
	var text: String = FileAccess.get_file_as_string(NEEDLER).replace("{", "{\"wake_range\": 12.3456, ")
	var parsed: RobotDef = RobotDef.parse_json(text)
	if parsed.error != "" or parsed.wake_range != 12.346:
		return "a file's 12.3456 read as %s (%s)" % [parsed.wake_range, parsed.error]
	if def.set_wake_range(0.0) == "" or def.wake_range != 8.001:
		return "zero was accepted or changed the value"
	return ""


func test_a_spawn_entry_sets_the_wake_range_of_its_robot_only() -> String:
	var text: String = "{\"robots\": [" \
		+ "{\"id\": \"needler\", \"position\": [0, 0, -15], \"facing\": [0, 0, 1], \"wake_range\": 6.5}," \
		+ "{\"id\": \"needler\", \"position\": [0, 0, -20], \"facing\": [0, 0, 1]}]}"
	var list: RobotSpawnList = RobotSpawnList.parse_json(text)
	if list.error != "":
		return list.error
	var problem: String = list.resolve({"needler": FileAccess.get_file_as_string(NEEDLER)})
	if problem != "":
		return problem
	if list.spawns[0].def.wake_range != 6.5:
		return "the first needler has wake range %s" % list.spawns[0].def.wake_range
	if list.spawns[1].def.has_wake_range():
		return "the second needler took the first one's wake range"
	for bad: String in ["0", "-1", "\"far\"", "20000"]:
		var bad_list: RobotSpawnList = RobotSpawnList.parse_json(text.replace("6.5", bad))
		if not bad_list.error.contains("robot 1") or not bad_list.error.contains("wake_range"):
			return "wake_range %s gave error \"%s\"" % [bad, bad_list.error]
	return ""


func test_the_wake_range_round_trips_through_the_replay() -> String:
	var replay: Replay = Replay.new(4, 1)
	replay.robots = [
		RobotSpawn.new(_needler(), Vector3i(0, 0, -15000), Vector3i(0, 0, 1000), _weapon(NEEDLE_GUN)),
		RobotSpawn.new(_needler(0.0), Vector3i(2000, 0, -30000), Vector3i(0, 0, 1000), _weapon(NEEDLE_GUN)),
	]
	for tick: int in 240:
		# Drift forward so the first needler wakes part way through.
		var thrust: Vector3i = Vector3i(0, 0, -400) if tick < 60 else Vector3i.ZERO
		replay.add_tick([ShipInput.new(thrust)] as Array[ShipInput])
	var text: String = replay.to_text()
	if text.count("\"wake_range\"") != 1:
		return "expected the wake range on the first robot line only:\n%s" % text
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	if reread.robots[0].def.wake_range != WAKE_M or reread.robots[1].def.has_wake_range():
		return "wake ranges read back as %s and %s" % [reread.robots[0].def.wake_range,
			reread.robots[1].def.wake_range]
	var live: Sim = replay.run()
	if not live.robots[0].awake:
		return "the run never woke the first needler, so this proves too little"
	if reread.run().state_hash() != live.state_hash():
		return "the reread replay ends on another hash"
	return ""


func test_every_test_tunnel_robot_has_a_wake_range_shorter_than_its_start_distance() -> String:
	var spawns: Array[RobotSpawn] = LocalSession.load_spawns(SPAWN_FILE)
	if spawns.size() != 6:
		return "%d spawns loaded" % spawns.size()
	for spawn: RobotSpawn in spawns:
		if not spawn.def.has_wake_range():
			return "%s has no wake range" % spawn.id
		if spawn.def.wake_range >= spawn.position().length():
			return "%s wakes with the ship at the start" % spawn.id
	return ""
