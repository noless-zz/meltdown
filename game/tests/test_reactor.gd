extends RefCounted

## The level's reactor in the simulation (#310, RUN-2, ARC-1, ARC-2, ARC-4): ship
## shots wear its hull down, robot shots do not, its destruction is reported
## once and starts the meltdown countdown on the next tick, and replays carry it.

const G2_LEVEL: String = "res://data/levels/g2_level.json"
const PULSE: String = "res://data/weapons/pulse_cannon.json"
## 40 hull against the pulse cannon's 8 damage: five shots. Two seconds of meltdown.
const REACTOR_JSON: String = '{"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 2}'
const LEVEL_WITHOUT: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []'


func _reactor() -> ReactorState:
	return ReactorState.parse_json(REACTOR_JSON)


## One ship at the origin facing -z, in one box, with the reactor 30 m ahead.
func _sim(armed: bool) -> Sim:
	var sim: Sim = Sim.new(310, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	sim.set_reactor(_reactor())
	if armed:
		var loadout: ShipLoadout = ShipLoadout.new()
		loadout.set_slot("primary", 0, "pulse_cannon",
			WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
		sim.equip(loadout)
	return sim


func _fire() -> Array[ShipInput]:
	var input: ShipInput = ShipInput.new()
	input.fire_primary = true
	return [input]


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


## Steps `sim` until its reactor is destroyed, at most `limit` ticks. Returns the
## REACTOR_DESTROYED events seen over every tick.
func _fire_until_destroyed(sim: Sim, limit: int) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	for i: int in limit:
		sim.step(_fire())
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.REACTOR_DESTROYED:
				events.append(event)
		if sim.reactor.destroyed:
			break
	return events


func _replay(hull: float) -> Replay:
	var replay: Replay = Replay.new(310, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON.replace('"hull": 40', '"hull": %s' % hull))
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	for i: int in 120:
		replay.add_tick(_fire())
	return replay


func test_a_level_without_a_reactor_parses_as_before() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL_WITHOUT + "}")
	if level.error != "":
		return level.error
	if level.reactor != null:
		return "a reactor appeared from nowhere"
	return ""


func test_the_level_reads_its_reactor() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL_WITHOUT + ', "reactor": ' + REACTOR_JSON + "}")
	if level.error != "":
		return level.error
	var reactor: ReactorState = level.reactor
	if reactor == null:
		return "no reactor"
	if reactor.position_mm != Vector3i(0, 0, -30000) or reactor.radius_mm != 2000:
		return "position %s, radius %d mm" % [reactor.position_mm, reactor.radius_mm]
	if reactor.hull != 40.0 or reactor.meltdown_ticks() != 120 or reactor.destroyed:
		return "hull %s, %d ticks" % [reactor.hull, reactor.meltdown_ticks()]
	return ""


func test_bad_reactors_are_rejected_with_the_problem_named() -> String:
	var cases: Dictionary = {
		'{"position": [0, 0, -99], "radius": 2, "hull": 40, "meltdown_seconds": 2}':
			"reactor: position is not inside the level with its radius to spare",
		'{"position": [0, 0, -30], "radius": 0, "hull": 40, "meltdown_seconds": 2}':
			"reactor: radius must be a number above zero",
		'{"position": [0, 0, -30], "radius": 2, "hull": 40}':
			"reactor: missing key \"meltdown_seconds\"",
		'{"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 2, "x": 1}':
			"reactor: unknown key \"x\"",
		'{"position": [0, 0], "radius": 2, "hull": 40, "meltdown_seconds": 2}':
			"reactor: position must be a list of three numbers",
	}
	var failures: PackedStringArray = PackedStringArray()
	for reactor_json: String in cases:
		var level: LevelDef = LevelDef.parse_json(LEVEL_WITHOUT + ', "reactor": ' + reactor_json + "}")
		if level.error != cases[reactor_json] or level.reactor != null:
			failures.append("%s: got '%s'" % [reactor_json, level.error])
	return "\n".join(failures)


func test_the_g2_level_has_a_reactor_in_its_furthest_room() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return level.error
	if level.reactor == null:
		return "G2 has no reactor"
	var room: BoxBounds = level.union.boxes[4]
	if not room.holds(level.reactor.position(), level.reactor.radius()):
		return "the reactor is not inside box 4"
	return ""


func test_ship_shots_reduce_the_hull_by_their_damage() -> String:
	var sim: Sim = _sim(true)
	# The first shot leaves on tick 0 and needs 15 ticks at 2 m a tick to reach 28 m.
	for i: int in 20:
		sim.step(_fire())
	if sim.reactor.hull != 32.0:
		return "hull %s after one hit, expected 32" % sim.reactor.hull
	return ""


func test_robot_shots_pass_through_without_damage() -> String:
	var sim: Sim = _sim(false)
	sim.projectiles.append(Projectile.new(Vector3(0, 0, -20), Vector3(0, 0, -120),
		Projectile.robot_owner(0), 60, 30.0))
	var crossed: bool = false
	for i: int in 30:
		sim.step(_idle())
		if not sim.projectiles.is_empty() and sim.projectiles[0].position.z < -33.0:
			crossed = true
	if sim.reactor.hull != 40.0:
		return "a robot shot took the hull to %s" % sim.reactor.hull
	if not crossed:
		return "the robot shot stopped at the reactor"
	return ""


