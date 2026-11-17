extends RefCounted

## Box-shaped meltdown entries, blast doors and cave-ins (#457, RUN-4, FLT-3, ARC-1,
## ARC-2, ARC-4): read with `size` in place of `radius`, a wall to ships from every
## face, a stop to shots, timed and hashed like spheres, and carried by replays.

## Out of every line of fire and flight below.
const FAR_REACTOR_JSON: String = '{"position": [15, 15, 15], "radius": 2, "hull": 40, "meltdown_seconds": 2}'
const REACTOR_JSON: String = '{"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 2}'
const PULSE: String = "res://data/weapons/pulse_cannon.json"
const LEVEL: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []'
## A 4 m cube centred at (0, 0, -10).
const CUBE: String = '[{"position": [0, 0, -10], "size": [4, 4, 4], "after_seconds": 0.02}]'
const CENTRE: Vector3 = Vector3(0, 0, -10)
const HALF: Vector3 = Vector3(2, 2, 2)


## One tick in, as in `test_meltdown_debris.gd`: one ship at the origin inside
## `min_corner`..(20, 20, 20), its start far off, the far reactor and the debris.
func _sim(min_corner: Vector3, debris_text: String) -> Sim:
	var sim: Sim = Sim.new(457, 1, BoxBounds.new(min_corner, Vector3(20, 20, 20)))
	sim.set_reactor(ReactorState.parse_json(FAR_REACTOR_JSON))
	if debris_text != "":
		sim.set_debris(MeltdownDebris.parse_json(debris_text))
	sim.ships[0].position = Vector3(-15, -15, 15)
	sim.step(_idle())
	sim.ships[0].position = Vector3.ZERO
	return sim


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


## How far the ship's surface is outside the cube; negative when it overlaps.
func _clearance(ship: ShipState) -> float:
	var local: Vector3 = ship.position - CENTRE
	var outside: Vector3 = local - local.clamp(-HALF, HALF)
	return outside.length() - ship.radius


func test_the_level_reads_a_box_in_whole_millimetres() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": [{"position": [0, 0, -30],'
		+ ' "size": [6.0004, 4, 0.5], "after_seconds": 2.5}, {"position": [0, 0, -50],'
		+ ' "radius": 1.5, "after_seconds": 3}]}')
	if level.error != "":
		return level.error
	var debris: MeltdownDebris = level.debris
	if debris.size() != 2 or not debris.is_box(0) or debris.is_box(1):
		return "read as %s" % debris.to_json()
	if debris.sizes_mm[0] != Vector3i(6000, 4000, 500) or debris.radii_mm[1] != 1500 \
			or debris.after_ticks[0] != 150:
		return "read as %s" % debris.to_json()
	if debris.box_size(1) != Vector3.ZERO or not debris.box_size(0).is_equal_approx(Vector3(6, 4, 0.5)):
		return "box sizes %s %s" % [debris.box_size(0), debris.box_size(1)]
	return ""


func test_bad_shapes_are_rejected_naming_the_index_and_key() -> String:
	var good: String = '{"position": [0, 0, -30], "size": [1, 1, 1], "after_seconds": 1}'
	var cases: Dictionary = {
		'[{"position": [0, 0, 0], "radius": 1, "size": [1, 1, 1], "after_seconds": 1}]':
			"debris 0: needs exactly one of \"radius\" and \"size\"",
		'[%s, {"position": [0, 0, 0], "after_seconds": 1}]' % good:
			"debris 1: needs exactly one of \"radius\" and \"size\"",
		'[%s, %s, {"position": [0, 0, 0], "size": [1, 0.09, 1], "after_seconds": 1}]' % [good, good]:
			"debris 2: size must be at least 0.1 m on every axis",
		'[{"position": [0, 0, 0], "size": [1, -1, 1], "after_seconds": 1}]':
			"debris 0: size must be at least 0.1 m on every axis",
		'[{"position": [0, 0, 0], "size": [1, 1], "after_seconds": 1}]':
			"debris 0: size must be a list of three numbers",
		'[{"position": [0, 0, 0], "size": 2, "after_seconds": 1}]':
			"debris 0: size must be a list of three numbers",
	}
	var failures: Array[String] = []
	for text: String in cases:
		var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": ' + text + "}")
		if level.error != cases[text]:
			failures.append("%s: got '%s'" % [text, level.error])
	if MeltdownDebris.parse_json('[{"position": [0, 0, 0], "size": [0.1, 0.1, 0.1], "after_seconds": 1}]') \
			.error != "":
		failures.append("a 0.1 m box was refused")
	return "\n".join(failures)


