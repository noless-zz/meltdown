extends RefCounted

## Replay robot lines carry each robot's resolved weapon and its optional
## movement keys (#266, ARC-2, CMB-2, CMB-3, ARC-4), so a run with armed
## robots, or with robot files that set those keys, replays exactly.

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const TICKS: int = 240


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


## The ship drifts slowly ahead; the drone 10 m ahead faces it.
func _input(tick: int) -> ShipInput:
	var turn: Vector3i = Vector3i(0, 150, 0) if tick < 60 else Vector3i.ZERO
	return ShipInput.new(Vector3i(0, 0, -200), turn)


func _armed_spawns() -> Array[RobotSpawn]:
	var cannon: WeaponDef = _cannon()
	cannon.damage = 3.123456789012  # Not round: lost precision would show.
	return [RobotSpawn.new(_drone(), Vector3i(0, 0, -10000), Vector3i(0, 0, 1000), cannon),
		RobotSpawn.new(_drone(), Vector3i(4000, 0, -30000), Vector3i(0, 0, 1000))]


func _robot_shots_seen(sim: Sim) -> int:
	var count: int = 0
	for projectile: Projectile in sim.projectiles:
		if projectile.is_robot_owned():
			count += 1
	return count


func test_an_armed_drone_firing_at_the_ship_replays_to_the_live_hash() -> String:
	var spawns: Array[RobotSpawn] = _armed_spawns()
	var live: Sim = Sim.new(17, 1)
	if not RobotSpawn.spawn_all(live, spawns):
		return "the live run refused its spawns"
	var replay: Replay = Replay.new(17, 1)
	replay.robots = spawns
	var start_shield: float = live.ships[0].shield
	var shots: int = 0
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [_input(tick)]
		live.step(inputs)
		replay.add_tick(inputs)
		shots = maxi(shots, _robot_shots_seen(live))
	if shots == 0:
		return "the armed drone never fired"
	if live.ships[0].shield >= start_shield:
		return "the drone's shots never hit the ship"
	var reread: Replay = Replay.from_text(replay.to_text())
	if reread.error != "":
		return reread.error
	if reread.robots[0].weapon == null or reread.robots[1].weapon != null:
		return "armed and unarmed did not read back as such"
	if reread.robots[0].weapon.damage != 3.123456789012:
		return "the weapon read back as %s damage" % reread.robots[0].weapon.damage
	var replayed: Sim = reread.run()
	if replayed == null:
		return reread.run_error
	if replayed.state_hash() != live.state_hash():
		return "the replay ends on %d, the live run on %d" % [replayed.state_hash(), live.state_hash()]
	# Dropping the weapon must change the outcome, or the test proves nothing.
	reread.robots[0].weapon = null
	if reread.run().state_hash() == live.state_hash():
		return "the run ends the same without the drone's weapon"
	return ""


func test_an_unarmed_robot_is_recorded_as_unarmed() -> String:
	var replay: Replay = Replay.new(1, 1)
	replay.robots = [RobotSpawn.new(_drone(), Vector3i(0, 0, -5000), Vector3i(0, 0, 1000))]
	replay.add_tick([ShipInput.new()] as Array[ShipInput])
	var text: String = replay.to_text()
	if not text.contains("\"weapon\":null}"):
		return "the robot line does not say unarmed:\n%s" % text
	var reread: Replay = Replay.from_text(text)
	if reread.error != "" or reread.robots[0].weapon != null:
		return "an unarmed robot read back as %s" % reread.error
	return ""


func test_optional_movement_keys_round_trip_through_the_robot_line() -> String:
	var def: RobotDef = _drone()
	def.movement = "strafe"
	def.strafe_min_distance = 6.123456789012
	def.strafe_max_distance = 31.5
	def.standoff_radii = 7.25
	def.strafe_radial_gain = 0.875
	var replay: Replay = Replay.new(2, 1)
	replay.robots = [RobotSpawn.new(def, Vector3i(0, 0, -20000), Vector3i(0, 0, 1000))]
	for tick: int in 90:
		replay.add_tick([_input(tick)] as Array[ShipInput])
	var text: String = replay.to_text()
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	if reread.to_text() != text:
		return "the text changed on reading back"
	var back: RobotDef = reread.robots[0].def
	for key: String in RobotDef.OPTIONAL_KEYS:
		if back.get(key) != def.get(key):
			return "%s read back as %s, written %s" % [key, back.get(key), def.get(key)]
	if reread.run().state_hash() != replay.run().state_hash():
		return "the reread replay ends on another hash"
	return ""


func test_version_8_robot_lines_still_read_as_unarmed() -> String:
	var drone: String = FileAccess.get_file_as_string(DRONE).replace("\n", "").replace("\t", "")
	var text: String = "meltdown-replay 8\nseed 1\nships 1\nrobot 0 0 -9000 0 0 1 %s\ninputs\n0 0 0 0 0 0 0 0 0\n" % drone
	var replay: Replay = Replay.from_text(text)
	if replay.error != "":
		return replay.error
	if replay.robots.size() != 1 or replay.robots[0].weapon != null:
		return "a version 8 robot did not read as one unarmed robot"
	if replay.robots[0].def.strafe_min_distance != RobotDef.new().strafe_min_distance:
		return "a version 8 robot did not get the default optional keys"
	return ""


func test_malformed_robot_lines_name_the_field() -> String:
	var drone: String = FileAccess.get_file_as_string(DRONE).replace("\n", "").replace("\t", "")
	var cannon: String = FileAccess.get_file_as_string(PULSE_CANNON).replace("\n", "").replace("\t", "")
	var bad_cannon: String = cannon.replace("\"damage\"", "\"damages\"")
	var slow_cannon: String = JSON.stringify({"fire_interval_ticks": 0, "projectile_speed": 120,
		"lifetime": 1.5, "damage": 8, "energy_cost": 2})
	var header: String = "meltdown-replay 9\nseed 1\nships 1\nrobot 0 0 0 0 0 1 "
	var cases: Array[Array] = [
		["{\"robot\": %s, \"weapon\": %s}" % [drone, bad_cannon],
			"line 4: robot 1 weapon: unknown key \"damages\""],
		["{\"robot\": %s, \"weapon\": %s}" % [drone, slow_cannon],
			"line 4: robot 1 weapon: key \"fire_interval_ticks\" is 0.0, must be at least 1.0"],
		["{\"robot\": %s, \"weapon\": 3}" % drone,
			"line 4: robot 1: key \"weapon\" must be a JSON object or null"],
		["{\"robot\": %s}" % drone, "line 4: robot 1: missing key \"weapon\""],
		["{\"robot\": %s, \"weapon\": null, \"ammo\": 1}" % drone, "line 4: robot 1: unknown key \"ammo\""],
		["%s" % drone, "line 4: robot 1: unknown key \"id\""],
		["{\"robot\": [], \"weapon\": null}", "line 4: robot 1: key \"robot\" must be a JSON object"],
		["{\"robot\": {\"id\": \"drone\"}, \"weapon\": null}", "line 4: robot 1: missing key \"hull\""],
	]
	for c: Array in cases:
		var replay: Replay = Replay.from_text(header + c[0] + "\ninputs\n")
		if replay.error != c[1]:
			return "gave \"%s\", expected \"%s\"" % [replay.error, c[1]]
		if not replay.robots.is_empty():
			return "a rejected robot line kept a robot"
	return ""
