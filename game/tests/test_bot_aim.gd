extends RefCounted

## The bot pilot's aiming (#492): tracking a robot that crosses the nose, and
## choosing the robot cheapest to aim at.

const SHIP: String = "res://data/ships/default_ship.json"
const WEAPONS: String = "res://data/weapons/"
const ROBOTS: String = "res://data/robots/"


## An armed ship at the origin facing -z.
func _ship() -> ShipState:
	var sim: Sim = Sim.new(3, 1)
	sim.equip(LocalSession.load_tuning(SHIP).loadout)
	return sim.ships[0]


func _robot(id: String, position: Vector3, velocity: Vector3 = Vector3.ZERO) -> RobotState:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(ROBOTS + id + ".json"))
	var robot: RobotState = RobotState.new(def, position)
	robot.velocity = velocity
	return robot


## With the nose already on a strafer's lead point, `turn_towards` asks for no
## turn and the robot slips out of the cone; `track` turns with it.
func test_track_turns_with_a_robot_crossing_the_nose() -> String:
	var ship: ShipState = _ship()
	var glider: RobotState = _robot("glider", Vector3(0.0, 0.0, -20.0), Vector3(18.0, 0.0, 0.0))
	var lead: Vector3 = BotAim.lead_point(ship, glider)
	ship.orientation = Basis.looking_at(lead, Vector3.UP)
	var still: Vector3 = BotAim.turn_towards(ship.orientation.transposed() * lead)
	if absf(still.y) > 0.01:
		return "set-up: the nose is not on the lead point (yaw %f)" % still.y
	var yaw: float = BotAim.track(ship, glider).y
	# Turning right is negative yaw; the robot crosses at about 0.9 rad/s.
	if yaw > -0.8 or yaw < -BotAim.MAX_YAW_RATE:
		return "track asked for yaw %f rad/s, expected about -0.9" % yaw
	return ""


## A robot standing still dead ahead needs no turn either way.
func test_track_holds_still_on_a_still_robot_ahead() -> String:
	var ship: ShipState = _ship()
	var turn: Vector3 = BotAim.track(ship, _robot("drone", Vector3(0.0, 0.0, -20.0)))
	if turn.length() > 1e-4:
		return "turn %s, expected none" % turn
	return ""


## The turn stays within the pilot's caps however fast the robot crosses.
func test_track_stays_within_the_turn_caps() -> String:
	var ship: ShipState = _ship()
	var fast: RobotState = _robot("needler", Vector3(0.0, 0.0, -3.0), Vector3(-200.0, 200.0, 0.0))
	var turn: Vector3 = BotAim.track(ship, fast)
	if absf(turn.x) > BotAim.MAX_PITCH_RATE + 1e-6 or absf(turn.y) > BotAim.MAX_YAW_RATE + 1e-6:
		return "turn %s beyond the caps" % turn
	return ""


## Ahead beats beside at the same distance, and a robot ahead beats a nearer
## one off to the side unless it is much farther.
func test_cost_prefers_the_robot_nearest_the_nose() -> String:
	var ship: ShipState = _ship()
	var ahead: RobotState = _robot("drone", Vector3(0.0, 0.0, -20.0))
	var beside: RobotState = _robot("drone", Vector3(20.0, 0.0, 0.0))
	if BotAim.cost(ship, ahead) >= BotAim.cost(ship, beside):
		return "a robot beside the ship cost no more than one ahead"
	var nearer_beside: RobotState = _robot("drone", Vector3(10.0, 0.0, 0.0))
	if BotAim.cost(ship, ahead) >= BotAim.cost(ship, nearer_beside):
		return "a robot 10 m nearer but a quarter turn off cost less than one ahead"
	var far_ahead: RobotState = _robot("drone", Vector3(0.0, 0.0, -100.0))
	if BotAim.cost(ship, far_ahead) <= BotAim.cost(ship, nearer_beside):
		return "a robot 100 m ahead cost less than one 10 m beside"
	return ""
