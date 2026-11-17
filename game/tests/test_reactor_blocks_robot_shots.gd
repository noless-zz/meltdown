extends RefCounted

## An intact reactor stops robot shots as it stops ship shots (#345, RUN-2,
## CMB-3, ARC-1, ARC-2): a robot behind it cannot hit the ship, the reactor
## takes no harm from them, a destroyed reactor stops nothing, and replays with
## a reactor still reproduce their hash.

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## Robots facing +Z, towards a ship at the origin, from further along -Z.
const FACING_PLUS_Z: Basis = Basis(Vector3.UP, PI)
## A reactor halfway between the ship at the origin and a drone at z = -10.
const ON_LINE: String = '{"position": [0, 0, -5], "radius": 1.5, "hull": 40, "meltdown_seconds": 2}'
## The same reactor moved well clear of that line.
const OFF_LINE: String = '{"position": [6, 0, -5], "radius": 1.5, "hull": 40, "meltdown_seconds": 2}'
## Four of the drone's 10-tick fire intervals, plus time for the shots to land.
const TICKS: int = 60
const SUITES: Array[String] = ["res://acceptance/suites/m1.json", "res://acceptance/suites/m2.json"]


func _sim(reactor_json: String) -> Sim:
	var sim: Sim = Sim.new(345, 1)
	sim.ships[0].shield_recharge = 0.0
	if reactor_json != "":
		sim.set_reactor(ReactorState.parse_json(reactor_json))
	var drone: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var cannon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -10.0), FACING_PLUS_Z, cannon)
	return sim


## Steps `sim` idle for `ticks` and returns how many SHIP_HIT events it saw.
func _fly(sim: Sim, ticks: int) -> int:
	var hits: int = 0
	for i: int in ticks:
		sim.step([ShipInput.new()] as Array[ShipInput])
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_HIT:
				hits += 1
	return hits


func _undamaged(ship: ShipState) -> bool:
	return ship.shield == ship.max_shield and ship.hull == ship.max_hull


func test_a_robot_behind_the_reactor_cannot_hit_the_ship() -> String:
	var sim: Sim = _sim(ON_LINE)
	var hits: int = _fly(sim, TICKS)
	if hits != 0 or not _undamaged(sim.ships[0]):
		return "%d hits through the reactor; shield %s hull %s" % [
			hits, sim.ships[0].shield, sim.ships[0].hull]
	return ""


func test_with_the_reactor_off_the_line_the_robot_hits() -> String:
	var sim: Sim = _sim(OFF_LINE)
	if _fly(sim, TICKS) == 0:
		return "the drone never hit the ship with the reactor off its line"
	return ""


func test_robot_shots_leave_the_reactor_hull_unchanged() -> String:
	var sim: Sim = _sim(ON_LINE)
	_fly(sim, TICKS)
	if sim.reactor.hull != 40.0 or sim.reactor.destroyed:
		return "reactor hull %s, destroyed %s after robot fire" % [sim.reactor.hull, sim.reactor.destroyed]
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.REACTOR_DESTROYED:
			return "a robot shot reported the reactor destroyed"
	return ""


## Judged by the shots' flight, not by hits: with the reactor destroyed the
## ship at its start point has escaped, so it can no longer be hit at all.
func test_a_destroyed_reactor_no_longer_blocks() -> String:
	var sim: Sim = _sim(ON_LINE)
	sim.reactor.apply_damage(40.0)
	if not sim.reactor.destroyed:
		return "the reactor did not die"
	for i: int in TICKS:
		sim.step([ShipInput.new()] as Array[ShipInput])
		for projectile: Projectile in sim.projectiles:
			if projectile.is_robot_owned() and projectile.position.z > -3.0:
				return ""
	return "no drone shot got past a destroyed reactor"


## A shot that enters the ship and the reactor at the same instant hits the
## ship, as robots win the same tie against the reactor for ship shots.
func test_an_exact_tie_goes_to_the_ship() -> String:
	var sim: Sim = Sim.new(345, 1)
	sim.ships[0].shield_recharge = 0.0
	var radius_mm: int = roundi(sim.ships[0].radius * RobotSpawn.SCALE)
	sim.set_reactor(ReactorState.parse_json(
		'{"position": [0, 0, 0], "radius": %s, "hull": 40, "meltdown_seconds": 2}' % (radius_mm / 1000.0)))
	if not is_equal_approx(sim.reactor.radius(), sim.ships[0].radius):
		return "could not give the reactor the ship's radius %s" % sim.ships[0].radius
	sim.projectiles.append(Projectile.new(Vector3(0, 0, -5), Vector3(0, 0, 120),
		Projectile.robot_owner(0), 60, 10.0))
	var hits: int = _fly(sim, 3)
	if hits != 1:
		return "%d ship hits on a tie with the reactor, expected 1" % hits
	if sim.reactor.hull != 40.0:
		return "the tie hurt the reactor: hull %s" % sim.reactor.hull
	return ""


func test_a_replay_with_a_reactor_reproduces_its_hash_from_text() -> String:
	var replay: Replay = Replay.new(345, 1)
	replay.reactor = ReactorState.parse_json(ON_LINE)
	var drone: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var cannon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	replay.robots.append(RobotSpawn.new(drone, Vector3i(0, 0, -10000), Vector3i(0, 0, 1000), cannon))
	for i: int in TICKS:
		replay.add_tick([ShipInput.new()] as Array[ShipInput])
	var first: Sim = replay.run()
	if first == null:
		return replay.run_error
	if not _undamaged(first.ships[0]):
		return "the replay's ship was hit through the reactor"
	var read: Replay = Replay.from_text(replay.to_text())
	if read.error != "":
		return read.error
	if read.reactor == null:
		return "the reactor did not survive the text"
	var second: Sim = read.run()
	if second == null:
		return read.run_error
	if second.state_hash() != first.state_hash():
		return "read back, the replay flew to %d, not %d" % [second.state_hash(), first.state_hash()]
	return ""


## Every committed suite replay ends on its pinned hash; since #332 the G2 one
## carries the level's reactor, the others none.
func test_the_m1_and_m2_suite_replays_still_end_on_their_hashes() -> String:
	var flown: int = 0
	for path: String in SUITES:
		var suite: AcceptanceSuite = AcceptanceSuite.load_file(path)
		if suite.error != "":
			return suite.error
		for step: AcceptanceStep in suite.steps:
			if step.replay_path == "" or not step.checks.has(AcceptanceStep.CHECK_FINAL_HASH):
				continue
			var replay: Replay = Replay.load_file(step.replay_path)
			if replay.error != "":
				return "%s: %s" % [step.replay_path, replay.error]
			var sim: Sim = replay.run()
			if sim == null:
				return "%s: %s" % [step.replay_path, replay.run_error]
			if sim.state_hash() != step.expected_hash:
				return "%s flew to %d, the suite pins %d" % [step.replay_path, sim.state_hash(), step.expected_hash]
			flown += 1
	if flown < 3:
		return "only %d suite replays were flown, expected the m1 one and both m2 ones" % flown
	return ""
