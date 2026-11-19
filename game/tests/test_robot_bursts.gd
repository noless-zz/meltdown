extends RefCounted

## Robot weapons fire in bursts with a wind-up before each (#612, CMB-3,
## ARC-4): the optional weapon keys, their parse errors, the firing pattern
## they give a robot, and that weapons without them behave as before.

const BASE: Dictionary = {
	"fire_interval_ticks": 5, "projectile_speed": 100.0, "lifetime": 1.0,
	"damage": 4.0, "energy_cost": 0.0,
}
const DRONE: String = "res://data/robots/drone.json"


func _weapon(extra: Dictionary) -> WeaponDef:
	var data: Dictionary = BASE.duplicate()
	data.merge(extra, true)
	return WeaponDef.parse_json(JSON.stringify(data))


## A drone 5 m away facing a ship at the origin, armed with `weapon`.
func _robot(weapon: WeaponDef) -> RobotState:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var robot: RobotState = RobotState.new(def, Vector3(0.0, 0.0, -5.0), Basis(Vector3.UP, PI))
	robot.weapon = weapon
	return robot


## The ticks (from 0) on which `robot` fires at `ship` over `ticks` calls.
func _shot_ticks(robot: RobotState, ship: ShipState, ticks: int) -> Array[int]:
	var shots: Array[int] = []
	for tick: int in ticks:
		if robot.fire_at(ship) != null:
			shots.append(tick)
	return shots


func test_missing_burst_keys_take_their_defaults() -> String:
	var weapon: WeaponDef = _weapon({})
	if weapon.error != "":
		return weapon.error
	if weapon.burst_shots != 1 or weapon.burst_pause_ticks != 0 or weapon.windup_ticks != 0:
		return "defaults %d %d %d" % [weapon.burst_shots, weapon.burst_pause_ticks, weapon.windup_ticks]
	if weapon.has_bursts():
		return "a weapon without burst keys reports bursts"
	return ""


func test_burst_keys_are_read() -> String:
	var weapon: WeaponDef = _weapon({"burst_shots": 3, "burst_pause_ticks": 40, "windup_ticks": 12})
	if weapon.error != "":
		return weapon.error
	if weapon.burst_shots != 3 or weapon.burst_pause_ticks != 40 or weapon.windup_ticks != 12:
		return "read %d %d %d" % [weapon.burst_shots, weapon.burst_pause_ticks, weapon.windup_ticks]
	if weapon.burst_cooldown_ticks() != 40:
		return "burst cooldown %d, expected 40" % weapon.burst_cooldown_ticks()
	return ""


func test_bad_burst_keys_are_rejected_naming_the_key() -> String:
	var cases: Array = [
		[{"burst_shots": 0}, "burst_shots"],
		[{"burst_shots": 2.5}, "burst_shots"],
		[{"burst_shots": true}, "burst_shots"],
		[{"burst_pause_ticks": -1}, "burst_pause_ticks"],
		[{"burst_pause_ticks": 601}, "burst_pause_ticks"],
		[{"windup_ticks": "10"}, "windup_ticks"],
		[{"windup_ticks": 1.5}, "windup_ticks"],
		[{"burst_shot": 3}, "burst_shot"],
	]
	for case: Array in cases:
		var weapon: WeaponDef = _weapon(case[0])
		if weapon.error == "" or not weapon.error.contains("\"%s\"" % case[1]):
			return "%s gave error '%s'" % [case[0], weapon.error]
	return ""


func test_the_pause_is_never_shorter_than_the_interval() -> String:
	var weapon: WeaponDef = _weapon({"burst_shots": 2, "burst_pause_ticks": 2})
	if weapon.burst_cooldown_ticks() != 5:
		return "burst cooldown %d, expected the interval 5" % weapon.burst_cooldown_ticks()
	return ""


