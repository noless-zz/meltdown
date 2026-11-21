extends RefCounted

## Look-aim in the simulation (CMB-6, decision record 0010, #922): the guns
## turn towards the aim at the gimbal rate, inside the cone, shots leave along
## them, and a run stays deterministic (ARC-2).

const SHIPPED: String = "res://data/aim/look_aim.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## Two seconds: at 180 degrees a second any aim inside the cone is reached.
const SETTLE_TICKS: int = 120


static func _right(degrees: float) -> Vector3:
	return LookAim.NOSE.rotated(Vector3.UP, -deg_to_rad(degrees))


static func _aiming(degrees: float, fire: bool = false) -> ShipInput:
	var input: ShipInput = ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, fire)
	input.aim_q = ShipInput.aim_q_from(_right(degrees))
	return input


static func _armed_sim() -> Sim:
	var sim: Sim = Sim.new(7, 1)
	sim.ships[0].primary_slots[0] = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	return sim


static func _step(sim: Sim, input: ShipInput, ticks: int) -> void:
	for i: int in ticks:
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)


## Degrees to the right of the nose of a ship-space direction, signed.
static func _yaw_right(direction: Vector3) -> float:
	return rad_to_deg(atan2(direction.x, -direction.z))


func test_shipped_file_parses_to_the_defaults() -> String:
	var aim: LookAim = LookAim.parse_json(FileAccess.get_file_as_string(SHIPPED))
	if aim.error != "":
		return aim.error
	if aim.cone_degrees != 35.0 or aim.gimbal_degrees_per_second != 180.0:
		return "shipped %s, the issue ships 35 and 180" % aim.to_json()
	# A Sim given no values flies the file's, so the two must not drift apart.
	if aim.values_hash() != LookAim.new().values_hash():
		return "LookAim.new() %s differs from the shipped file %s" % [LookAim.new().to_json(),
			aim.to_json()]
	return ""


func test_bad_files_are_rejected_naming_the_key() -> String:
	var cases: Dictionary = {
		"[]": "top level must be a JSON object",
		"{": "invalid JSON",
		"{\"cone_degrees\": 35}": "missing key \"gimbal_degrees_per_second\"",
		"{\"cone_degrees\": 35, \"gimbal_degrees_per_second\": 180, \"cone\": 1}":
			"unknown key \"cone\"",
		"{\"cone_degrees\": true, \"gimbal_degrees_per_second\": 180}":
			"key \"cone_degrees\" must be a number",
		"{\"cone_degrees\": 200, \"gimbal_degrees_per_second\": 180}": "key \"cone_degrees\" is 200",
		"{\"cone_degrees\": 35, \"gimbal_degrees_per_second\": 0}":
			"key \"gimbal_degrees_per_second\" is 0",
	}
	for text: String in cases:
		var aim: LookAim = LookAim.parse_json(text)
		if not aim.error.contains(cases[text]):
			return "%s gave error '%s', expected '%s'" % [text, aim.error, cases[text]]
	return ""


func test_an_aim_ten_degrees_right_settles_and_a_bolt_leaves_along_it() -> String:
	var sim: Sim = _armed_sim()
	_step(sim, _aiming(10.0), SETTLE_TICKS)
	var gun: float = _yaw_right(sim.ships[0].gun_direction)
	if absf(gun - 10.0) > 0.1:
		return "the guns settled %.3f degrees right, expected 10" % gun
	_step(sim, _aiming(10.0, true), 1)
	if sim.projectiles.size() != 1:
		return "%d projectiles after one shot" % sim.projectiles.size()
	var bolt: float = _yaw_right(sim.projectiles[0].velocity.normalized())
	if absf(bolt - 10.0) > 0.1:
		return "the bolt left %.3f degrees right, expected 10" % bolt
	return ""


func test_an_aim_sixty_degrees_right_stops_at_the_cone_edge() -> String:
	var sim: Sim = _armed_sim()
	_step(sim, _aiming(60.0), SETTLE_TICKS)
	var edge: float = LookAim.new().cone_degrees * 0.5
	var gun: float = _yaw_right(sim.ships[0].gun_direction)
	if absf(gun - edge) > 0.01:
		return "the guns stopped %.3f degrees right, the cone's edge is %.1f" % [gun, edge]
	return ""


