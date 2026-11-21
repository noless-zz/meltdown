extends RefCounted

## Falling debris during the meltdown (#355, RUN-4, FLT-3, ARC-1, ARC-2, ARC-4):
## read from the level file, solid from a set tick after the reactor dies, a
## wall to ships and a stop to shots, in the hash only when a level has debris,
## and carried by replays.

const G2_LEVEL: String = "res://data/levels/g2_level.json"
const PULSE: String = "res://data/weapons/pulse_cannon.json"
## 40 hull against the pulse cannon's 8 damage: five shots. Two seconds of meltdown.
const REACTOR_JSON: String = '{"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 2}'
## Out of every line of fire and flight below.
const FAR_REACTOR_JSON: String = '{"position": [15, 15, 15], "radius": 2, "hull": 40, "meltdown_seconds": 2}'
const LEVEL: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []'


func _debris(text: String) -> MeltdownDebris:
	return MeltdownDebris.parse_json(text)


## One tick in: one ship at the origin, its start (and exit) far off, inside `min_corner`..(20, 20, 20), with the
## far reactor and `debris_text`, or no debris for "".
func _sim(min_corner: Vector3, debris_text: String) -> Sim:
	var sim: Sim = Sim.new(355, 1, BoxBounds.new(min_corner, Vector3(20, 20, 20)))
	sim.set_reactor(ReactorState.parse_json(FAR_REACTOR_JSON))
	if debris_text != "":
		sim.set_debris(_debris(debris_text))
	# The first tick records the start, and with it the exit, far away, so the
	# ship has not escaped once the reactor dies.
	sim.ships[0].position = Vector3(-15, -15, 15)
	sim.step(_idle())
	sim.ships[0].position = Vector3.ZERO
	return sim


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


func _fire() -> Array[ShipInput]:
	var input: ShipInput = ShipInput.new()
	input.fire_primary = true
	return [input]


func _forward() -> Array[ShipInput]:
	return [ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO)]


func _loadout() -> ShipLoadout:
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	return loadout


func test_the_level_reads_debris_in_whole_millimetres_and_ticks() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": [{"position": [1.0004, -2, -30],'
		+ ' "radius": 1.5, "after_seconds": 2.5}]}')
	if level.error != "":
		return level.error
	var debris: MeltdownDebris = level.debris
	if debris == null or debris.size() != 1:
		return "debris not read"
	if debris.positions_mm[0] != Vector3i(1000, -2000, -30000) or debris.radii_mm[0] != 1500 \
			or debris.after_ticks[0] != 150:
		return "read as %s" % debris.to_json()
	var without: LevelDef = LevelDef.parse_json(LEVEL + "}")
	if without.error != "" or without.debris != null:
		return "a level without debris got some: %s" % without.error
	return ""


func test_bad_debris_is_rejected_naming_the_index_and_key() -> String:
	var good: String = '{"position": [0, 0, -30], "radius": 1, "after_seconds": 1}'
	var cases: Dictionary = {
		'{}': "debris: must be a list",
		'[3]': "debris 0: must be a JSON object",
		'[%s, {"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "mass": 2}]' % good:
			"debris 1: unknown key \"mass\"",
		'[{"position": [0, 0, 0], "radius": 1}]': "debris 0: missing key \"after_seconds\"",
		'[%s, %s, {"position": [0, 0, 0], "radius": 0, "after_seconds": 1}]' % [good, good]:
			"debris 2: radius must be a number above zero",
		'[{"position": [0, 0, 0], "radius": 1, "after_seconds": -1}]':
			"debris 0: after_seconds must be a number of at least zero",
		'[{"position": [0, 0, 0], "radius": 1, "after_seconds": 0}]':
			"debris 0: after_seconds must be at least one tick",
		'[{"position": [0, 0], "radius": 1, "after_seconds": 1}]': "debris 0: position",
	}
	var failures: Array[String] = []
	for text: String in cases:
		var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": ' + text + "}")
		if not level.error.begins_with(cases[text]):
			failures.append("%s: got '%s'" % [text, level.error])
		elif level.union.boxes.size() != 0:
			failures.append("%s: a rejected level kept its boxes" % text)
	return "\n".join(failures)


func test_nothing_is_solid_while_the_reactor_is_intact() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), '[{"position": [0, 0, -10], "radius": 2, "after_seconds": 0.02}]')
	sim.ships[0].position = Vector3(0, 0, -10)
	for i: int in 120:
		sim.step(_idle())
	if sim.debris.is_solid(0):
		return "debris fell with the reactor intact"
	if sim.ships[0].position.distance_to(Vector3(0, 0, -10)) > 0.001:
		return "the ship was pushed by debris that has not fallen: %s" % sim.ships[0].position
	return ""


