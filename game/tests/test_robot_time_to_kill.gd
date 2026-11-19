extends RefCounted

## Robot balance from the data files alone (#612, CMB-3, CMB-4, ARC-4): how
## long each robot type takes to destroy a ship that does nothing, how many
## shots its shield takes, and how many pulse-cannon hits the robot takes.
## The owner died in about 4 s to one robot in the headset; these bounds keep
## the first fight learnable whatever the data files are tuned to.
##
## Every shot is counted as a hit and lands the tick it is fired, so the times
## are the worst case for an idle ship; a moving pilot lasts longer.

const SHIP_FILE: String = "res://data/ships/default_ship.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const GEN_ROBOTS: String = "res://data/gen/robots.json"
const TEST_TUNNEL: String = "res://data/levels/test_tunnel_robots.json"
const ROBOT_DIR: String = "res://data/robots"
## First-contact robots: the issue's 20 to 30 s against an idle ship.
const FIRST_CONTACT_MIN_S: float = 20.0
const FIRST_CONTACT_MAX_S: float = 30.0
## No single robot may kill an idle ship faster than this.
const ANY_ROBOT_MIN_S: float = 10.0
## The shield must take at least this many robot shots.
const SHIELD_MIN_SHOTS: int = 5
## Pulse-cannon hits a common type needs, inclusive.
const COMMON_MIN_HITS: int = 3
const COMMON_MAX_HITS: int = 5
## Ten minutes: a robot that has not killed by then never will.
const TICK_LIMIT: int = 36000
## Close enough for every robot weapon's range, straight ahead of the robot.
const RANGE_M: float = 5.0


## Seconds `def` armed with `weapon` takes to bring an idle ship from the
## ship file to zero hull, or INF if it never does. The ship sits in range,
## straight ahead, and its shield recharges as it would in flight.
static func time_to_kill(def: RobotDef, weapon: WeaponDef) -> float:
	var ship: ShipState = ShipState.new()
	ShipTuning.parse_json(FileAccess.get_file_as_string(SHIP_FILE)).apply_to(ship)
	var robot: RobotState = RobotState.new(def, Vector3(0.0, 0.0, -RANGE_M))
	robot.weapon = weapon
	robot.orientation = Basis(Vector3.UP, PI)
	for tick: int in TICK_LIMIT:
		ship.step(Vector3.ZERO, Vector3.ZERO)
		var fired: WeaponDef = robot.fire_at(ship)
		if fired != null:
			ship.apply_damage(fired.damage)
		if ship.hull <= 0.0:
			return float(tick + 1) * ShipState.TICK_DT
	return INF


## Each robot type's numbers by id: time to kill, shots the shield takes,
## pulse-cannon hits needed. Also printed as the table in the pull request.
static func table() -> Dictionary:
	var rows: Dictionary = {}
	var ship: ShipState = ShipState.new()
	ShipTuning.parse_json(FileAccess.get_file_as_string(SHIP_FILE)).apply_to(ship)
	var cannon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	var files: PackedStringArray = DirAccess.get_files_at(ROBOT_DIR)
	files.sort()
	for file: String in files:
		if file.get_extension() != "json":
			continue
		var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(ROBOT_DIR.path_join(file)))
		var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(def.weapon_path()))
		rows[def.id] = {
			"weapon": def.weapon,
			"ttk_s": time_to_kill(def, weapon),
			"shield_shots": ceili(ship.max_shield / weapon.damage) if weapon.damage > 0.0 else 0,
			"pulse_hits": ceili(def.hull / cannon.damage),
		}
	return rows


## The types a generated level may place near its start, and the test
## tunnel's nearest robot: the robots a pilot meets first.
static func first_contact_ids() -> Array[String]:
	var ids: Array[String] = []
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GEN_ROBOTS))
	for id: Variant in plan["types"]:
		ids.append(str(id))
	var tunnel: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_TUNNEL))
	var nearest: String = ""
	var nearest_z: float = -INF
	for spawn: Variant in tunnel["robots"]:
		var z: float = float(spawn["position"][2])
		if z > nearest_z:
			nearest_z = z
			nearest = str(spawn["id"])
	if not ids.has(nearest):
		ids.append(nearest)
	return ids


static func common_ids() -> Array[String]:
	var ids: Array[String] = []
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GEN_ROBOTS))
	for id: Variant in plan["types"]:
		ids.append(str(id))
	return ids


func test_every_robot_weapon_parses() -> String:
	for id: String in table():
		var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(ROBOT_DIR.path_join(id + ".json")))
		var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(def.weapon_path()))
		if weapon.error != "":
			return "%s: %s" % [def.weapon_path(), weapon.error]
	return ""


func test_first_contact_robots_take_20_to_30_s() -> String:
	var rows: Dictionary = table()
	for id: String in first_contact_ids():
		var ttk: float = rows[id]["ttk_s"]
		if ttk < FIRST_CONTACT_MIN_S or ttk > FIRST_CONTACT_MAX_S:
			return "%s kills an idle ship in %.1f s, outside %s to %s s" % [id, ttk,
				FIRST_CONTACT_MIN_S, FIRST_CONTACT_MAX_S]
	return ""


func test_no_robot_kills_in_under_10_s() -> String:
	var rows: Dictionary = table()
	for id: String in rows:
		if rows[id]["ttk_s"] < ANY_ROBOT_MIN_S:
			return "%s kills an idle ship in %.1f s" % [id, rows[id]["ttk_s"]]
	return ""


func test_the_shield_takes_at_least_5_shots() -> String:
	var rows: Dictionary = table()
	for id: String in rows:
		if rows[id]["shield_shots"] < SHIELD_MIN_SHOTS:
			return "%s breaks the shield in %d shots" % [id, rows[id]["shield_shots"]]
	return ""


func test_common_robots_take_3_to_5_pulse_hits() -> String:
	var rows: Dictionary = table()
	for id: String in common_ids():
		var hits: int = rows[id]["pulse_hits"]
		if hits < COMMON_MIN_HITS or hits > COMMON_MAX_HITS:
			return "%s takes %d pulse-cannon hits" % [id, hits]
	return ""


## The ship's own cannon is not a robot weapon, so tuning robots leaves it be.
func test_no_robot_fires_a_ship_weapon() -> String:
	for id: String in table():
		var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(ROBOT_DIR.path_join(id + ".json")))
		if FileAccess.file_exists("%s/%s.json" % [RobotDef.WEAPONS_DIR, def.weapon]):
			return "%s fires %s, a ship weapon" % [id, def.weapon]
	return ""
