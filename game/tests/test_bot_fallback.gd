extends RefCounted

## `BotFallback`, split out of `BotPilot` (#1135): when the bot falls back out
## of fire and when it waits for robots out of sight. The whole fight is
## checked through the pilot in `test_bot_tactics.gd` and `test_bot_stall.gd`;
## these check the extracted rules on their own.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SHIP: String = "res://data/ships/default_ship.json"
const DRONE: String = "res://data/robots/drone.json"
const WEAPONS: String = "res://data/weapons/"
## In the shaft below the first corridor: out of reach of the start, in sight
## of the corridor's end (as in `test_bot_tactics.gd`).
const SHAFT_ROBOT: Vector3 = Vector3(0.0, -20.0, -42.0)
const CORRIDOR_END: Vector3 = Vector3(0.0, 0.0, -36.5)


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _sim(level: LevelDef, positions: Array[Vector3]) -> Sim:
	var sim: Sim = Sim.new(3, 1)
	sim.set_walls(level.union)
	sim.equip(LocalSession.load_tuning(SHIP).loadout)
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS + def.weapon + ".json"))
	for position: Vector3 in positions:
		sim.spawn_robot(def, position, Basis.IDENTITY, weapon)
	return sim


func _fallback(sim: Sim, level: LevelDef) -> BotFallback:
	return BotFallback.new(sim, BotCover.new(sim, level, LevelRoute.new(level)))


func test_the_pilot_keeps_the_names_its_callers_use() -> String:
	if BotPilot.RETREAT_SHIELD != BotFallback.RETREAT_SHIELD \
			or BotPilot.OUTNUMBERED != BotFallback.OUTNUMBERED \
			or BotPilot.CLOSING_ROBOT_SPEED != BotFallback.CLOSING_ROBOT_SPEED \
			or BotPilot.MAX_WAIT_TICKS != BotFallback.MAX_WAIT_TICKS:
		return "a constant moved to BotFallback no longer matches BotPilot's name for it"
	return ""


## Safe at the start, then under fire at the corridor's end: with the shield
## up it holds on, with the shield low it falls back to where it stood safe.
func test_falls_back_to_where_it_last_stood_safe_with_a_low_shield() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [SHAFT_ROBOT])
	var fallback: BotFallback = _fallback(sim, level)
	var ship: ShipState = sim.ships[0]
	var start: Vector3 = ship.position
	if BotFallback.under_fire(sim, level.union, ship):
		return "set-up: the drone already reaches the start"
	fallback.update(ship, false)
	if fallback.retreating() or fallback.shelter(ship) != Vector3.INF:
		return "falling back with no robot able to shoot"
	ship.position = CORRIDOR_END
	if not BotFallback.under_fire(sim, level.union, ship):
		return "set-up: the drone does not reach the corridor's end"
	ship.shield = BotFallback.RETREAT_SHIELD + 1.0
	fallback.update(ship, true)
	if fallback.retreating():
		return "fell back with the shield above %.0f" % BotFallback.RETREAT_SHIELD
	ship.shield = BotFallback.RETREAT_SHIELD - 1.0
	fallback.update(ship, true)
	if not fallback.retreating():
		return "did not fall back with the shield below %.0f" % BotFallback.RETREAT_SHIELD
	if fallback.shelter(ship) != start:
		return "shelter %s, expected the start %s" % [fallback.shelter(ship), start]
	# Out of fire again, the fall-back ends whatever the shield.
	fallback.update(ship, false)
	if fallback.retreating():
		return "still falling back out of fire"
	return ""


func test_waits_at_most_max_wait_ticks_in_a_row_and_a_robot_in_sight_resets_it() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [])
	var fallback: BotFallback = _fallback(sim, level)
	var ship: ShipState = sim.ships[0]
	ship.shield = ship.max_shield - 1.0
	for tick: int in range(BotFallback.MAX_WAIT_TICKS):
		if not fallback.waits(ship, true, false, false, false, false):
			return "stopped waiting at tick %d" % tick
	if fallback.waits(ship, true, false, false, false, false):
		return "waited past %d ticks" % BotFallback.MAX_WAIT_TICKS
	if fallback.waits(ship, true, true, false, false, false):
		return "waited with the robot in sight"
	if not fallback.waits(ship, true, false, false, false, false):
		return "a robot in sight did not reset the wait"
	return ""


func test_no_wait_without_a_reason() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [])
	var fallback: BotFallback = _fallback(sim, level)
	var ship: ShipState = sim.ships[0]
	ship.shield = ship.max_shield
	if fallback.waits(ship, true, false, false, false, false):
		return "waited with a full shield and no robot closing"
	ship.shield = ship.max_shield - 1.0
	if fallback.waits(ship, false, false, false, false, false):
		return "waited with no target"
	if fallback.waits(ship, true, false, true, false, false):
		return "waited under fire"
	if fallback.waits(ship, true, false, false, true, false):
		return "waited while flanking"
	if fallback.waits(ship, true, false, false, false, true):
		return "waited while stalled"
	return ""


func test_robots_closing_counts_only_robots_coming_on() -> String:
	var sim: Sim = _sim(_level(), [Vector3(0.0, 0.0, -20.0)])
	var ship: ShipState = sim.ships[0]
	var robot: RobotState = sim.robots[0]
	robot.velocity = Vector3(0.0, 0.0, BotFallback.CLOSING_ROBOT_SPEED * 2.0)
	if not BotFallback.robots_closing(sim, ship):
		return "a robot coming on was not counted"
	robot.velocity = Vector3(0.0, 0.0, -1.0)
	if BotFallback.robots_closing(sim, ship):
		return "a robot moving away was counted"
	robot.velocity = Vector3(0.0, 0.0, BotFallback.CLOSING_ROBOT_SPEED * 0.5)
	if BotFallback.robots_closing(sim, ship):
		return "a robot creeping slower than CLOSING_ROBOT_SPEED was counted"
	return ""
