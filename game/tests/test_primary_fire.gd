extends RefCounted

## Firing a primary weapon and the projectiles it leaves in the simulation
## (CMB-1, ARC-1, ARC-2, #94).

const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const SCRATCH_PATH: String = "user://test_primary_fire.replay"


static func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


static func _fire() -> ShipInput:
	return ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, true)


## One ship carrying the pulse cannon, with energy recharge off so the pool
## shows only what the shots spent.
static func _armed_sim(p_bounds: BoxBounds = null) -> Sim:
	var sim: Sim = Sim.new(7, 1, p_bounds)
	sim.ships[0].primary_slots[0] = _cannon()
	sim.ships[0].energy_recharge = 0.0
	return sim


static func _step(sim: Sim, input: ShipInput, ticks: int) -> void:
	for i: int in ticks:
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)


func test_slots_start_empty() -> String:
	var ship: ShipState = ShipState.new()
	if ship.primary_slots.size() != 2 or ship.secondary_slots.size() != 2:
		return "expected two primary and two secondary slots"
	for slot: WeaponDef in ship.primary_slots + ship.secondary_slots:
		if slot != null:
			return "a slot is filled on a new ship"
	return ""


func test_holding_fire_for_one_second() -> String:
	var weapon: WeaponDef = _cannon()
	var sim: Sim = _armed_sim()
	var shots: int = 0
	for i: int in ShipState.TICK_RATE:
		var before: int = sim.projectiles.size()
		_step(sim, _fire(), 1)
		if sim.projectiles.size() > before:
			shots += 1
	var expected: int = ceili(float(ShipState.TICK_RATE) / weapon.fire_interval_ticks)
	if shots != expected:
		return "%d shots in one second, expected %d" % [shots, expected]
	var used: float = sim.ships[0].max_energy - sim.ships[0].energy
	if not is_equal_approx(used, expected * weapon.energy_cost):
		return "used %f energy, expected %f" % [used, expected * weapon.energy_cost]
	return ""


func test_no_fire_without_trigger_weapon_or_energy() -> String:
	var idle: Sim = _armed_sim()
	_step(idle, ShipInput.new(), 30)
	if not idle.projectiles.is_empty():
		return "fired without the trigger held"
	var unarmed: Sim = Sim.new(7, 1)
	_step(unarmed, _fire(), 30)
	if not unarmed.projectiles.is_empty():
		return "fired with an empty slot"
	var drained: Sim = _armed_sim()
	drained.ships[0].energy = _cannon().energy_cost * 0.5
	_step(drained, _fire(), 30)
	if not drained.projectiles.is_empty():
		return "fired without enough energy"
	return ""


func test_projectile_travels_speed_times_time_then_expires() -> String:
	var weapon: WeaponDef = _cannon()
	var sim: Sim = _armed_sim()
	_step(sim, _fire(), 1)
	_step(sim, ShipInput.new(), 30)
	if sim.projectiles.size() != 1:
		return "%d projectiles, expected 1" % sim.projectiles.size()
	var shot: Projectile = sim.projectiles[0]
	var expected: Vector3 = Vector3(0.0, 0.0, -weapon.projectile_speed * 0.5)
	if not shot.position.is_equal_approx(expected):
		return "after 0.5 s at %f m/s the shot is at %s, expected %s" % [
			weapon.projectile_speed, shot.position, expected]
	if shot.owner_index != 0 or shot.damage != weapon.damage:
		return "owner %d, damage %f" % [shot.owner_index, shot.damage]
	_step(sim, ShipInput.new(), weapon.lifetime_ticks() - 31)
	if sim.projectiles.size() != 1:
		return "expired one tick early"
	_step(sim, ShipInput.new(), 1)
	if not sim.projectiles.is_empty():
		return "still alive after its lifetime"
	return ""


func test_projectile_leaving_the_box_is_removed() -> String:
	var weapon: WeaponDef = _cannon()
	# 9 m ahead of the ship is the far wall: at 2 m per tick the shot leaves
	# on its fifth tick, long before its lifetime ends. An odd distance keeps
	# the shot off the wall itself, where rounding would decide.
	var box: BoxBounds = BoxBounds.new(Vector3(-5.0, -5.0, -9.0), Vector3(5.0, 5.0, 5.0))
	var sim: Sim = _armed_sim(box)
	_step(sim, _fire(), 1)
	var step_m: float = weapon.projectile_speed * ShipState.TICK_DT
	var inside_ticks: int = floori(9.0 / step_m)
	_step(sim, ShipInput.new(), inside_ticks)
	if sim.projectiles.size() != 1:
		return "removed while still inside the box"
	_step(sim, ShipInput.new(), 1)
	if not sim.projectiles.is_empty():
		return "still alive outside the box at %s" % sim.projectiles[0].position
	return ""


