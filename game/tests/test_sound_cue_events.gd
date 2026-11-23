extends RefCounted

## Which cues the simulation's output makes, and where (#1290, AUD-1): a new
## bolt is a shot of the weapon in the slot that fired it, a bolt ending with
## range left places a robot or ship hit or else knocks on a wall, and each
## event sounds at the place it happened. Following the simulation for sound
## leaves its hash as it was (ARC-1).

const SHORT_REPLAY: String = "res://acceptance/replays/both_primaries_fire.replay"


static func _ship(at: Vector3 = Vector3.ZERO) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.position = at
	ship.primary_ids = ["pulse_cannon", "needle_gun"]
	return ship


static func _bolt(owner: int, at: Vector3, velocity: Vector3, ticks_left: int, slot: int = 0) -> Projectile:
	var bolt: Projectile = Projectile.new(at, velocity, owner, ticks_left, 1.0)
	bolt.slot = slot
	return bolt


static func _cues(hits: Array[SoundCueHit]) -> Array[String]:
	var listed: Array[String] = []
	for hit: SoundCueHit in hits:
		listed.append(hit.cue)
	return listed


func test_new_bolts_are_shots_of_their_slots_weapon() -> String:
	var cues: SoundCueEvents = SoundCueEvents.new()
	var ships: Array[ShipState] = [_ship()]
	var right: Projectile = _bolt(0, Vector3.ZERO, Vector3.FORWARD * 60.0, 30, 0)
	var left: Projectile = _bolt(0, Vector3.ZERO, Vector3.FORWARD * 60.0, 30, 1)
	var robot: Projectile = _bolt(-1, Vector3(0, 0, -20), Vector3.BACK * 30.0, 30)
	var first: Array[String] = _cues(cues.feed([], [right, left, robot], ships))
	if first != ["SHOT_FIRED:pulse_cannon", "SHOT_FIRED:needle_gun", "SHOT_FIRED:robot"]:
		return "first feed gave %s" % [first]
	var again: Array[String] = _cues(cues.feed([], [right, left, robot], ships))
	return "" if again.is_empty() else "bolts still flying sounded again: %s" % [again]


func test_bolt_from_unknown_ship_plays_plain_shot() -> String:
	var hits: Array[SoundCueHit] = SoundCueEvents.new().feed([], [_bolt(3, Vector3.ZERO, Vector3.UP, 5)],
		[_ship()] as Array[ShipState])
	return "" if _cues(hits) == ["SHOT_FIRED"] else "gave %s" % [_cues(hits)]


func test_bolt_ending_with_range_left_knocks_where_it_ended() -> String:
	var cues: SoundCueEvents = SoundCueEvents.new()
	var ships: Array[ShipState] = [_ship()]
	var bolt: Projectile = _bolt(0, Vector3(0, 0, -10), Vector3(0, 0, -60), 20)
	cues.feed([], [bolt], ships)
	var hits: Array[SoundCueHit] = cues.feed([], [], ships)
	if _cues(hits) != ["BOLT_IMPACT"]:
		return "gave %s" % [_cues(hits)]
	var expected: Vector3 = Vector3(0, 0, -10) + Vector3(0, 0, -60) * ShipState.TICK_DT * 0.5
	return "" if hits[0].position.is_equal_approx(expected) else "at %s, expected %s" % [hits[0].position, expected]


func test_bolt_running_out_of_range_is_silent() -> String:
	var cues: SoundCueEvents = SoundCueEvents.new()
	var ships: Array[ShipState] = [_ship()]
	cues.feed([], [_bolt(0, Vector3.ZERO, Vector3.FORWARD, 1)], ships)
	var hits: Array[SoundCueHit] = cues.feed([], [], ships)
	return "" if hits.is_empty() else "gave %s" % [_cues(hits)]


func test_robot_hit_sounds_where_the_bolt_ended() -> String:
	var cues: SoundCueEvents = SoundCueEvents.new()
	var ships: Array[ShipState] = [_ship()]
	var velocity: Vector3 = Vector3(0, 0, -60)
	cues.feed([], [_bolt(0, Vector3(0, 0, -30), velocity, 20)], ships)
	var hit: SimEvent = SimEvent.new(SimEvent.Kind.ROBOT_HIT, 0, 10.0, velocity.normalized())
	var killed: SimEvent = SimEvent.new(SimEvent.Kind.ROBOT_DESTROYED, 0, 0.0, Vector3.ZERO)
	var hits: Array[SoundCueHit] = cues.feed([hit, killed], [], ships)
	if _cues(hits) != ["ROBOT_HIT", "ROBOT_DESTROYED"]:
		return "gave %s; the bolt that hit must not also knock on a wall" % [_cues(hits)]
	var expected: Vector3 = Vector3(0, 0, -30) + velocity * ShipState.TICK_DT * 0.5
	if not hits[0].position.is_equal_approx(expected) or not hits[1].position.is_equal_approx(expected):
		return "hit at %s and kill at %s, expected both at %s" % [hits[0].position, hits[1].position, expected]
	return ""


