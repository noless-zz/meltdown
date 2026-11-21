extends RefCounted

## The meltdown countdown scales with the longest escape path on the tick the
## reactor dies (#337, RUN-5, RUN-2, ARC-1, ARC-2, ARC-4).

const G2_LEVEL: String = "res://data/levels/g2_level.json"
const PULSE: String = "res://data/weapons/pulse_cannon.json"
## Eight hull (one pulse shot), 30 m ahead. 10 s plus 1 s a metre, 12 s to 40 s.
const SCALED: String = '{"position": [0, 0, -30], "radius": 2, "hull": 8, "meltdown_seconds": 5,' \
	+ ' "meltdown_base_seconds": 10, "meltdown_seconds_per_metre": 1,' \
	+ ' "meltdown_min_seconds": 12, "meltdown_max_seconds": 40}'
const PLAIN: String = '{"position": [0, 0, -30], "radius": 2, "hull": 8, "meltdown_seconds": 5}'
## The hash `_replay(PLAIN)` ended on at main d7c06a3, before the scaling keys
## existed (Godot 4.7.2). It must not move for the scaling keys; #603 moved it
## once by retuning the pulse cannon, which the replay fires, and #750 once more:
## the ship escapes on the tick the reactor dies and the countdown now holds.
const PLAIN_PINNED_HASH: int = 594744929