func test_burst_keys_join_the_hash_only_when_set() -> String:
	var plain: WeaponDef = _weapon({})
	var explicit: WeaponDef = _weapon({"burst_shots": 1, "burst_pause_ticks": 0, "windup_ticks": 0})
	if plain.values_hash() != explicit.values_hash():
		return "default burst keys written out change the hash"
	if plain.values_hash() == _weapon({"windup_ticks": 1}).values_hash():
		return "a wind-up does not change the hash"
	return ""


## Without burst keys a robot fires once every interval, as before #612.
func test_a_weapon_without_bursts_fires_every_interval() -> String:
	var shots: Array[int] = _shot_ticks(_robot(_weapon({})), ShipState.new(), 21)
	if shots != [0, 5, 10, 15, 20]:
		return "fired on %s" % [shots]
	return ""


func test_bursts_wind_up_then_fire_then_pause() -> String:
	var weapon: WeaponDef = _weapon({"burst_shots": 3, "burst_pause_ticks": 30, "windup_ticks": 10})
	var robot: RobotState = _robot(weapon)
	var ship: ShipState = ShipState.new()
	var winding: Array[int] = []
	var shots: Array[int] = []
	for tick: int in 100:
		if robot.fire_at(ship) != null:
			shots.append(tick)
		if robot.is_winding_up():
			winding.append(tick)
	# Wind-up 0..9, shots 10, 15, 20; pause to 50; wind-up 50..59; shots 60, 65, 70.
	if shots != [10, 15, 20, 60, 65, 70]:
		return "fired on %s" % [shots]
	if winding.size() != 20 or winding[0] != 0 or winding[9] != 9 or winding[10] != 50:
		return "wound up on %s" % [winding]
	return ""


## A ship that slips out of the fire cone resets the wind-up, so a burst
## always follows a full, visible wind-up.
func test_leaving_the_cone_restarts_the_wind_up() -> String:
	var weapon: WeaponDef = _weapon({"burst_shots": 2, "windup_ticks": 10})
	var robot: RobotState = _robot(weapon)
	var ship: ShipState = ShipState.new()
	for tick: int in 6:
		robot.fire_at(ship)
	if not robot.is_winding_up():
		return "not winding up after 6 ticks in the cone"
	ship.position = Vector3(0.0, 0.0, -20.0)
	robot.fire_at(ship)
	if robot.is_winding_up():
		return "still winding up with the ship behind it"
	ship.position = Vector3.ZERO
	var shots: Array[int] = _shot_ticks(robot, ship, 12)
	if shots != [10]:
		return "after coming back it fired on %s, expected tick 10" % [shots]
	return ""


func test_burst_state_joins_the_robot_hash_only_with_bursts() -> String:
	var plain: RobotState = _robot(_weapon({}))
	var before: int = plain.state_hash()
	plain.windup_elapsed = 3
	if plain.state_hash() != before:
		return "a robot without bursts hashes its wind-up"
	var bursty: RobotState = _robot(_weapon({"windup_ticks": 5}))
	var bursty_before: int = bursty.state_hash()
	bursty.windup_elapsed = 3
	if bursty.state_hash() == bursty_before:
		return "a winding-up robot keeps its hash"
	return ""


func test_burst_keys_survive_a_replay_robot_line() -> String:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var weapon: WeaponDef = _weapon({"burst_shots": 4, "burst_pause_ticks": 50, "windup_ticks": 7})
	var spawn: RobotSpawn = RobotSpawn.new(def, Vector3i(0, 0, -5000), Vector3i(0, 0, 1000), weapon)
	var replay: Replay = Replay.new(0, 1)
	var seen: Dictionary[String, bool] = {"meltdown-replay": true}
	var problem: String = ReplayLines.parse_robot_line(replay, ReplayLines.robot_text(spawn), seen, 9)
	if problem != "":
		return problem
	var back: WeaponDef = replay.robots[0].weapon
	if back == null or back.values_hash() != weapon.values_hash():
		return "the replay read back a different weapon"
	return ""
