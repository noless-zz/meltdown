extends RefCounted

## Snap yaw and pitch and roll-off for comfort preset 1 (CMF-3, CMF-8), the
## untouched input of preset 4 (CMF-2), and thrust passing through for every
## preset (CMF-6, ARC-3).

const PRESET_DIR: String = "res://xr/presets"
const FULL_YAW_Q: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
const FULL_PITCH_Q: int = roundi(ThumbstickMapping.MAX_PITCH_RATE * ShipInput.SCALE)


static func _load(preset_name: String) -> ComfortPreset:
	return ResourceLoader.load("%s/comfort_%s.tres" % [PRESET_DIR, preset_name], "",
		ResourceLoader.CACHE_MODE_IGNORE) as ComfortPreset


static func _turn(pitch_q: int, yaw_q: int, roll_q: int = 0) -> ShipInput:
	return ShipInput.new(Vector3i(100, -200, -900), Vector3i(pitch_q, yaw_q, roll_q), true)


## Checks that pitch and yaw are only zero or one snap and roll is zero.
static func _only_snaps(filter: ComfortInputFilter, input: ShipInput, label: String) -> String:
	var out: ShipInput = filter.filter(input)
	var snap: int = filter.snap_rate_q()
	for value: int in [out.turn_q.x, out.turn_q.y]:
		if value != 0 and absi(value) != snap:
			return "%s: turn %s is not 0 or one snap (%d)" % [label, out.turn_q, snap]
	if out.turn_q.z != 0:
		return "%s: roll %d is not zero" % [label, out.turn_q.z]
	if out.thrust_q != input.thrust_q or out.afterburner != input.afterburner:
		return "%s: thrust or afterburner changed" % label
	return ""


func test_preset_one_snaps_through_a_stick_sweep() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var steps: int = 240
	for i: int in steps * 2 + 1:
		# Right stick sweeps -1..1 and back on both axes, out of phase; grips roll.
		var t: float = float(i) / steps
		var x: float = -1.0 + 2.0 * pingpong(t, 1.0)
		var y: float = sin(t * TAU)
		var input: ShipInput = mapping.map_controls(
			Vector2.ZERO, Vector2(x, y), 0.0, 0.0, absf(y), absf(x))
		var message: String = _only_snaps(filter, input, "sweep tick %d" % i)
		if message != "":
			return message
	return ""


func test_preset_one_snaps_for_random_inputs() -> String:
	for seed_value: int in [1, 7, 42, 1234]:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
		for i: int in 600:
			var input: ShipInput = _turn(
				rng.randi_range(-FULL_PITCH_Q, FULL_PITCH_Q),
				rng.randi_range(-FULL_YAW_Q, FULL_YAW_Q),
				rng.randi_range(-3000, 3000))
			var message: String = _only_snaps(filter, input, "seed %d tick %d" % [seed_value, i])
			if message != "":
				return message
	return ""


func test_holding_the_stick_gives_exactly_one_snap() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	var yaw_snaps: int = 0
	var pitch_snaps: int = 0
	for i: int in 300:
		var out: ShipInput = filter.filter(_turn(-FULL_PITCH_Q, FULL_YAW_Q))
		if out.turn_q.y != 0:
			yaw_snaps += 1
			if out.turn_q.y != filter.snap_rate_q():
				return "yaw snap has the wrong size or sign: %d" % out.turn_q.y
		if out.turn_q.x != 0:
			pitch_snaps += 1
			if out.turn_q.x != -filter.snap_rate_q():
				return "pitch snap has the wrong size or sign: %d" % out.turn_q.x
	if yaw_snaps != 1 or pitch_snaps != 1:
		return "held stick gave %d yaw and %d pitch snaps, want 1 each" % [yaw_snaps, pitch_snaps]
	return ""