func test_spheres_write_no_size_and_boxes_round_trip() -> String:
	var spheres: MeltdownDebris = MeltdownDebris.parse_json(
		'[{"position": [0, 0, -12], "radius": 2, "after_seconds": 1}]')
	if spheres.to_json() != '[{"position":[0.0,0.0,-12.0],"radius":2.0,"after_seconds":1.0}]':
		return "spheres write %s" % spheres.to_json()
	var mixed: MeltdownDebris = MeltdownDebris.parse_json(
		'[{"position": [1, 2, -12], "size": [3.5, 0.25, 7], "after_seconds": 1},'
		+ ' {"position": [0, 0, -20], "radius": 1, "after_seconds": 2}]')
	var again: MeltdownDebris = MeltdownDebris.parse_json(mixed.to_json())
	if again.error != "" or again.sizes_mm != mixed.sizes_mm or again.radii_mm != mixed.radii_mm \
			or again.positions_mm != mixed.positions_mm or again.after_ticks != mixed.after_ticks:
		return "%s read back as %s (%s)" % [mixed.to_json(), again.to_json(), again.error]
	if mixed.fresh_copy().sizes_mm != mixed.sizes_mm:
		return "a fresh copy lost the box sizes"
	return ""


## From each of the six faces at 20 m/s: the ship bounces back, takes the wall
## damage and is never inside the cube at the end of a tick.
func test_a_ship_bounces_off_each_face_and_never_ends_inside() -> String:
	var failures: Array[String] = []
	for axis: int in 3:
		for side: float in [-1.0, 1.0]:
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = side
			var sim: Sim = _sim(Vector3(-20, -20, -40), CUBE)
			sim.reactor.apply_damage(40.0)
			var ship: ShipState = sim.ships[0]
			ship.position = CENTRE + normal * 3.1
			ship.velocity = -normal * 20.0
			var hit: bool = false
			for i: int in 20:
				sim.step(_idle())
				if _clearance(ship) < -0.0001:
					failures.append("%s: inside on tick %d at %s" % [normal, i, ship.position])
					break
				for event: SimEvent in sim.last_events:
					if event.kind == SimEvent.Kind.WALL_IMPACT:
						hit = hit or event.vector.is_equal_approx(normal)
			if not hit or ship.velocity.dot(normal) <= 0.0:
				failures.append("%s: no bounce, velocity %s" % [normal, ship.velocity])
			if ship.shield >= ship.max_shield:
				failures.append("%s: a 20 m/s hit dealt no damage" % normal)
	return "\n".join(failures)


## Head on, a box face is a wall: the same place, speed and damage as a ship
## meeting a wall at the face.
func test_a_box_face_matches_a_wall() -> String:
	var into_box: Sim = _sim(Vector3(-20, -20, -40), CUBE)
	var into_wall: Sim = _sim(Vector3(-20, -20, -8), "")
	for sim: Sim in [into_box, into_wall]:
		sim.reactor.apply_damage(40.0)
		sim.ships[0].position = Vector3(0.5, -0.3, -6.9)
		sim.ships[0].velocity = Vector3(1, 0, -20)
	for i: int in 3:
		into_box.step(_idle())
		into_wall.step(_idle())
	var a: ShipState = into_box.ships[0]
	var b: ShipState = into_wall.ships[0]
	if not a.velocity.is_equal_approx(b.velocity) or not a.position.is_equal_approx(b.position):
		return "box %s %s, wall %s %s" % [a.position, a.velocity, b.position, b.velocity]
	if not is_equal_approx(a.shield, b.shield) or a.shield >= a.max_shield:
		return "shield %s off the box, %s off the wall" % [a.shield, b.shield]
	return ""


## Corners and edges: a ship aimed at one is pushed out along the line from the
## nearest point and is never left inside.
func test_a_ship_aimed_at_corners_and_edges_never_ends_inside() -> String:
	var failures: Array[String] = []
	for aim: Vector3 in [Vector3(1, 1, 1), Vector3(-1, 1, 0), Vector3(0, -1, -1), Vector3(1, 0, -1)]:
		var sim: Sim = _sim(Vector3(-20, -20, -40), CUBE)
		sim.reactor.apply_damage(40.0)
		var ship: ShipState = sim.ships[0]
		ship.position = CENTRE + aim * 2.0 + aim.normalized() * 1.5
		ship.velocity = -aim.normalized() * 25.0
		for i: int in 20:
			sim.step(_idle())
			if _clearance(ship) < -0.0001:
				failures.append("%s: inside on tick %d at %s" % [aim, i, ship.position])
				break
	return "\n".join(failures)


