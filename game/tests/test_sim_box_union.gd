extends RefCounted

## The simulation's walls as a union of boxes (GEN-5, FLT-3, ARC-1, ARC-2,
## #285): ships, robots, salvage and shots keep to a multi-box level, and a
## one-box union is the old single `BoxBounds` tick for tick.

const DRONE: String = "res://data/robots/drone.json"
const NEEDLER: String = "res://data/robots/needler.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const SEED: int = 285


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


func _union(list: Array[BoxBounds]) -> BoxUnion:
	return BoxUnion.new(list)


## A room and a 4 m tunnel leaving its far wall, overlapping for 5 m
## (z -20..-15), as in `test_box_union.gd`.
func _room_and_tunnel() -> BoxUnion:
	var room: BoxBounds = BoxBounds.new(Vector3(-5.0, -5.0, -20.0), Vector3(5.0, 5.0, 0.0))
	var tunnel: BoxBounds = BoxBounds.new(Vector3(-2.0, -2.0, -60.0), Vector3(2.0, 2.0, -15.0))
	return _union([room, tunnel])


## An L: a corridor along -z, and one along +x leaving its far end. They share
## the corner cube x -3..3, z -30..-24.
func _l_corner() -> BoxUnion:
	var down: BoxBounds = BoxBounds.new(Vector3(-3.0, -3.0, -30.0), Vector3(3.0, 3.0, 0.0))
	var across: BoxBounds = BoxBounds.new(Vector3(-3.0, -3.0, -30.0), Vector3(40.0, 3.0, -24.0))
	return _union([down, across])


func _input(thrust: Vector3i, turn: Vector3i, fire: bool) -> Array[ShipInput]:
	var inputs: Array[ShipInput] = [ShipInput.new(thrust, turn, false, false, fire)]
	return inputs


func _idle() -> Array[ShipInput]:
	return _input(Vector3i.ZERO, Vector3i.ZERO, false)


## An armed ship facing a drone, in a box, firing in bursts and then flying
## about so it hits walls. Built either from the box (the constructor) or from
## a one-box union set with `set_walls`.
func _duel(box: BoxBounds, as_union: bool) -> Sim:
	var sim: Sim = Sim.new(SEED, 1, null if as_union else box)
	if as_union:
		if not sim.set_walls(_union([box])):
			return null
	sim.ships[0].primary_slots[0] = _cannon()
	sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -25.0), Basis.IDENTITY, _cannon())
	return sim


func _duel_input(tick: int) -> Array[ShipInput]:
	# The drone gets a minute of shooting before the ship fires back.
	if tick < 240:
		return _input(Vector3i.ZERO, Vector3i.ZERO, tick >= 60)
	var thrust: Vector3i = Vector3i(1000 if tick % 90 < 45 else -1000,
		1000 if tick % 70 < 30 else 0, -1000)
	var turn: Vector3i = Vector3i(0, 800 if tick % 120 < 20 else 0, 0)
	return _input(thrust, turn, false)


func test_one_box_union_hashes_as_the_box_with_a_robot_firing_and_a_drop() -> String:
	var box: BoxBounds = BoxBounds.new(Vector3(-6.0, -5.0, -45.0), Vector3(6.0, 5.0, 5.0))
	var old: Sim = _duel(box, false)
	var union: Sim = _duel(box, true)
	if union == null:
		return "set_walls refused a one-box union before the first tick"
	var robot_shots: int = 0
	var drops: int = 0
	var wall_hits: int = 0
	for tick: int in 600:
		old.step(_duel_input(tick))
		union.step(_duel_input(tick))
		if union.state_hash() != old.state_hash():
			return "tick %d: one-box union hash differs from BoxBounds" % tick
		for projectile: Projectile in union.projectiles:
			if projectile.is_robot_owned():
				robot_shots += 1
		for event: SimEvent in union.last_events:
			if event.kind == SimEvent.Kind.SALVAGE_DROPPED:
				drops += 1
			elif event.kind == SimEvent.Kind.WALL_IMPACT:
				wall_hits += 1
	if robot_shots == 0 or drops == 0 or wall_hits == 0:
		return "run proves too little: robot shots %d, drops %d, wall hits %d" % [
			robot_shots, drops, wall_hits]
	return ""


## The ship waits round the corner of the L; a needler (a chaser) starts at
## the top of the other leg and goes after it.
func _chase() -> Sim:
	var sim: Sim = Sim.new(SEED, 1)
	sim.set_walls(_l_corner())
	sim.set_start_pose(0, Vector3(30.0, 0.0, -27.0), Basis.IDENTITY)
	var needler: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(NEEDLER))
	# Unarmed, so the chase does not end with the ship shot down before the
	# needler reaches the corner.
	sim.spawn_robot(needler, Vector3(0.0, 0.0, -5.0), Basis.IDENTITY)
	return sim


