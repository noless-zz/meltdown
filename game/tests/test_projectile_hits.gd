extends RefCounted

## `ProjectileHits`, split out of `Sim` (#260), called directly: the whole
## behaviour through `Sim.step` stays covered by `test_robot_hits.gd` and the
## pinned hashes (CMB-1, CMB-2, ARC-1).

const DRONE: String = "res://data/robots/drone.json"


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


## A shot crossing a robot's centre on its next tick, at 600 m/s (10 m a tick).
func _shot_through(target: Vector3, owner: int, damage: float) -> Projectile:
	return Projectile.new(target + Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -600.0),
		owner, 60, damage)


func test_a_killing_ship_shot_is_removed_and_names_its_killer() -> String:
	var sim: Sim = Sim.new(1, 2)
	var drone: RobotDef = _drone()
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -30.0), Basis.IDENTITY)
	sim.projectiles.append(_shot_through(Vector3(0.0, 0.0, -30.0), 1, drone.hull))
	var events: Array[SimEvent] = []
	var killers: Dictionary = {}
	ProjectileHits.advance(sim, events, killers)
	if not sim.projectiles.is_empty():
		return "the shot that hit is still flying"
	if events.size() != 2 or events[0].kind != SimEvent.Kind.ROBOT_HIT \
			or events[1].kind != SimEvent.Kind.ROBOT_DESTROYED:
		return "expected ROBOT_HIT then ROBOT_DESTROYED, got %d events" % events.size()
	if killers.get(0, -1) != 1:
		return "killer of robot 0 is %s, expected ship 1" % killers.get(0, -1)
	return ""


func test_a_robot_shot_hits_the_ship_and_no_robot() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.spawn_robot(_drone(), Vector3(0.0, 0.0, 0.0), Basis.IDENTITY)
	var shield: float = sim.ships[0].shield
	sim.projectiles.append(_shot_through(Vector3.ZERO, Projectile.robot_owner(0), 5.0))
	var events: Array[SimEvent] = []
	var killers: Dictionary = {}
	ProjectileHits.advance(sim, events, killers)
	if not sim.projectiles.is_empty():
		return "the shot that hit is still flying"
	if events.size() != 1 or events[0].kind != SimEvent.Kind.SHIP_HIT or events[0].ship != 0:
		return "expected one SHIP_HIT on ship 0"
	if not is_equal_approx(sim.ships[0].shield, shield - 5.0):
		return "shield %s, expected %s" % [sim.ships[0].shield, shield - 5.0]
	if sim.robots[0].hull != _drone().hull or not killers.is_empty():
		return "a robot's own shot damaged a robot"
	return ""


func test_a_missing_shot_flies_on_until_its_lifetime_ends() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.projectiles.append(Projectile.new(Vector3(0.0, 0.0, -50.0),
		Vector3(0.0, 0.0, -60.0), 0, 2, 5.0))
	var events: Array[SimEvent] = []
	var killers: Dictionary = {}
	ProjectileHits.advance(sim, events, killers)
	if sim.projectiles.size() != 1 or not events.is_empty():
		return "a shot with a tick left was removed or hit something"
	if not sim.projectiles[0].position.is_equal_approx(Vector3(0.0, 0.0, -51.0)):
		return "shot at %s after one tick" % sim.projectiles[0].position
	ProjectileHits.advance(sim, events, killers)
	if not sim.projectiles.is_empty():
		return "the shot outlived its lifetime"
	return ""


func test_a_shot_leaving_the_walls_is_removed() -> String:
	var sim: Sim = Sim.new(1, 1, BoxBounds.new(Vector3(-5.0, -5.0, -5.0), Vector3(5.0, 5.0, 5.0)))
	sim.projectiles.append(Projectile.new(Vector3(0.0, 0.0, -4.5),
		Vector3(0.0, 0.0, -60.0), 0, 60, 5.0))
	var events: Array[SimEvent] = []
	ProjectileHits.advance(sim, events, {})
	if not sim.projectiles.is_empty():
		return "a shot outside the walls is still flying"
	return ""