func test_release_and_push_again_gives_another_snap() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	var fire: int = FULL_YAW_Q * 6 / 10
	var between: int = FULL_YAW_Q * 35 / 100
	var below: int = FULL_YAW_Q * 2 / 10
	# Dropping only to between the thresholds does not re-arm; dropping below a
	# quarter does, and pushing the other way then snaps the other way.
	var sequence: Array[int] = [fire, fire, between, fire, below, fire, fire, 0, -fire, -fire]
	var want: Array[int] = [1, 0, 0, 0, 0, 1, 0, 0, -1, 0]
	for i: int in sequence.size():
		var out: ShipInput = filter.filter(_turn(0, sequence[i]))
		if out.turn_q.y != want[i] * filter.snap_rate_q():
			return "tick %d: yaw %d, want %d snaps" % [i, out.turn_q.y, want[i]]
	return ""


func test_input_between_thresholds_never_snaps() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	for i: int in 120:
		var out: ShipInput = filter.filter(_turn(FULL_PITCH_Q * 45 / 100, FULL_YAW_Q * 45 / 100))
		if out.turn_q != Vector3i.ZERO:
			return "tick %d: below half rate gave turn %s" % [i, out.turn_q]
	return ""


func test_twelve_snaps_turn_the_ship_once_around() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	if not is_equal_approx(filter.preset.snap_angle_deg, 30.0):
		return "preset 1 snap angle is %f, this test expects 30" % filter.preset.snap_angle_deg
	var sim: Sim = Sim.new()
	var turned: float = 0.0
	var snaps: int = 0
	for i: int in 240:
		# Push for 10 ticks, release for 10: one snap per push.
		var yaw_q: int = FULL_YAW_Q if i % 20 < 10 else 0
		var out: ShipInput = filter.filter(_turn(0, yaw_q))
		if out.turn_q.y != 0:
			snaps += 1
		turned += out.turn().y * ShipState.TICK_DT
		var inputs: Array[ShipInput] = [out]
		sim.step(inputs)
		if snaps == 6 and out.turn_q.y != 0:
			var back: float = sim.ships[0].orientation.z.angle_to(Vector3.BACK)
			if absf(back - PI) > 0.01:
				return "after 6 snaps the nose is %f rad from behind" % absf(back - PI)
	if snaps != 12:
		return "got %d snaps, want 12" % snaps
	if absf(turned - TAU) > 0.01:
		return "summed turn is %f rad, want 2 pi" % turned
	var left: float = Quaternion(sim.ships[0].orientation.orthonormalized()).get_angle()
	if left > 0.01 and absf(left - TAU) > 0.01:
		return "after 12 snaps the ship is %f rad from where it started" % left
	return ""


func test_preset_four_passes_every_input_unchanged() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("unrestricted"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for i: int in 600:
		var input: ShipInput = ShipInput.new(
			Vector3i(rng.randi_range(-1000, 1000), rng.randi_range(-1000, 1000),
				rng.randi_range(-1000, 1000)),
			Vector3i(rng.randi_range(-FULL_PITCH_Q, FULL_PITCH_Q),
				rng.randi_range(-FULL_YAW_Q, FULL_YAW_Q), rng.randi_range(-3000, 3000)),
			rng.randf() < 0.5)
		var out: ShipInput = filter.filter(input)
		if out.thrust_q != input.thrust_q or out.turn_q != input.turn_q \
				or out.afterburner != input.afterburner:
			return "tick %d: preset 4 changed the input" % i
	return ""


func test_smooth_axes_and_manual_roll_pass_through() -> String:
	var preset: ComfortPreset = _load("anchored")
	preset.yaw_mode = ComfortPreset.YawMode.SMOOTH
	for roll_mode: ComfortPreset.RollMode in [
			ComfortPreset.RollMode.MANUAL, ComfortPreset.RollMode.FULLY_MANUAL]:
		preset.roll_mode = roll_mode
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		var out: ShipInput = filter.filter(_turn(FULL_PITCH_Q, 777, -1234))
		if out.turn_q != Vector3i(filter.snap_rate_q(), 777, -1234):
			return "roll mode %d: turn %s, want pitch snap with yaw and roll kept" \
				% [roll_mode, out.turn_q]
	return ""


func test_filter_returns_a_new_input() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	var input: ShipInput = _turn(FULL_PITCH_Q, FULL_YAW_Q, 500)
	var out: ShipInput = filter.filter(input)
	if out == input or input.turn_q != Vector3i(FULL_PITCH_Q, FULL_YAW_Q, 500):
		return "filter changed or returned its argument"
	return ""
