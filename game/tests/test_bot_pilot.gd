extends RefCounted

## The bot pilot: hunts the nearest robot with only a ship's inputs, never
## writes the sim, and is deterministic (CMB-3, PLT-4, MP-2, ARC-1, ARC-2,
## #248).

const SHIP: String = "res://data/ships/default_ship.json"
const DRONE: String = "res://data/robots/drone.json"
const WEAPONS: String = "res://data/weapons/"
## Ticks the bot gets to destroy what the issue sets up: 30 seconds.
const TICK_LIMIT: int = 1800


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _drone_weapon(def: RobotDef) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS + def.weapon + ".json"))


## One ship at the origin facing -Z with the shipped loadout, and an armed
## hovering drone at each of `positions`.
func _sim(positions: Array[Vector3]) -> Sim:
	var sim: Sim = Sim.new(17, 1)
	sim.equip(LocalSession.load_tuning(SHIP).loadout)
	var def: RobotDef = _drone()
	for position: Vector3 in positions:
		sim.spawn_robot(def, position, Basis.IDENTITY, _drone_weapon(def))
	return sim


## Flies the bot until no robot is left or the limit is reached; returns the
## ticks flown.
func _fly(sim: Sim, bot: BotPilot, limit: int) -> int:
	while not sim.robots.is_empty() and sim.tick < limit:
		var inputs: Array[ShipInput] = [bot.next_input(sim.tick)]
		sim.step(inputs)
	return sim.tick


## 40 m away, 30 degrees right of the nose (the ship faces -Z).
func _off_nose() -> Vector3:
	var angle: float = deg_to_rad(30.0)
	return Vector3(sin(angle), 0.0, -cos(angle)) * 40.0


static func _describe(input: ShipInput) -> Array:
	return [input.thrust_q, input.turn_q, input.afterburner, input.reset_to_start,
		input.fire_primary]


func test_shipped_loadout_is_armed() -> String:
	var sim: Sim = _sim([])
	if sim.ships[0].primary_slots[0] == null:
		return "the shipped loadout left primary slot 1 empty; the tests below need a weapon"
	return ""


func test_destroys_a_drone_30_degrees_off_the_nose() -> String:
	var sim: Sim = _sim([_off_nose()])
	var ticks: int = _fly(sim, BotPilot.new(sim, 0), TICK_LIMIT)
	if not sim.robots.is_empty():
		return "drone still alive after %d ticks, hull %f" % [ticks, sim.robots[0].hull]
	return ""


func test_destroys_two_drones_on_opposite_sides() -> String:
	var sim: Sim = _sim([Vector3(-40.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0)])
	var ticks: int = _fly(sim, BotPilot.new(sim, 0), TICK_LIMIT)
	if not sim.robots.is_empty():
		return "%d drones still alive after %d ticks" % [sim.robots.size(), ticks]
	return ""


func test_targets_the_nearest_robot_ties_to_the_lower_index() -> String:
	var sim: Sim = _sim([Vector3(-40.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 30.0)])
	var bot: BotPilot = BotPilot.new(sim, 0)
	if bot.nearest_robot(Vector3.ZERO) != sim.robots[2]:
		return "did not pick the nearest robot"
	sim.robots.remove_at(2)
	if bot.nearest_robot(Vector3.ZERO) != sim.robots[0]:
		return "a tie did not go to the lower index"
	return ""


func test_with_no_robots_it_neither_thrusts_nor_fires() -> String:
	var sim: Sim = _sim([])
	var bot: BotPilot = BotPilot.new(sim, 0)
	for i: int in 120:
		var input: ShipInput = bot.next_input(sim.tick)
		if input.thrust_q != Vector3i.ZERO or input.fire_primary:
			return "tick %d input %s, expected no thrust and no fire" % [sim.tick, _describe(input)]
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)
	return ""


func test_never_writes_the_sim() -> String:
	var sim: Sim = _sim([_off_nose(), Vector3(-30.0, 5.0, 10.0)])
	var bot: BotPilot = BotPilot.new(sim, 0)
	for i: int in 600:
		var before: int = sim.state_hash()
		var input: ShipInput = bot.next_input(sim.tick)
		if sim.state_hash() != before:
			return "next_input changed the sim at tick %d" % sim.tick
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)
	return ""


