extends RefCounted

## The main scene's start is survivable: the test tunnel's robots wait for the
## ship to approach, and a ship flying down the tunnel still meets the nearest
## one within three seconds (#301, CMB-2, CMB-3, FLT-1, ARC-4).

## Ten seconds of holding still at the start.
const CALM_TICKS: int = 600
## Three seconds of flying straight down the tunnel.
const ENGAGE_TICKS: int = 180


func _main_session() -> Array:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	return [main, main.get("session")]


## Index of the live robot nearest the ship's start.
func _nearest_robot(session: LocalSession) -> int:
	var best: int = -1
	for index: int in session.sim.robots.size():
		var distance: float = session.sim.robots[index].position.length()
		if best < 0 or distance < session.sim.robots[best].position.length():
			best = index
	return best


func test_holding_still_at_the_start_takes_no_damage_for_ten_seconds() -> String:
	var parts: Array = _main_session()
	var main: Node = parts[0]
	var session: LocalSession = parts[1]
	var robots: int = session.sim.robots.size()
	var shots: int = 0
	var awake: int = 0
	for tick: int in CALM_TICKS:
		session.advance(ShipState.TICK_DT)
		for projectile: Projectile in session.sim.projectiles:
			if projectile.is_robot_owned():
				shots += 1
	for robot: RobotState in session.sim.robots:
		if robot.awake:
			awake += 1
	var ship: ShipState = session.sim.ships[0]
	var hull: float = ship.hull
	var shield: float = ship.shield
	var full_hull: float = ship.max_hull
	var full_shield: float = ship.max_shield
	var ticks: int = session.sim.tick
	main.free()
	if robots != 6:
		return "%d robots in the main scene, expected 6" % robots
	if ticks != CALM_TICKS:
		return "ran %d ticks" % ticks
	if hull != full_hull or shield != full_shield:
		return "hull %s and shield %s after ten seconds at the start" % [hull, shield]
	if shots > 0 or awake > 0:
		return "%d robot shots, %d robots awake" % [shots, awake]
	return ""


func test_flying_down_the_tunnel_meets_the_nearest_robot_within_three_seconds() -> String:
	var parts: Array = _main_session()
	var main: Node = parts[0]
	var session: LocalSession = parts[1]
	var nearest: int = _nearest_robot(session)
	var source: LatestInputSource = main.get("input_source")
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	var start_defence: float = session.sim.ships[0].shield + session.sim.ships[0].hull
	var fired_at: int = -1
	var woke_at: int = -1
	while session.sim.tick < ENGAGE_TICKS and fired_at < 0:
		session.advance(ShipState.TICK_DT)
		if woke_at < 0 and session.sim.robots[nearest].awake:
			woke_at = session.sim.tick
		for projectile: Projectile in session.sim.projectiles:
			if projectile.owner_index == Projectile.robot_owner(nearest):
				fired_at = session.sim.tick
	# Long enough for that first shot to land.
	for tick: int in 30:
		session.advance(ShipState.TICK_DT)
	var end_defence: float = session.sim.ships[0].shield + session.sim.ships[0].hull
	var id: String = session.sim.robots[nearest].def.id
	main.free()
	if woke_at < 0:
		return "the %s never woke in %d ticks" % [id, ENGAGE_TICKS]
	if fired_at < 0:
		return "the %s woke at tick %d but never fired" % [id, woke_at]
	if end_defence >= start_defence:
		return "the %s fired but never hit the ship" % id
	return ""


func test_the_session_replay_reproduces_robots_waking() -> String:
	var parts: Array = _main_session()
	var main: Node = parts[0]
	var session: LocalSession = parts[1]
	var source: LatestInputSource = main.get("input_source")
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	for tick: int in 120:
		if tick == 40:
			source.set_input(ShipInput.new())
		session.advance(ShipState.TICK_DT)
	var asleep: int = 0
	for robot: RobotState in session.sim.robots:
		if not robot.awake:
			asleep += 1
	var live_hash: int = session.sim.state_hash()
	var text: String = session.replay.to_text()
	main.free()
	if asleep == 0 or asleep == 6:
		return "%d of 6 robots asleep; the run should wake some and not others" % asleep
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	var replayed: Sim = reread.run()
	if replayed == null:
		return reread.run_error
	if replayed.state_hash() != live_hash:
		return "the replay ends on %d, the session on %d" % [replayed.state_hash(), live_hash]
	return ""