## The reactor dies to a shot on tick T; debris after 30 ticks is solid from tick
## T + 30, when the countdown has gone down by 30, and stays solid.
func test_debris_is_solid_from_exactly_its_tick_after_the_reactor_dies() -> String:
	var sim: Sim = Sim.new(355, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	sim.set_reactor(ReactorState.parse_json(REACTOR_JSON))
	sim.equip(_loadout())
	sim.set_debris(_debris('[{"position": [8, 0, -15], "radius": 1, "after_seconds": 0.5},'
		+ ' {"position": [-8, 0, -15], "radius": 1, "after_seconds": 1}]'))
	# The first tick records the exit 8 m behind the ship, so it does not
	# escape when the reactor dies and the countdown keeps running (#750).
	sim.ships[0].position = Vector3(0, 0, 8)
	sim.step(_idle())
	sim.ships[0].position = Vector3.ZERO
	var died_on: int = -1
	for i: int in 200:
		var tick: int = sim.tick
		sim.step(_fire())
		if sim.debris.is_solid(0) or sim.debris.is_solid(1):
			return "solid on tick %d, before the reactor died" % tick
		if sim.reactor.destroyed:
			died_on = tick
			break
	if died_on < 0:
		return "the reactor never died"
	for k: int in range(1, 30):
		sim.step(_idle())
		if sim.debris.is_solid(0):
			return "solid %d ticks after the reactor died, expected 30" % k
	sim.step(_idle())
	if not sim.debris.is_solid(0) or sim.debris.is_solid(1):
		return "30 ticks after: first %s, second %s" % [sim.debris.is_solid(0), sim.debris.is_solid(1)]
	if sim.reactor.meltdown_ticks_left != sim.reactor.meltdown_ticks() - 30:
		return "the countdown is at %d" % sim.reactor.meltdown_ticks_left
	for i: int in 300:
		sim.step(_idle())
	if not sim.debris.is_solid(0) or not sim.debris.is_solid(1):
		return "debris did not stay solid"
	return ""


## Head on, debris is a wall: a ship flying into it at 20 m/s ends the tick where
## and as fast as the same ship meeting a wall at the debris surface, and takes
## the same damage.
func test_a_ship_flying_into_debris_bounces_and_takes_the_wall_damage() -> String:
	return _compare_with_wall(20.0, true)


func test_scraping_debris_below_the_min_speed_deals_no_damage() -> String:
	return _compare_with_wall(3.0, false)


func _compare_with_wall(speed: float, hurts: bool) -> String:
	# Debris centre -10, radius 2, ship radius 1: the ship's centre stops at -7,
	# as it does in a box whose wall is at -8.
	var into_debris: Sim = _sim(Vector3(-20, -20, -40), '[{"position": [0, 0, -10], "radius": 2, "after_seconds": 0.02}]')
	var into_wall: Sim = _sim(Vector3(-20, -20, -8), "")
	for sim: Sim in [into_debris, into_wall]:
		sim.reactor.apply_damage(40.0)
		sim.ships[0].position = Vector3(0, 0, -6.9)
		sim.ships[0].velocity = Vector3(0, 0, -speed)
	var impact: SimEvent = null
	for i: int in 3:
		into_debris.step(_idle())
		into_wall.step(_idle())
		for event: SimEvent in into_debris.last_events:
			if event.kind == SimEvent.Kind.WALL_IMPACT:
				impact = event
	var a: ShipState = into_debris.ships[0]
	var b: ShipState = into_wall.ships[0]
	if impact == null or not impact.vector.is_equal_approx(Vector3(0, 0, 1)):
		return "no wall impact event pointing out of the debris: %s" % str(impact)
	if a.velocity.z <= 0.0:
		return "the ship did not bounce: velocity %s" % a.velocity
	if not a.velocity.is_equal_approx(b.velocity) or not a.position.is_equal_approx(b.position):
		return "debris %s %s, wall %s %s" % [a.position, a.velocity, b.position, b.velocity]
	if not is_equal_approx(a.hull, b.hull) or not is_equal_approx(a.shield, b.shield):
		return "hull and shield %s %s off debris, %s %s off the wall" % [a.hull, a.shield, b.hull, b.shield]
	# Damage goes to the shield first.
	var lost: float = a.max_hull + a.max_shield - a.hull - a.shield
	if hurts and lost <= 0.0:
		return "a %s m/s hit dealt no damage" % speed
	if not hurts and lost != 0.0:
		return "a %s m/s scrape dealt %s damage" % [speed, lost]
	return ""


func test_a_ship_inside_debris_when_it_appears_is_pushed_out() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), '[{"position": [0, 0, -10], "radius": 2, "after_seconds": 0.05}]')
	sim.reactor.apply_damage(40.0)
	sim.ships[0].position = Vector3(0, 0.5, -10)
	for i: int in 60:
		sim.step(_idle())
		var distance: float = sim.ships[0].position.distance_to(Vector3(0, 0, -10))
		if sim.debris.is_solid(0) and distance < 3.0 - 0.001:
			return "still inside %d ticks in, %s m from the centre" % [i, distance]
	if not sim.debris.is_solid(0):
		return "the debris never fell"
	if sim.ships[0].hull != sim.ships[0].max_hull or sim.ships[0].shield != sim.ships[0].max_shield:
		return "a ship at rest took damage being pushed out"
	return ""


