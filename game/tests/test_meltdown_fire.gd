extends RefCounted

## Fire among the meltdown entries (#480, RUN-4, CMB-2, ARC-1, ARC-2, ARC-4): read
## with `"kind": "fire"` and `damage_per_second`, never solid, burning every ship
## whose centre is inside it from its fall tick, and carried by replays without
## moving any earlier hash. Routes and the guard: `test_meltdown_fire_route.gd`.

const FAR_REACTOR_JSON: String = '{"position": [15, 15, 15], "radius": 2, "hull": 40, "meltdown_seconds": 60}'
const REACTOR_JSON: String = '{"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 60}'
const PULSE: String = "res://data/weapons/pulse_cannon.json"
const LEVEL: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []'
const CENTRE: Vector3 = Vector3(0, 0, -10)
## 30 points a second: half a point a tick.
const FIRE_SPHERE: String = '[{"position": [0, 0, -10], "radius": 3, "after_seconds": 0.02,' \
	+ ' "kind": "fire", "damage_per_second": 30}]'
const FIRE_BOX: String = '[{"position": [0, 0, -10], "size": [4, 4, 4], "after_seconds": 0.02,' \
	+ ' "kind": "fire", "damage_per_second": 30}]'


## One tick in, as in `test_box_debris.gd`: one ship at the origin inside
## `min_corner`..(20, 20, 20), its start far off, the far reactor intact and the
## debris. The shield does not recharge, so the damage can be counted exactly.
func _sim(debris_text: String) -> Sim:
	var sim: Sim = Sim.new(480, 1, BoxBounds.new(Vector3(-20, -20, -40), Vector3(20, 20, 20)))
	sim.set_reactor(ReactorState.parse_json(FAR_REACTOR_JSON))
	sim.set_debris(MeltdownDebris.parse_json(debris_text))
	sim.ships[0].position = Vector3(-15, -15, 15)
	sim.step(_idle())
	sim.ships[0].position = Vector3.ZERO
	sim.ships[0].shield_recharge = 0.0
	return sim


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


func _steps(sim: Sim, ticks: int) -> void:
	for i: int in ticks:
		sim.step(_idle())


func test_fire_entries_are_read_and_solid_is_the_default() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": [{"position": [0, 0, -30],'
		+ ' "radius": 2, "after_seconds": 1, "kind": "fire", "damage_per_second": 12.5},'
		+ ' {"position": [0, 0, -50], "size": [6, 6, 1], "after_seconds": 2, "kind": "fire",'
		+ ' "damage_per_second": 4}, {"position": [0, 0, -60], "radius": 1, "after_seconds": 3,'
		+ ' "kind": "solid"}, {"position": [0, 0, -70], "radius": 1, "after_seconds": 3}]}')
	if level.error != "":
		return level.error
	var debris: MeltdownDebris = level.debris
	var expected: Array[int] = [12500, 4000, 0, 0]
	if debris.fire_milli_dps != expected:
		return "read %s" % [debris.fire_milli_dps]
	if not debris.is_fire(0) or not debris.is_fire(1) or debris.is_fire(2) or debris.is_fire(3):
		return "kinds read wrong: %s" % debris.to_json()
	if not debris.is_box(1) or debris.is_box(0):
		return "a fire lost its shape"
	return ""


func test_bad_kinds_and_damage_are_rejected_naming_the_index() -> String:
	var good: String = '{"position": [0, 0, -30], "radius": 1, "after_seconds": 1}'
	var fire: String = '{"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "kind": "fire"'
	var cases: Dictionary = {
		'[{"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "kind": "lava"}]':
			'debris 0: kind must be "solid" or "fire"',
		'[%s, {"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "kind": 1}]' % good:
			'debris 1: kind must be "solid" or "fire"',
		'[%s, %s, %s}]' % [good, good, fire]:
			'debris 2: missing key "damage_per_second"',
		'[%s, "damage_per_second": 0}]' % fire:
			"debris 0: damage_per_second must be a number above zero and at most 100000",
		'[%s, "damage_per_second": -3}]' % fire:
			"debris 0: damage_per_second must be a number above zero and at most 100000",
		'[%s, "damage_per_second": "hot"}]' % fire:
			"debris 0: damage_per_second must be a number above zero and at most 100000",
		'[%s, "damage_per_second": 100001}]' % fire:
			"debris 0: damage_per_second must be a number above zero and at most 100000",
		'[%s, "damage_per_second": 0.0004}]' % fire:
			"debris 0: damage_per_second must be at least 0.001",
		'[%s, {"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "damage_per_second": 5}]' % good:
			"debris 1: damage_per_second is only for fire",
		'[{"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "kind": "solid",'
			+ ' "damage_per_second": 5}]':
			"debris 0: damage_per_second is only for fire",
	}
	var failures: Array[String] = []
	for text: String in cases:
		var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": ' + text + "}")
		if level.error != cases[text]:
			failures.append("%s: got '%s'" % [text, level.error])
	return "\n".join(failures)