func test_robot_chasing_round_the_corner_stays_held_by_the_union() -> String:
	var sim: Sim = _chase()
	# A hair under the radius: positions are stored in 32-bit floats, so one
	# placed exactly on a wall can read a hair past it.
	var radius: float = sim.robots[0].def.radius - 0.001
	for tick: int in 900:
		sim.step(_idle())
		if sim.robots.is_empty():
			return "tick %d: the robot is gone" % tick
		var at: Vector3 = sim.robots[0].position
		if not sim.walls.holds(at, radius):
			return "tick %d: robot at %s is in the rock" % [tick, at]
	# The ship sits wholly in the second box, so the union must leave it be.
	if not sim.ships[0].position.is_equal_approx(Vector3(30.0, 0.0, -27.0)):
		return "ship moved to %s while waiting in the second leg" % sim.ships[0].position
	var end: Vector3 = sim.robots[0].position
	# Past x 3 is only in the second leg: the first box alone would have held
	# it at the corner.
	if end.x <= 3.0:
		return "robot stopped at %s, never got round the corner" % end
	return ""


func test_salvage_dropped_in_the_narrow_box_stays_in_it() -> String:
	var sim: Sim = Sim.new(SEED, 1)
	sim.set_walls(_room_and_tunnel())
	var tunnel: BoxBounds = sim.walls.boxes[1]
	# Stands in for a part dropped by a robot dying at speed, thrown at the
	# tunnel's corner and back towards the room.
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3(0.0, 0.0, -40.0),
		Vector3(25.0, -20.0, 30.0)))
	var touched_side: bool = false
	for tick: int in 240:
		sim.step(_idle())
		var item: SalvageItem = sim.salvage[0]
		# A hair under the radius, as in the chase test.
		if not tunnel.holds(item.position, SalvageItem.RADIUS - 0.001):
			return "tick %d: item at %s left the tunnel" % [tick, item.position]
		if is_equal_approx(item.position.x, 2.0 - SalvageItem.RADIUS):
			touched_side = true
	if not touched_side:
		return "the item never reached the tunnel side, so it proves nothing"
	if not sim.salvage[0].is_at_rest():
		return "item still moving at %s" % sim.salvage[0].velocity
	return ""


## A sim in the room-and-tunnel level whose armed ship sits in the room
## facing `orientation`, and fires once on the first tick.
func _one_shot(orientation: Basis) -> Sim:
	var sim: Sim = Sim.new(SEED, 1)
	sim.set_walls(_room_and_tunnel())
	sim.ships[0].primary_slots[0] = _cannon()
	sim.set_start_pose(0, Vector3(0.0, 0.0, -5.0), orientation)
	sim.step(_input(Vector3i.ZERO, Vector3i.ZERO, true))
	return sim


func test_shot_through_the_opening_flies_on_into_the_second_box() -> String:
	var sim: Sim = _one_shot(Basis.IDENTITY)
	if sim.projectiles.size() != 1:
		return "%d shots after firing once" % sim.projectiles.size()
	var deepest: float = 0.0
	for tick: int in 60:
		sim.step(_idle())
		if sim.projectiles.is_empty():
			break
		deepest = minf(deepest, sim.projectiles[0].position.z)
	# z below -20 is only in the tunnel.
	if deepest > -55.0:
		return "shot only reached z %f before it was removed" % deepest
	if not sim.projectiles.is_empty():
		return "shot at %s is past the tunnel's end" % sim.projectiles[0].position
	return ""


func test_shot_into_rock_is_removed() -> String:
	# Facing +x, at the room's side wall 5 m away.
	var sim: Sim = _one_shot(Basis(Vector3.UP, -PI * 0.5))
	if sim.projectiles.size() != 1:
		return "%d shots after firing once" % sim.projectiles.size()
	var lifetime: int = sim.projectiles[0].ticks_left
	for tick: int in 10:
		sim.step(_idle())
		if sim.projectiles.is_empty():
			if tick + 1 >= lifetime:
				return "shot only expired, it was not removed by the rock"
			return ""
		if sim.projectiles[0].position.x > 5.0:
			return "tick %d: shot at %s is in the rock" % [tick, sim.projectiles[0].position]
	return "shot still flying after 10 ticks at %s" % sim.projectiles[0].position


func test_two_identical_runs_in_the_l_give_identical_hashes() -> String:
	var first: Sim = _chase()
	var second: Sim = _chase()
	for tick: int in 600:
		var fire: bool = tick % 50 < 5
		first.step(_input(Vector3i(0, 0, -1000), Vector3i.ZERO, fire))
		second.step(_input(Vector3i(0, 0, -1000), Vector3i.ZERO, fire))
		if first.state_hash() != second.state_hash():
			return "tick %d: identical runs differ" % tick
	return ""


func test_set_walls_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(SEED, 1)
	var empty: Array[BoxBounds] = []
	if sim.set_walls(BoxUnion.new(empty)):
		return "an empty union was accepted"
	var level: BoxUnion = _l_corner()
	if not sim.set_walls(level) or sim.walls != level:
		return "a two-box union was refused before the first tick"
	if sim.bounds != level.boxes[0]:
		return "bounds is not the first box of the union"
	sim.step(_idle())
	if sim.set_walls(null) or sim.walls != level:
		return "walls changed after the first tick"
	var open: Sim = Sim.new(SEED, 1, BoxBounds.new(-Vector3.ONE, Vector3.ONE))
	if not open.set_walls(null) or open.walls != null or open.bounds != null:
		return "null did not clear the walls to open space"
	return ""