func test_shots_of_both_sides_stop_on_solid_debris() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), '[{"position": [0, 0, -15], "radius": 2, "after_seconds": 0.02}]')
	sim.reactor.apply_damage(40.0)
	sim.step(_idle())
	sim.projectiles.append(Projectile.new(Vector3(0, 0, -5), Vector3(0, 0, -120), 0, 60, 8.0))
	sim.projectiles.append(Projectile.new(Vector3(0, 0, -30), Vector3(0, 0, 120),
		Projectile.robot_owner(0), 60, 30.0))
	for i: int in 20:
		sim.step(_idle())
		for projectile: Projectile in sim.projectiles:
			if absf(projectile.position.z + 15.0) < 2.0:
				return "a shot is inside the debris at %s" % projectile.position
	if not sim.projectiles.is_empty():
		return "%d shots got past the debris" % sim.projectiles.size()
	if sim.ships[0].shield != sim.ships[0].max_shield:
		return "the robot shot reached the ship"
	return ""


func test_the_hash_is_unchanged_for_levels_without_debris() -> String:
	var plain: Sim = _sim(Vector3(-20, -20, -40), "")
	var empty: Sim = _sim(Vector3(-20, -20, -40), "[]")
	var with: Sim = _sim(Vector3(-20, -20, -40), '[{"position": [0, 0, -15], "radius": 2, "after_seconds": 1}]')
	if empty.debris != null:
		return "an empty list was kept as debris"
	if plain.state_hash() != empty.state_hash():
		return "an empty debris list changed the hash"
	if plain.state_hash() == with.state_hash():
		return "debris did not join the hash"
	return ""


func test_debris_is_set_only_before_the_first_tick() -> String:
	var sim: Sim = _sim(Vector3(-20, -20, -40), "")
	if sim.set_debris(_debris('[{"position": [0, 0, -15], "radius": 2, "after_seconds": 1}]')) \
			or sim.debris != null:
		return "debris was set after the first tick"
	return ""


## Shoots the reactor, then flies into debris that fell in the way.
func _replay(with_debris: bool) -> Replay:
	var replay: Replay = Replay.new(355, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON)
	replay.loadout = _loadout()
	if with_debris:
		replay.debris = _debris('[{"position": [0, 0, -12], "radius": 2, "after_seconds": 0.1}]')
	for i: int in 90:
		replay.add_tick(_fire())
	for i: int in 120:
		replay.add_tick(_forward())
	return replay


func test_a_replay_with_debris_reproduces_its_hash_from_text() -> String:
	var replay: Replay = _replay(true)
	var first: Sim = replay.run()
	if first == null or not first.reactor.destroyed:
		return "the run did not destroy the reactor: %s" % replay.run_error
	var without: Sim = _replay(false).run()
	if without.state_hash() == first.state_hash():
		return "debris made no difference to the run"
	if first.ships[0].position.z < -9.0:
		return "the ship flew through the debris to %s" % first.ships[0].position
	replay.expected_hash = first.state_hash()
	var text: String = replay.to_text()
	var lines: PackedStringArray = text.split("\n")
	if not lines[5].begins_with("reactor {") or not lines[6].begins_with("debris ["):
		return "header %s" % str(lines.slice(0, 7))
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	var again: Sim = read.run()
	if again == null or again.state_hash() != read.expected_hash:
		return "the replay read back from text ends elsewhere"
	if read.to_text() != text:
		return "the debris line does not read back to itself"
	return ""


func test_a_debris_line_in_an_older_format_names_the_line() -> String:
	var line: String = 'debris [{"position": [0, 0, -12], "radius": 2, "after_seconds": 1}]'
	var text: String = "meltdown-replay 14\nseed 1\nships 1\n" + line + "\ninputs\n"
	var old: Replay = Replay.from_text(text)
	if old.error != "line 4: a debris line needs format version 15 or later":
		return "got '%s'" % old.error
	var twice: Replay = Replay.from_text(text.replace("replay 14", "replay 15")
		.replace("inputs", line + "\ninputs"))
	if twice.error != "line 5: 'debris' appears twice":
		return "got '%s'" % twice.error
	var bad: Replay = Replay.from_text(text.replace("replay 14", "replay 15").replace('"radius": 2', '"radius": -2'))
	if bad.error != "line 4: debris 0: radius must be a number above zero":
		return "got '%s'" % bad.error
	return ""


## The placeholder in G2's shaft (box 1) leaves at least 5 m beside it on a
## horizontal axis, so a ship of radius 1 can pass with room to spare.
func test_the_g2_level_has_debris_in_the_shaft_with_room_beside_it() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return level.error
	if level.debris == null or level.debris.size() != 1:
		return "G2 has no debris"
	var centre: Vector3 = level.debris.position(0)
	var radius: float = level.debris.radius(0)
	var shaft: BoxBounds = level.union.boxes[1]
	if not shaft.holds(centre, radius):
		return "the debris is not in the shaft"
	var widest: float = 0.0
	for axis: int in [0, 2]:
		widest = maxf(widest, shaft.max_corner[axis] - (centre[axis] + radius))
		widest = maxf(widest, (centre[axis] - radius) - shaft.min_corner[axis])
	if widest < 5.0:
		return "only %s m beside the debris" % widest
	return ""