func test_only_fire_writes_its_keys_and_fire_round_trips() -> String:
	var solid: MeltdownDebris = MeltdownDebris.parse_json(
		'[{"position": [0, 0, -12], "radius": 2, "after_seconds": 1, "kind": "solid"}]')
	if solid.to_json() != '[{"position":[0.0,0.0,-12.0],"radius":2.0,"after_seconds":1.0}]':
		return "a solid entry writes %s" % solid.to_json()
	var mixed: MeltdownDebris = MeltdownDebris.parse_json(
		'[{"position": [1, 2, -12], "size": [3.5, 0.25, 7], "after_seconds": 1, "kind": "fire",'
		+ ' "damage_per_second": 7.125}, {"position": [0, 0, -20], "radius": 1, "after_seconds": 2}]')
	var expected: String = '[{"position":[1.0,2.0,-12.0],"size":[3.5,0.25,7.0],"after_seconds":1.0,' \
		+ '"kind":"fire","damage_per_second":7.125},{"position":[0.0,0.0,-20.0],"radius":1.0,' \
		+ '"after_seconds":2.0}]'
	if mixed.to_json() != expected:
		return "fire writes %s" % mixed.to_json()
	var again: MeltdownDebris = MeltdownDebris.parse_json(mixed.to_json())
	if again.error != "" or again.fire_milli_dps != mixed.fire_milli_dps \
			or again.to_json() != mixed.to_json():
		return "read back as %s (%s)" % [again.to_json(), again.error]
	if mixed.fresh_copy().fire_milli_dps != mixed.fire_milli_dps:
		return "a fresh copy lost the fire"
	return ""


## Parked in a fire sphere and in a fire box: 0.5 a tick comes off the shield
## first, then the hull, and the ship is not moved.
func test_a_parked_ship_burns_shield_then_hull() -> String:
	var failures: Array[String] = []
	for text: String in [FIRE_SPHERE, FIRE_BOX]:
		var sim: Sim = _sim(text)
		var ship: ShipState = sim.ships[0]
		ship.position = CENTRE + Vector3(0.5, -1.0, 1.5)
		sim.reactor.apply_damage(40.0)
		_steps(sim, 60)
		if not sim.debris.is_burning(0) or sim.debris.is_solid(0):
			failures.append("%s: burning %s, solid %s" % [text, sim.debris.is_burning(0),
				sim.debris.is_solid(0)])
		if not is_equal_approx(ship.shield, 20.0) or ship.hull != ship.max_hull:
			failures.append("%s: after 60 ticks shield %s hull %s" % [text, ship.shield, ship.hull])
		_steps(sim, 60)
		if not is_equal_approx(ship.hull, 90.0) or ship.shield != 0.0:
			failures.append("%s: after 120 ticks shield %s hull %s" % [text, ship.shield, ship.hull])
		if ship.position != CENTRE + Vector3(0.5, -1.0, 1.5):
			failures.append("%s: the fire moved the ship to %s" % [text, ship.position])
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.WALL_IMPACT:
				failures.append("%s: the fire reported a wall hit" % text)
	return "\n".join(failures)


## A ship outside the fire, even touching it with its hull, is not burnt: only
## its centre counts.
func test_only_a_ship_whose_centre_is_inside_burns() -> String:
	for text: String in [FIRE_SPHERE, FIRE_BOX]:
		var sim: Sim = _sim(text)
		sim.ships[0].position = CENTRE + Vector3(3.5, 0, 0)
		sim.reactor.apply_damage(40.0)
		_steps(sim, 30)
		if sim.ships[0].shield != sim.ships[0].max_shield:
			return "%s: a ship beside the fire took damage" % text
	return ""


func test_no_burn_before_the_fall_tick() -> String:
	var sim: Sim = _sim(FIRE_BOX.replace('"after_seconds": 0.02', '"after_seconds": 0.5'))
	var ship: ShipState = sim.ships[0]
	ship.position = CENTRE
	_steps(sim, 60)
	if ship.shield != ship.max_shield or sim.debris.is_burning(0):
		return "a fire burnt with the reactor intact: shield %s" % ship.shield
	sim.reactor.apply_damage(40.0)
	_steps(sim, 29)
	if ship.shield != ship.max_shield:
		return "the fire burnt before its tick: shield %s" % ship.shield
	_steps(sim, 1)
	if not is_equal_approx(ship.shield, 49.5):
		return "on its fall tick the shield is %s, expected 49.5" % ship.shield
	return ""