func test_destruction_is_reported_once_and_counts_down_from_the_next_tick() -> String:
	var sim: Sim = _sim(true)
	var events: Array[SimEvent] = _fire_until_destroyed(sim, 200)
	if not sim.reactor.destroyed or sim.reactor.hull != 0.0:
		return "not destroyed: hull %s" % sim.reactor.hull
	if events.size() != 1 or events[0].ship != 0 or events[0].vector != Vector3(0, 0, -30):
		return "events %s" % str(events)
	if sim.reactor.meltdown_ticks_left != 120:
		return "%d ticks left on the tick it died, expected 120" % sim.reactor.meltdown_ticks_left
	sim.step(_fire())
	if sim.reactor.meltdown_ticks_left != 119:
		return "%d ticks left a tick later, expected 119" % sim.reactor.meltdown_ticks_left
	for i: int in 200:
		sim.step(_fire())
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.REACTOR_DESTROYED:
				return "destroyed reported again on a later tick"
	if sim.reactor.meltdown_ticks_left != 0:
		return "the countdown stopped at %d" % sim.reactor.meltdown_ticks_left
	return ""


func test_the_countdown_reaches_zero_after_exactly_meltdown_seconds() -> String:
	var sim: Sim = _sim(true)
	_fire_until_destroyed(sim, 200)
	for i: int in 119:
		sim.step(_idle())
	if sim.reactor.meltdown_ticks_left != 1:
		return "%d ticks left after 119 ticks" % sim.reactor.meltdown_ticks_left
	sim.step(_idle())
	if sim.reactor.meltdown_ticks_left != 0:
		return "%d ticks left after 120 ticks" % sim.reactor.meltdown_ticks_left
	return ""


func test_a_destroyed_reactor_stops_no_more_shots() -> String:
	var sim: Sim = _sim(false)
	sim.reactor.apply_damage(40.0)
	sim.projectiles.append(Projectile.new(Vector3(0, 0, -20), Vector3(0, 0, -120), 0, 60, 8.0))
	for i: int in 10:
		sim.step(_idle())
	if sim.projectiles.is_empty():
		return "a shot stopped at a destroyed reactor"
	return ""


func test_the_reactor_joins_the_hash_only_when_there_is_one() -> String:
	var without: Sim = Sim.new(310, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	var with: Sim = _sim(false)
	var plain: Sim = Sim.new(310, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	if without.state_hash() != plain.state_hash():
		return "two sims without a reactor differ"
	if with.state_hash() == without.state_hash():
		return "the reactor is not in the hash"
	var before: int = with.state_hash()
	with.reactor.apply_damage(1.0)
	if with.state_hash() == before:
		return "the reactor's hull is not in the hash"
	return ""


func test_the_reactor_is_set_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(310, 1)
	sim.step(_idle())
	if sim.set_reactor(_reactor()) or sim.reactor != null:
		return "a reactor was added mid-run"
	return ""


func test_the_same_replay_twice_gives_the_same_hash() -> String:
	var replay: Replay = _replay(40.0)
	var first: Sim = replay.run()
	var second: Sim = replay.run()
	if first == null or second == null:
		return replay.run_error
	if not first.reactor.destroyed:
		return "the replay never destroyed its reactor"
	if first.state_hash() != second.state_hash():
		return "two runs of one replay differ"
	var read: Replay = Replay.from_text(replay.to_text())
	if read.error != "":
		return read.error
	var third: Sim = read.run()
	if third == null or third.state_hash() != first.state_hash():
		return "the replay read back from text ends elsewhere"
	return ""


func test_changing_the_reactor_hull_in_the_replay_changes_the_hash() -> String:
	var weak: Sim = _replay(40.0).run()
	var strong: Sim = _replay(48.0).run()
	if weak.state_hash() == strong.state_hash():
		return "hull 40 and 48 end on the same hash"
	return ""


func test_the_reactor_line_follows_the_box_lines_and_reads_back() -> String:
	var replay: Replay = _replay(40.0)
	var lines: PackedStringArray = replay.to_text().split("\n")
	if lines[0] != "meltdown-replay 13" or not lines[3].begins_with("box ") \
			or not lines[4].begins_with("reactor {"):
		return "header %s" % str(lines.slice(0, 5))
	var read: ReactorState = Replay.from_text(replay.to_text()).reactor
	if read == null or read.position_mm != Vector3i(0, 0, -30000) or read.radius_mm != 2000 \
			or read.max_hull != 40.0 or read.meltdown_seconds != 2.0:
		return "read back as %s" % ("null" if read == null else read.to_json())
	return ""


func test_a_reactor_line_in_an_older_format_names_the_line() -> String:
	var text: String = "meltdown-replay 12\nseed 1\nships 1\nbox 0 0 0 1 1 1\nreactor " \
		+ REACTOR_JSON + "\ninputs\n"
	var replay: Replay = Replay.from_text(text)
	if replay.error != "line 5: a reactor line needs format version 13 or later":
		return "got '%s'" % replay.error
	var twice: Replay = Replay.from_text(text.replace("replay 12", "replay 13")
		.replace("inputs", "reactor " + REACTOR_JSON + "\ninputs"))
	if twice.error != "line 6: 'reactor' appears twice":
		return "got '%s'" % twice.error
	return ""


func test_an_older_replay_still_reads_without_a_reactor() -> String:
	var replay: Replay = Replay.from_text(
		"meltdown-replay 12\nseed 1\nships 1\nbox -5000 -5000 -5000 5000 5000 5000\ninputs\n"
		+ "0 0 -1000 0 0 0 0 0 0 0\n")
	if replay.error != "":
		return replay.error
	var sim: Sim = replay.run()
	if sim == null or sim.reactor != null:
		return "an old replay ran with a reactor"
	return ""
