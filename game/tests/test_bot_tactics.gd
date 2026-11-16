extends RefCounted

## The bot pilot's fighting in a level (#334): it shoots only where a shot
## gets through the rock, answers the robot it can reach before a nearer one
## behind rock, and falls back out of fire when its shield runs low. The G2
## level is the playground; `test_m2_g2_level.gd` checks the whole fight.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SHIP: String = "res://data/ships/default_ship.json"
const DRONE: String = "res://data/robots/drone.json"
const WEAPONS: String = "res://data/weapons/"
## Inside box 1, in the shaft below the first corridor: behind rock from the
## start, in sight from the corridor's end.
const SHAFT_ROBOT: Vector3 = Vector3(0.0, -20.0, -42.0)


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


## An armed ship at the origin facing -z inside the level's walls, and an
## armed drone at each of `positions`.
func _sim(level: LevelDef, positions: Array[Vector3]) -> Sim:
	var sim: Sim = Sim.new(3, 1)
	sim.set_walls(level.union)
	sim.equip(LocalSession.load_tuning(SHIP).loadout)
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS + def.weapon + ".json"))
	for position: Vector3 in positions:
		sim.spawn_robot(def, position, Basis.IDENTITY, weapon)
	return sim


func test_a_shot_reaches_along_the_corridor_but_not_through_rock() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [])
	var bot: BotPilot = BotPilot.new(sim, 0, level)
	if not bot.shot_reaches(sim.ships[0], Vector3(0.0, 0.0, -30.0)):
		return "a shot down the open corridor does not reach"
	if bot.shot_reaches(sim.ships[0], SHAFT_ROBOT):
		return "a shot through the rock into the shaft reaches"
	return ""


## The nearer robot sits behind rock; the bot faces the farther one in sight
## and fires, which it would not do while aiming at the nearer one.
func test_fires_at_the_robot_in_sight_before_a_nearer_one_behind_rock() -> String:
	var level: LevelDef = _level()
	var hidden: Vector3 = Vector3(0.0, -12.0, -38.0)
	var in_sight: Vector3 = Vector3(5.0, 2.0, -39.9)
	if in_sight.length() <= hidden.length():
		return "set-up: the robot in sight must be the farther one"
	var sim: Sim = _sim(level, [hidden, in_sight])
	var bot: BotPilot = BotPilot.new(sim, 0, level)
	sim.ships[0].orientation = Basis.looking_at(in_sight, Vector3.UP)
	var input: ShipInput = bot.next_input(0)
	if not input.fire_primary:
		return "the bot held fire at the robot in sight"
	return ""


func test_never_fires_at_a_robot_behind_rock() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [SHAFT_ROBOT])
	var bot: BotPilot = BotPilot.new(sim, 0, level)
	sim.ships[0].orientation = Basis.looking_at(SHAFT_ROBOT, Vector3.UP)
	if bot.next_input(0).fire_primary:
		return "the bot fired into the rock"
	return ""


## Out of the drone's reach at the start, then in its sight at the corridor's
## end with a low shield: the bot heads back (+z) rather than closing in.
func test_falls_back_out_of_fire_with_a_low_shield() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [SHAFT_ROBOT])
	var bot: BotPilot = BotPilot.new(sim, 0, level)
	var ship: ShipState = sim.ships[0]
	if bot.under_fire(ship):
		return "set-up: the drone already reaches the start"
	bot.next_input(0)
	ship.position = Vector3(0.0, 0.0, -36.5)
	if not bot.under_fire(ship):
		return "set-up: the drone does not reach the corridor's end"
	ship.shield = BotPilot.RETREAT_SHIELD + 1.0
	if bot.next_input(1).thrust_q.z >= 0:
		return "with its shield up the bot did not close in"
	ship.shield = BotPilot.RETREAT_SHIELD - 1.0
	var input: ShipInput = bot.next_input(2)
	if input.thrust_q.z <= 0:
		return "with its shield low the bot thrust %s, expected back towards the start" % input.thrust_q
	return ""