## Two ships in one fire (#518): the one with a point of hull dies, then lies in it untouched
## (a shield set on the wreck shows no `apply_damage` call) while the other burns on.
func test_a_destroyed_ship_takes_no_more_fire() -> String:
	var sim: Sim = Sim.new(480, 2, BoxBounds.new(Vector3(-20, -20, -40), Vector3(20, 20, 20)))
	sim.set_reactor(ReactorState.parse_json(FAR_REACTOR_JSON))
	sim.set_debris(MeltdownDebris.parse_json(FIRE_SPHERE))
	var idle: Array[ShipInput] = [ShipInput.new(), ShipInput.new()]
	sim.step(idle)
	var wreck: ShipState = sim.ships[0]
	var live: ShipState = sim.ships[1]
	wreck.position = CENTRE + Vector3(-1, 0, 0)
	live.position = CENTRE + Vector3(1, 0, 0)
	wreck.shield_recharge = 0.0
	live.shield_recharge = 0.0
	wreck.shield = 0.0
	wreck.hull = 1.0
	sim.reactor.apply_damage(40.0)
	for i: int in 2:
		sim.step(idle)
	if wreck.hull != 0.0:
		return "the fire left the wreck with hull %s" % wreck.hull
	wreck.shield = 5.0
	var shield_before: float = live.shield
	for i: int in 60:
		sim.step(idle)
	if wreck.hull != 0.0 or wreck.shield != 5.0:
		return "the wreck burnt on: shield %s hull %s" % [wreck.shield, wreck.hull]
	if not is_equal_approx(live.shield, shield_before - 30.0):
		return "the live ship's shield went %s -> %s, expected 30 less" % [shield_before, live.shield]
	return ""


## Through a burning box at 30 m/s: no bounce, no wall hit, out the far side,
## a little burnt.
func test_a_ship_flies_through_fire_without_bouncing() -> String:
	var sim: Sim = _sim(FIRE_BOX)
	sim.reactor.apply_damage(40.0)
	sim.step(_idle())
	var ship: ShipState = sim.ships[0]
	ship.position = Vector3(0, 0, -6)
	ship.velocity = Vector3(0, 0, -30)
	for i: int in 60:
		sim.step(_idle())
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.WALL_IMPACT:
				return "a wall hit on tick %d at %s" % [i, ship.position]
		if ship.velocity.z >= 0.0:
			return "the ship was turned back on tick %d" % i
	if ship.position.z > -14.0:
		return "the ship did not get through: %s" % ship.position
	if ship.shield >= ship.max_shield or ship.hull != ship.max_hull:
		return "shield %s hull %s after flying through" % [ship.shield, ship.hull]
	return ""


func test_shots_pass_through_fire() -> String:
	var sim: Sim = _sim(FIRE_BOX)
	sim.reactor.apply_damage(40.0)
	sim.step(_idle())
	sim.ships[0].position = Vector3(0, 0, 15)
	sim.projectiles.append(Projectile.new(Vector3(0, 1, -3), Vector3(0, 0, -120), 0, 60, 8.0))
	var passed: bool = false
	for i: int in 20:
		sim.step(_idle())
		for projectile: Projectile in sim.projectiles:
			passed = passed or projectile.position.z < -13.0
	if not passed:
		return "a fire stopped a shot"
	if sim.debris.segment_entry(Vector3(0, 0, -3), Vector3(0, 0, -17)) != -1.0:
		return "a shot enters burning fire"
	return ""


## Flies towards the reactor shooting it, then turns back for the exit at the
## start through the fire that fell behind it.
func _replay() -> Replay:
	var replay: Replay = Replay.new(480, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON)
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	replay.debris = MeltdownDebris.parse_json('[{"position": [0, 0, -8], "size": [8, 8, 2],'
		+ ' "after_seconds": 0.1, "kind": "fire", "damage_per_second": 40}]')
	var attack: ShipInput = ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO)
	attack.fire_primary = true
	for i: int in 90:
		replay.add_tick([attack])
	for i: int in 180:
		replay.add_tick([ShipInput.from_floats(Vector3(0, 0, 1), Vector3.ZERO)])
	return replay


func test_a_replay_with_fire_gives_the_same_hash_twice_and_from_text() -> String:
	var replay: Replay = _replay()
	var first: Sim = replay.run()
	if first == null or not first.reactor.destroyed:
		return "the run did not destroy the reactor: %s" % replay.run_error
	var ship: ShipState = first.ships[0]
	if not first.debris.is_burning(0) or not ship.escaped:
		return "the ship did not get home through the fire: %s, escaped %s" % [ship.position,
			ship.escaped]
	if ship.shield >= ship.max_shield or ship.hull != ship.max_hull:
		return "flying through the fire left shield %s hull %s" % [ship.shield, ship.hull]
	var unlit: Replay = _replay()
	unlit.debris = null
	var cold: Sim = unlit.run()
	if cold == null or cold.ships[0].shield != cold.ships[0].max_shield:
		return "the flight hurts the ship without fire, the test proves nothing"
	var second: Sim = _replay().run()
	if second.state_hash() != first.state_hash():
		return "the same level and inputs gave two hashes"
	replay.expected_hash = first.state_hash()
	var text: String = replay.to_text()
	if not text.contains('"kind":"fire","damage_per_second":40.0'):
		return "the debris line lost the fire:\n%s" % text
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	var again: Sim = read.run()
	if again == null or again.state_hash() != read.expected_hash:
		return "the replay read back from text ends elsewhere"
	if read.to_text() != text:
		return "the debris line does not read back to itself"
	return ""