func test_turns_no_faster_than_the_controller_mappings() -> String:
	if BotPilot.MAX_PITCH_RATE > ThumbstickMapping.MAX_PITCH_RATE \
			or BotPilot.MAX_YAW_RATE > ThumbstickMapping.MAX_YAW_RATE:
		return "bot turn limits exceed the thumbstick mapping's"
	var sim: Sim = _sim([Vector3(0.0, 0.0, 40.0), Vector3(-25.0, 20.0, -10.0)])
	var bot: BotPilot = BotPilot.new(sim, 0)
	var limit: Vector3 = Vector3(BotPilot.MAX_PITCH_RATE, BotPilot.MAX_YAW_RATE, 0.0)
	for i: int in 900:
		var input: ShipInput = bot.next_input(sim.tick)
		var turn: Vector3 = input.turn()
		# One thousandth of slack: the rates are rounded to the stored precision.
		for axis: int in 3:
			if absf(turn[axis]) > limit[axis] + 0.001:
				return "tick %d turn %s exceeds %s" % [sim.tick, turn, limit]
		var thrust: Vector3 = input.thrust()
		if thrust.length() > 1.001:
			return "tick %d thrust %s is longer than full stick" % [sim.tick, thrust]
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)
	return ""


func test_backs_off_when_closer_than_the_engagement_distance() -> String:
	var sim: Sim = _sim([Vector3(0.0, 0.0, -5.0)])
	var input: ShipInput = BotPilot.new(sim, 0).next_input(0)
	# The drone is straight ahead (-Z in ship space), so backing off is +Z.
	if input.thrust_q.z <= 0:
		return "thrust %s, expected backwards (+z) inside %f m" % [
			input.thrust_q, BotPilot.ENGAGE_DISTANCE]
	return ""


func test_holds_fire_outside_the_cone_and_beyond_range() -> String:
	var sim: Sim = _sim([Vector3(0.0, 0.0, -20.0)])
	var ship: ShipState = sim.ships[0]
	if not BotPilot.should_fire(ship, Vector3(0.0, 0.0, -20.0)):
		return "did not fire at a robot dead ahead in range"
	var wide: float = deg_to_rad(BotPilot.FIRE_CONE_HALF_ANGLE_DEG + 1.0)
	if BotPilot.should_fire(ship, Vector3(sin(wide), 0.0, -cos(wide)) * 20.0):
		return "fired outside the cone"
	var weapon: WeaponDef = ship.primary_slots[0]
	var weapon_range: float = weapon.projectile_speed * float(weapon.lifetime_ticks()) \
		* ShipState.TICK_DT
	if BotPilot.should_fire(ship, Vector3(0.0, 0.0, -(weapon_range + 1.0))):
		return "fired beyond the weapon's range"
	ship.primary_slots[0] = null
	if BotPilot.should_fire(ship, Vector3(0.0, 0.0, -20.0)):
		return "fired with an empty slot"
	return ""


func test_two_runs_give_the_same_inputs_and_hashes() -> String:
	var positions: Array[Vector3] = [Vector3(-40.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0)]
	var first: Sim = _sim(positions)
	var second: Sim = _sim(positions)
	var first_bot: BotPilot = BotPilot.new(first, 0)
	var second_bot: BotPilot = BotPilot.new(second, 0)
	for i: int in 900:
		var a: ShipInput = first_bot.next_input(first.tick)
		var b: ShipInput = second_bot.next_input(second.tick)
		if _describe(a) != _describe(b):
			return "tick %d inputs differ: %s and %s" % [first.tick, _describe(a), _describe(b)]
		var first_inputs: Array[ShipInput] = [a]
		var second_inputs: Array[ShipInput] = [b]
		first.step(first_inputs)
		second.step(second_inputs)
		if first.state_hash() != second.state_hash():
			return "tick %d hashes differ" % first.tick
	return ""
