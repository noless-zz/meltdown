extends RefCounted

## Afterburner and energy pool (FLT-2) in `ShipState`, `Sim` and `Replay`.

const ShipStateScript: GDScript = preload("res://core/ship_state.gd")

const FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)
const SCRATCH_PATH: String = "user://test_afterburner.replay"


func _new_ship() -> ShipState:
	return ShipStateScript.new() as ShipState


## Steps until the pool is dry with the afterburner held, at most `limit` ticks.
func _drain(ship: ShipState, limit: int = 1200) -> int:
	for i: int in limit:
		ship.step(FORWARD, Vector3.ZERO, true)
		if ship.energy <= 0.0:
			return i + 1
	return -1


func test_input_defaults_to_afterburner_off() -> String:
	if ShipInput.new().afterburner:
		return "ShipInput.new() has the afterburner on"
	if ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO).afterburner:
		return "two-argument constructor has the afterburner on"
	if ShipInput.from_floats(FORWARD, Vector3.ZERO).afterburner:
		return "from_floats without a flag has the afterburner on"
	if not ShipInput.from_floats(FORWARD, Vector3.ZERO, true).afterburner:
		return "from_floats dropped the afterburner flag"
	return ""


func test_boosted_speed_exceeds_normal_cap_and_stays_under_boosted_cap() -> String:
	var ship: ShipState = _new_ship()
	var top: float = 0.0
	for i: int in 240:
		ship.step(FORWARD, Vector3.ZERO, true)
		top = maxf(top, ship.velocity.length())
		if ship.velocity.length() > ship.afterburner_max_speed + 0.001:
			return "speed %f exceeded the boosted cap at tick %d" % [ship.velocity.length(), i]
	if top <= ship.max_speed + 0.5:
		return "boosted top speed %f did not exceed the normal cap %f" % [top, ship.max_speed]
	return ""


func test_speed_falls_back_gradually_after_boost() -> String:
	var ship: ShipState = _new_ship()
	for i: int in 120:
		ship.step(FORWARD, Vector3.ZERO, true)
	var previous: float = ship.velocity.length()
	ship.step(FORWARD, Vector3.ZERO, false)
	var after_one: float = ship.velocity.length()
	if after_one > previous + 0.001:
		return "speed rose from %f to %f when the boost ended" % [previous, after_one]
	if after_one < previous - 2.0:
		return "speed dropped from %f to %f in one tick" % [previous, after_one]
	for i: int in 300:
		ship.step(FORWARD, Vector3.ZERO, false)
	if ship.velocity.length() > ship.max_speed + 0.001:
		return "speed %f still above the normal cap after 5 s" % ship.velocity.length()
	return ""


func test_energy_drains_while_boosting_and_recharges_after() -> String:
	var ship: ShipState = _new_ship()
	for i: int in 60:
		ship.step(FORWARD, Vector3.ZERO, true)
	var drained: float = ship.energy
	if drained >= ship.max_energy - 0.001:
		return "energy did not drain while boosting"
	if absf(drained - (ship.max_energy - ship.afterburner_drain)) > 0.01:
		return "one second of boost left %f energy" % drained
	for i: int in 60:
		ship.step(FORWARD, Vector3.ZERO, false)
	if ship.energy <= drained:
		return "energy did not recharge after boosting"
	for i: int in 1200:
		ship.step(Vector3.ZERO, Vector3.ZERO, false)
	if ship.energy != ship.max_energy:
		return "energy recharged to %f, not max %f" % [ship.energy, ship.max_energy]
	return ""


func test_zero_energy_blocks_the_boost() -> String:
	var ship: ShipState = _new_ship()
	if _drain(ship) < 0:
		return "energy never reached zero"
	var boosted: ShipState = _new_ship()
	var plain: ShipState = _new_ship()
	for s: ShipState in [boosted, plain]:
		s.position = ship.position
		s.velocity = ship.velocity
		s.energy = ship.energy
		s.afterburner_locked = ship.afterburner_locked
	for i: int in 30:
		boosted.step(FORWARD, Vector3.ZERO, true)
		plain.step(FORWARD, Vector3.ZERO, false)
	if boosted.state_hash() != plain.state_hash():
		return "with an empty pool, holding the afterburner still changed the flight"
	return ""


func test_restart_threshold_prevents_flicker() -> String:
	var ship: ShipState = _new_ship()
	if _drain(ship) < 0:
		return "energy never reached zero"
	var switches: int = 0
	var was_draining: bool = false
	var first_restart_energy: float = -1.0
	for i: int in 600:
		var before: float = ship.energy
		ship.step(FORWARD, Vector3.ZERO, true)
		var draining: bool = ship.energy < before
		if draining and not was_draining:
			switches += 1
			if first_restart_energy < 0.0:
				first_restart_energy = before
		was_draining = draining
	if first_restart_energy < ship.afterburner_restart_energy:
		return "boost restarted at %f energy, below the threshold %f" % [
			first_restart_energy, ship.afterburner_restart_energy]
	# 10 s held: about 2 s locked, 1 s boost, then repeating. Flicker would be
	# hundreds of switches.
	if switches > 5:
		return "boost switched on %d times in 10 s while held" % switches
	return ""


func test_energy_is_in_the_hash() -> String:
	var a: ShipState = _new_ship()
	var b: ShipState = _new_ship()
	b.energy = a.energy - 1.0
	if a.state_hash() == b.state_hash():
		return "two ships differing only in energy have the same hash"
	return ""


func test_same_inputs_give_same_hash_with_afterburner() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = Sim.new(7, 2)
		for tick: int in 900:
			var inputs: Array[ShipInput] = [
				ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 300, 0), tick % 90 < 60),
				ShipInput.new(Vector3i(200, 0, -1000), Vector3i.ZERO, tick > 100),
			]
			sim.step(inputs)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "identical afterburner inputs produced different hashes"
	return ""


func test_replay_with_afterburner_saves_loads_and_reproduces_hash() -> String:
	var recorded: Replay = Replay.new(11, 2)
	var sim: Sim = Sim.new(11, 2)
	for tick: int in 600:
		var inputs: Array[ShipInput] = [
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO, tick % 200 < 150),
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 0, 400), false),
		]
		recorded.add_tick(inputs)
		sim.step(inputs)
	recorded.expected_hash = sim.state_hash()
	if recorded.save(SCRATCH_PATH) != OK:
		return "could not save replay"
	var loaded: Replay = Replay.load_file(SCRATCH_PATH)
	DirAccess.remove_absolute(SCRATCH_PATH)
	if loaded.error != "":
		return "reload failed: %s" % loaded.error
	var first: ShipInput = loaded.frames[0][0]
	if not first.afterburner:
		return "afterburner flag lost in save and load"
	var replayed: Sim = loaded.run()
	if replayed == null or replayed.state_hash() != recorded.expected_hash:
		return "replay with afterburner ticks did not reproduce its hash"
	return ""


func test_version_1_text_loads_with_afterburner_off() -> String:
	var replay: Replay = Replay.from_text(
		"meltdown-replay 1\nseed 3\nships 2\ninputs\n0 0 -1000 0 0 0 | 0 0 -1000 0 0 0\n")
	if replay.error != "":
		return replay.error
	for input: ShipInput in replay.frames[0]:
		if input.afterburner:
			return "a version-1 tick was read with the afterburner on"
	if replay.run() == null:
		return "a version-1 replay did not run: %s" % replay.run_error
	return ""