## One ship in one box, moved `metres` along -z from its start after the first
## tick, then firing until the reactor dies. Returns the sim on that tick.
func _killed_from(reactor_json: String, metres: float) -> Sim:
	var sim: Sim = Sim.new(337, 1, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	sim.set_reactor(ReactorState.parse_json(reactor_json))
	sim.equip(_loadout())
	sim.step([ShipInput.new()])
	sim.ships[0].position = Vector3(0, 0, -metres)
	sim.ships[0].velocity = Vector3.ZERO
	var fire: ShipInput = ShipInput.new()
	fire.fire_primary = true
	for i: int in 200:
		sim.step([fire])
		if sim.reactor.destroyed:
			break
	return sim


func _loadout() -> ShipLoadout:
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	return loadout


func _replay(reactor_json: String) -> Replay:
	var replay: Replay = Replay.new(337, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(reactor_json)
	replay.loadout = _loadout()
	var forward: ShipInput = ShipInput.new()
	forward.fire_primary = true
	forward.thrust_q = Vector3i(0, 0, -400)
	for i: int in 90:
		replay.add_tick([forward])
	for i: int in 60:
		replay.add_tick([ShipInput.new()])
	return replay


func test_a_ship_further_from_the_exit_gets_a_longer_timer() -> String:
	var near: Sim = _killed_from(SCALED, 15.0)
	var far: Sim = _killed_from(SCALED, 25.0)
	if not near.reactor.destroyed or not far.reactor.destroyed:
		return "the reactor was not destroyed"
	# 10 s + 15 m and 10 s + 25 m, at 60 ticks a second.
	var near_path: int = EscapePath.longest_for_ships(near)
	var far_path: int = EscapePath.longest_for_ships(far)
	if near.reactor.meltdown_ticks_left != near.reactor.meltdown_ticks_for_path(near_path) \
			or far.reactor.meltdown_ticks_left != far.reactor.meltdown_ticks_for_path(far_path):
		return "%d and %d ticks, not from the paths %d and %d mm" % [
			near.reactor.meltdown_ticks_left, far.reactor.meltdown_ticks_left, near_path, far_path]
	if absi(near.reactor.meltdown_ticks_left - 1500) > 6 or absi(far.reactor.meltdown_ticks_left - 2100) > 6:
		return "%d and %d ticks, expected about 1500 and 2100" % [
			near.reactor.meltdown_ticks_left, far.reactor.meltdown_ticks_left]
	return ""


func test_the_timer_is_clamped_at_min_and_max() -> String:
	var reactor: ReactorState = ReactorState.parse_json(SCALED)
	if reactor.error != "" or not reactor.scales_with_path:
		return "did not read the scaling keys: " + reactor.error
	var cases: Dictionary[int, int] = {0: 720, 1000: 720, 2000: 720, 15000: 1500,
		30000: 2400, 500000: 2400}
	for path_mm: int in cases:
		if reactor.meltdown_ticks_for_path(path_mm) != cases[path_mm]:
			return "%d mm gave %d ticks, expected %d" % [path_mm,
				reactor.meltdown_ticks_for_path(path_mm), cases[path_mm]]
	var killed: Sim = _killed_from(SCALED, 0.5)
	if killed.reactor.meltdown_ticks_left != 720:
		return "killed from 0.5 m out: %d ticks, expected the 12 s minimum" % killed.reactor.meltdown_ticks_left
	return ""


func test_without_the_keys_meltdown_seconds_is_used_as_before() -> String:
	var reactor: ReactorState = ReactorState.parse_json(PLAIN)
	if reactor.scales_with_path or reactor.meltdown_ticks_for_path(90000) != 300:
		return "a plain reactor scaled its timer"
	var killed: Sim = _killed_from(PLAIN, 25.0)
	if killed.reactor.meltdown_ticks_left != 300:
		return "%d ticks, expected 300" % killed.reactor.meltdown_ticks_left
	return ""


func test_partial_or_bad_scaling_keys_are_rejected_with_the_problem_named() -> String:
	var cases: Dictionary[String, String] = {
		PLAIN.replace("}", ', "meltdown_base_seconds": 10}'):
			"must be given together",
		SCALED.replace('"meltdown_seconds_per_metre": 1', '"meltdown_seconds_per_metre": -1'):
			"meltdown_seconds_per_metre must be a number of at least zero",
		SCALED.replace('"meltdown_min_seconds": 12', '"meltdown_min_seconds": 0'):
			"meltdown_min_seconds must be at least one tick",
		SCALED.replace('"meltdown_max_seconds": 40', '"meltdown_max_seconds": 11'):
			"meltdown_max_seconds must be at least meltdown_min_seconds",
	}
	for text: String in cases:
		var reactor: ReactorState = ReactorState.parse_json(text)
		if not reactor.error.begins_with("reactor: ") or not reactor.error.contains(cases[text]):
			return "'%s' for %s" % [reactor.error, text]
	return ""


func test_a_replay_with_the_keys_reproduces_its_hash() -> String:
	var replay: Replay = _replay(SCALED)
	var first: Sim = replay.run()
	if first == null:
		return replay.run_error
	if not first.reactor.destroyed:
		return "the replay never destroyed its reactor"
	var text: String = replay.to_text()
	if not text.contains("\"meltdown_seconds_per_metre\":1"):
		return "the reactor line lost the scaling keys"
	var read: Replay = Replay.from_text(text)
	if read.error != "" or not read.reactor.scales_with_path:
		return "read back: " + read.error
	var again: Sim = read.run()
	if again == null or again.state_hash() != first.state_hash():
		return "the replay read back from text ends elsewhere"
	if _replay(PLAIN).run().state_hash() == first.state_hash():
		return "scaling the timer did not change the hash"
	return ""


func test_a_level_with_only_meltdown_seconds_keeps_its_pinned_hash() -> String:
	var replay: Replay = _replay(PLAIN)
	if replay.to_text().contains("meltdown_base_seconds"):
		return "a plain reactor line grew scaling keys"
	var sim: Sim = replay.run()
	if sim == null or not sim.reactor.destroyed:
		return "the plain replay never destroyed its reactor"
	if sim.state_hash() != PLAIN_PINNED_HASH:
		return "ends on %d, pinned %d" % [sim.state_hash(), PLAIN_PINNED_HASH]
	return ""


func test_the_g2_reactor_scales_its_timer() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return level.error
	var reactor: ReactorState = level.reactor
	if reactor == null or not reactor.scales_with_path:
		return "G2's reactor has no scaling keys"
	var from_reactor: int = EscapePath.length_mm(level.union,
		reactor.position() + Vector3(0, 0, 6), Vector3.ZERO)
	var ticks: int = reactor.meltdown_ticks_for_path(from_reactor)
	if from_reactor <= 0 or ticks <= reactor.meltdown_ticks_for_path(0):
		return "a %d mm escape from the reactor gives %d ticks" % [from_reactor, ticks]
	return ""