func test_the_guns_turn_at_most_the_gimbal_rate_per_tick() -> String:
	var sim: Sim = _armed_sim()
	var limit: float = LookAim.new().gimbal_degrees_per_second / ShipState.TICK_RATE
	var before: Vector3 = sim.ships[0].gun_direction
	for tick: int in 30:
		_step(sim, _aiming(-15.0), 1)
		var turned: float = rad_to_deg(before.angle_to(sim.ships[0].gun_direction))
		if turned > limit + 1.0e-3:
			return "tick %d turned %.4f degrees, the limit is %.4f" % [tick, turned, limit]
		before = sim.ships[0].gun_direction
	if absf(_yaw_right(before) + 15.0) > 0.1:
		return "the guns ended %.3f degrees right, expected -15" % _yaw_right(before)
	return ""


func test_back_on_the_nose_the_hash_is_as_if_never_aimed() -> String:
	var aimed: Sim = _armed_sim()
	_step(aimed, _aiming(10.0), 5)
	_step(aimed, ShipInput.new(), SETTLE_TICKS)
	if aimed.ships[0].gun_direction != LookAim.NOSE:
		return "the guns rest at %s, not exactly on the nose" % aimed.ships[0].gun_direction
	var never: Sim = _armed_sim()
	_step(never, ShipInput.new(), 5 + SETTLE_TICKS)
	if aimed.state_hash() != never.state_hash():
		return "a ship back on the nose hashes %d, one that never aimed %d" % [aimed.state_hash(),
			never.state_hash()]
	return ""


func test_same_seed_and_inputs_give_the_same_hash_twice() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = _armed_sim()
		for tick: int in 90:
			_step(sim, _aiming(float(tick % 50) - 25.0, tick % 3 == 0), 1)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "two identical runs hashed %d and %d" % hashes
	var nose: Sim = _armed_sim()
	_step(nose, ShipInput.new(), 90)
	if nose.state_hash() == hashes[0]:
		return "an aimed run hashes like one that never aimed"
	return ""


func test_look_aim_is_set_before_the_first_tick_only() -> String:
	var sim: Sim = Sim.new(1, 1)
	var wide: LookAim = LookAim.parse_json("{\"cone_degrees\": 90, \"gimbal_degrees_per_second\": 360}")
	if sim.set_look_aim(wide) != "" or sim.look_aim != wide:
		return "a valid look-aim was refused before the first tick"
	if sim.set_look_aim(LookAim.parse_json("[]")) == "":
		return "a rejected look-aim was taken"
	_step(sim, ShipInput.new(), 1)
	if sim.set_look_aim(LookAim.new()) == "" or sim.look_aim != wide:
		return "look-aim changed after the first tick"
	return ""


func test_a_destroyed_ship_keeps_its_guns_where_they_were() -> String:
	var sim: Sim = _armed_sim()
	sim.ships[0].hull = 0.0
	_step(sim, _aiming(10.0), 10)
	if sim.ships[0].gun_direction != LookAim.NOSE:
		return "a wreck turned its guns to %s" % sim.ships[0].gun_direction
	return ""


func test_aim_helpers() -> String:
	if ShipInput.new().aims_off_nose() or ShipInput.new().aim() != LookAim.NOSE:
		return "a new input does not aim along the nose"
	if ShipInput.aim_q_from(Vector3.ZERO) != ShipInput.NOSE_AIM_Q:
		return "a zero direction is not the nose"
	if ShipInput.aim_q_valid(Vector3i.ZERO) or ShipInput.aim_q_valid(Vector3i(0, 0, -1001)):
		return "a zero or oversized aim passed as valid"
	if LookAim.new().clamp_to_cone(Vector3.BACK) != LookAim.NOSE:
		return "an aim straight behind did not fall back to the nose"
	return ""