func test_a_ship_inside_a_box_when_it_appears_is_pushed_out_unhurt() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), CUBE)
	sim.reactor.apply_damage(40.0)
	sim.ships[0].position = CENTRE + Vector3(0.2, 0.5, 0.1)
	for i: int in 30:
		sim.step(_idle())
		if sim.debris.is_solid(0) and _clearance(sim.ships[0]) < -0.0001:
			return "still inside %d ticks in at %s" % [i, sim.ships[0].position]
	if not sim.debris.is_solid(0):
		return "the box never fell"
	if sim.ships[0].shield != sim.ships[0].max_shield or sim.ships[0].hull != sim.ships[0].max_hull:
		return "a ship at rest took damage being pushed out"
	return ""


func test_before_it_falls_a_box_neither_pushes_nor_stops_shots() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), CUBE)
	sim.ships[0].position = CENTRE + Vector3(0, 0.5, 0)
	sim.projectiles.append(Projectile.new(Vector3(5, -1.8, -9), Vector3(-120, 0, 0), 0, 30, 8.0))
	var passed: bool = false
	for i: int in 10:
		sim.step(_idle())
		for projectile: Projectile in sim.projectiles:
			passed = passed or projectile.position.x < -3.0
	if sim.debris.is_solid(0):
		return "the box fell with the reactor intact"
	if sim.ships[0].position.distance_to(CENTRE + Vector3(0, 0.5, 0)) > 0.001:
		return "a box that has not fallen moved the ship to %s" % sim.ships[0].position
	if not passed:
		return "a box that has not fallen stopped a shot"
	return ""


func test_shots_of_both_sides_stop_at_a_solid_box_face() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), CUBE)
	sim.reactor.apply_damage(40.0)
	sim.step(_idle())
	sim.ships[0].position = Vector3(0, 0, 15)
	sim.projectiles.append(Projectile.new(Vector3(0, 1, -3), Vector3(0, 0, -120), 0, 60, 8.0))
	sim.projectiles.append(Projectile.new(Vector3(-1, 0, -25), Vector3(0, 0, 120),
		Projectile.robot_owner(0), 60, 30.0))
	for i: int in 20:
		sim.step(_idle())
		for projectile: Projectile in sim.projectiles:
			if absf(projectile.position.z - CENTRE.z) <= 2.0:
				return "a shot is inside the box at %s" % projectile.position
	if not sim.projectiles.is_empty():
		return "%d shots got past the box" % sim.projectiles.size()
	var face: float = DebrisShapes.box_entry(Vector3(0, 1, -3), Vector3(0, 1, -13), CENTRE, HALF)
	if not is_equal_approx(face, 0.5):
		return "a shot from 5 m off the face enters at %s of 10 m" % face
	if DebrisShapes.box_entry(Vector3(3, 0, -3), Vector3(3, 0, -17), CENTRE, HALF) != -1.0:
		return "a shot beside the box entered it"
	return ""


## Shoots the reactor, then flies into a door that fell in the way.
func _replay() -> Replay:
	var replay: Replay = Replay.new(457, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON)
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	replay.debris = MeltdownDebris.parse_json(
		'[{"position": [0, 0, -12], "size": [8, 8, 0.5], "after_seconds": 0.1}]')
	var fire: ShipInput = ShipInput.new()
	fire.fire_primary = true
	for i: int in 90:
		replay.add_tick([fire])
	for i: int in 120:
		replay.add_tick([ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO)])
	return replay


func test_a_replay_with_a_box_gives_the_same_hash_twice_and_from_text() -> String:
	var replay: Replay = _replay()
	var first: Sim = replay.run()
	if first == null or not first.reactor.destroyed:
		return "the run did not destroy the reactor: %s" % replay.run_error
	if first.ships[0].position.z < -10.76:
		return "the ship flew through the door to %s" % first.ships[0].position
	var second: Sim = _replay().run()
	if second.state_hash() != first.state_hash():
		return "the same level and inputs gave two hashes"
	replay.expected_hash = first.state_hash()
	var text: String = replay.to_text()
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	if read.debris.sizes_mm != replay.debris.sizes_mm:
		return "the debris line lost the box: %s" % read.debris.to_json()
	var again: Sim = read.run()
	if again == null or again.state_hash() != read.expected_hash:
		return "the replay read back from text ends elsewhere"
	if read.to_text() != text:
		return "the debris line does not read back to itself"
	return ""