func test_projectiles_change_the_hash() -> String:
	var fired: Sim = _armed_sim()
	var idle: Sim = _armed_sim()
	_step(fired, _fire(), 1)
	_step(idle, ShipInput.new(), 1)
	idle.ships[0].energy = fired.ships[0].energy
	idle.ships[0].fire_cooldowns = fired.ships[0].fire_cooldowns.duplicate()
	if fired.state_hash() == idle.state_hash():
		return "a live projectile does not change the hash"
	return ""


func test_unarmed_ship_hash_is_unchanged_by_weapons() -> String:
	var ship: ShipState = ShipState.new()
	var old_way: int = hash([ship.position, ship.velocity, ship.orientation, ship.energy,
		ship.afterburner_locked])
	if ship.state_hash() != old_way:
		return "an unarmed ship hashes differently than before weapons"
	var armed: ShipState = ShipState.new()
	armed.primary_slots[1] = _cannon()
	if armed.state_hash() == ship.state_hash():
		return "carrying a weapon does not change the hash"
	return ""


## Fire is held in bursts while the ship turns, so shots leave in different
## directions and some expire during the run.
static func _scripted(tick: int) -> ShipInput:
	var fire: bool = (tick / 40) % 2 == 0
	return ShipInput.new(Vector3i(0, 0, -600), Vector3i(0, 400, 150), false, false, fire)


func _record() -> Replay:
	var replay: Replay = Replay.new(99, 1)
	var sim: Sim = _armed_sim()
	for tick: int in 240:
		var inputs: Array[ShipInput] = [_scripted(tick)]
		replay.add_tick(inputs)
		sim.step(inputs)
	replay.expected_hash = sim.state_hash()
	return replay


func test_replay_round_trip_keeps_fire() -> String:
	var recorded: Replay = _record()
	if recorded.save(SCRATCH_PATH) != OK:
		return "could not save the replay"
	var loaded: Replay = Replay.load_file(SCRATCH_PATH)
	DirAccess.remove_absolute(SCRATCH_PATH)
	if loaded.error != "":
		return "reload failed: %s" % loaded.error
	if loaded.to_text() != recorded.to_text():
		return "text changed on a round trip"
	for tick: int in loaded.frames.size():
		if (loaded.frames[tick][0] as ShipInput).fire_primary != _scripted(tick).fire_primary:
			return "fire_primary lost at tick %d" % tick
	return ""


func test_two_runs_with_the_same_inputs_hash_the_same() -> String:
	var first: Replay = _record()
	var second: Replay = _record()
	if first.expected_hash != second.expected_hash:
		return "two recordings of the same inputs differ"
	# The replay carries no weapon, so arm the ship the same way before each run.
	var hashes: Array[int] = []
	for i: int in 2:
		var sim: Sim = _armed_sim()
		for frame: Array in first.frames:
			var inputs: Array[ShipInput] = []
			inputs.assign(frame)
			sim.step(inputs)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1] or hashes[0] != first.expected_hash:
		return "hashes %s, recorded %d" % [str(hashes), first.expected_hash]
	return ""


func test_old_replay_text_loads_with_fire_off() -> String:
	var replay: Replay = Replay.from_text("meltdown-replay 5\nseed 1\nships 1\ninputs\n0 0 -1000 0 0 0 1 0\n")
	if replay.error != "":
		return "version 5 text rejected: %s" % replay.error
	if (replay.frames[0][0] as ShipInput).fire_primary:
		return "version 5 text read with fire on"
	var short: Replay = Replay.from_text("meltdown-replay 6\nseed 1\nships 1\ninputs\n0 0 -1000 0 0 0 1 0\n")
	if short.error == "":
		return "version 6 text with eight numbers was accepted"
	var bad: Replay = Replay.from_text("meltdown-replay 6\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 0 2\n")
	if not bad.error.contains("fire"):
		return "fire 2 accepted: \"%s\"" % bad.error
	return ""


## The input source and the comfort filter pass `fire_primary` through. The
## field-by-field tests in `test_ship_input_copies.gd` cover it too; this one
## names it, so dropping it fails with a clear message.
func test_fire_survives_input_source_and_filter() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(_fire())
	if not source.next_input(0).fire_primary or not source.latest_input().fire_primary:
		return "LatestInputSource dropped fire_primary"
	for preset_name: String in ["anchored", "guided", "pilot", "unrestricted"]:
		var preset: ComfortPreset = ResourceLoader.load(
			"res://xr/presets/comfort_%s.tres" % preset_name, "",
			ResourceLoader.CACHE_MODE_IGNORE) as ComfortPreset
		if not ComfortInputFilter.new(preset).filter(_fire()).fire_primary:
			return "comfort preset %s dropped fire_primary" % preset_name
	return ""