func test_robot_hit_without_a_bolt_sounds_ahead_of_the_ship() -> String:
	var hit: SimEvent = SimEvent.new(SimEvent.Kind.ROBOT_HIT, 0, 10.0, Vector3.FORWARD)
	var hits: Array[SoundCueHit] = SoundCueEvents.new().feed([hit], [], [_ship(Vector3(1, 2, 3))] as Array[ShipState])
	var expected: Vector3 = Vector3(1, 2, 3) + Vector3.FORWARD * SoundCueEvents.ROBOT_FALLBACK_M
	return "" if hits[0].position.is_equal_approx(expected) else "at %s" % hits[0].position


func test_ship_hit_sounds_from_where_the_shot_came() -> String:
	var cues: SoundCueEvents = SoundCueEvents.new()
	var ships: Array[ShipState] = [_ship(Vector3(5, 0, 0))]
	cues.feed([], [_bolt(-1, Vector3(5, 0, -1), Vector3(0, 0, 30), 20)], ships)
	var hit: SimEvent = SimEvent.new(SimEvent.Kind.SHIP_HIT, 0, 5.0, Vector3.BACK)
	var hits: Array[SoundCueHit] = cues.feed([hit], [], ships)
	if _cues(hits) != ["SHIP_HIT"]:
		return "gave %s; the robot bolt that hit must not also knock" % [_cues(hits)]
	var expected: Vector3 = Vector3(5, 0, 0) - Vector3.BACK * SoundCueEvents.SHOT_FROM_M
	return "" if hits[0].position.is_equal_approx(expected) else "at %s, expected %s" % [hits[0].position, expected]


func test_wall_impact_sounds_in_the_wall() -> String:
	var knock: SimEvent = SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 4.0, Vector3.UP)
	var hits: Array[SoundCueHit] = SoundCueEvents.new().feed([knock], [], [_ship(Vector3(0, 3, 0))] as Array[ShipState])
	if not hits[0].position.is_equal_approx(Vector3(0, 3 - SoundCueEvents.WALL_OFFSET_M, 0)):
		return "at %s" % hits[0].position
	return "" if is_equal_approx(hits[0].magnitude, 4.0) else "magnitude %f" % hits[0].magnitude


func test_placed_events_sound_where_they_happened() -> String:
	var ships: Array[ShipState] = [_ship()]
	for kind: SimEvent.Kind in [SimEvent.Kind.REACTOR_DESTROYED, SimEvent.Kind.SHIP_ESCAPED,
			SimEvent.Kind.SALVAGE_COLLECTED, SimEvent.Kind.SHIP_DESTROYED]:
		var at: Vector3 = Vector3(7, -2, 11)
		var hits: Array[SoundCueHit] = SoundCueEvents.new().feed([SimEvent.new(kind, 0, 0.0, at)], [], ships)
		if hits.size() != 1 or hits[0].cue != SimEvent.Kind.keys()[kind] or hits[0].position != at:
			return "%s gave %s" % [SimEvent.Kind.keys()[kind], hits]
	return ""


func test_reset_forgets_bolts_in_flight() -> String:
	var cues: SoundCueEvents = SoundCueEvents.new()
	var ships: Array[ShipState] = [_ship()]
	cues.feed([], [_bolt(0, Vector3.ZERO, Vector3.FORWARD, 20)], ships)
	cues.reset()
	var hits: Array[SoundCueHit] = cues.feed([], [], ships)
	return "" if hits.is_empty() else "an old level's bolt sounded: %s" % [_cues(hits)]


func test_feeding_does_not_change_the_bolts() -> String:
	var bolt: Projectile = _bolt(0, Vector3(1, 2, 3), Vector3(4, 5, 6), 9)
	var before: int = bolt.state_hash()
	SoundCueEvents.new().feed([], [bolt], [_ship()] as Array[ShipState])
	return "" if bolt.state_hash() == before else "the bolt changed"


func test_simulation_hash_same_with_sound_followed() -> String:
	var plain: Replay = Replay.load_file(SHORT_REPLAY)
	var sim: Sim = plain.run()
	if sim == null:
		return "the replay did not run: %s" % plain.run_error
	var flown: Array = preload("res://acceptance/checks/sound_cues_check.gd").fly(
		Replay.load_file(SHORT_REPLAY), SoundCueTable.load_file())
	if flown.is_empty():
		return "the followed flight did not start"
	if int(flown[1]) != sim.state_hash():
		return "hash %d with sound followed, %d without" % [flown[1], sim.state_hash()]
	return "" if not (flown[0] as Array).is_empty() else "no cue played over a fight"
