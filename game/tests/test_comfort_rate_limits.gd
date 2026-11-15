extends RefCounted

## Rate caps of preset 2 and the pitch limit of preset 1 (CMF-1, CMF-3),
## applied in `xr/` only and never written back to the ship (CMF-6, ARC-3).

const PRESET_DIR: String = "res://xr/presets"
const FULL_YAW_Q: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
const FULL_PITCH_Q: int = roundi(ThumbstickMapping.MAX_PITCH_RATE * ShipInput.SCALE)
## Ten seconds at the simulation tick rate.
const TEN_SECONDS: int = ShipState.TICK_RATE * 10
## Stated tolerance for the pitch limit: one tick of full-stick pitch.
const ONE_TICK_DEG: float = rad_to_deg(ThumbstickMapping.MAX_PITCH_RATE * ShipState.TICK_DT)


static func _load(preset_name: String) -> ComfortPreset:
	return ResourceLoader.load("%s/comfort_%s.tres" % [PRESET_DIR, preset_name], "",
		ResourceLoader.CACHE_MODE_IGNORE) as ComfortPreset


static func _turn(pitch_q: int, yaw_q: int, roll_q: int = 0) -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -1000), Vector3i(pitch_q, yaw_q, roll_q), false)


## Flies `ticks` ticks through a real `Sim`, asking `pitch_at` for the stick's
## pitch each tick. Returns [largest |nose elevation| in degrees, final sim].
static func _fly(filter: ComfortInputFilter, ticks: int, pitch_at: Callable) -> Array:
	var sim: Sim = Sim.new()
	var worst: float = 0.0
	for i: int in ticks:
		var out: ShipInput = filter.filter(_turn(int(pitch_at.call(i)), 0),
			sim.ships[0].orientation)
		var inputs: Array[ShipInput] = [out]
		sim.step(inputs)
		var elevation: float = absf(rad_to_deg(
			ComfortInputFilter.nose_elevation(sim.ships[0].orientation)))
		worst = maxf(worst, elevation)
	return [worst, sim]


func test_preset_two_never_exceeds_its_caps() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("guided"))
	var yaw_cap: int = ComfortInputFilter.cap_q(filter.preset.yaw_rate_cap_deg_per_s)
	var pitch_cap: int = ComfortInputFilter.cap_q(filter.preset.pitch_rate_cap_deg_per_s)
	if yaw_cap <= 0 or pitch_cap <= 0:
		return "preset 2 has no caps: yaw %d, pitch %d" % [yaw_cap, pitch_cap]
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	for stick: Vector2 in [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1),
			Vector2(1, 0), Vector2(0, 1), Vector2(0.7, -0.7)]:
		var out: ShipInput = filter.filter(
			mapping.map_controls(Vector2.ZERO, stick, 0.0, 0.0, 0.0, 0.0))
		if absi(out.turn_q.y) > yaw_cap or absi(out.turn_q.x) > pitch_cap:
			return "stick %s gave turn %s, caps yaw %d pitch %d" \
				% [stick, out.turn_q, yaw_cap, pitch_cap]
	var full: ShipInput = filter.filter(_turn(-FULL_PITCH_Q, FULL_YAW_Q))
	if full.turn_q.x != -pitch_cap or full.turn_q.y != yaw_cap:
		return "full stick gave %s, want pitch %d and yaw %d" % [full.turn_q, -pitch_cap, yaw_cap]
	var slow: ShipInput = filter.filter(_turn(pitch_cap / 2, -yaw_cap / 2))
	if slow.turn_q.x != pitch_cap / 2 or slow.turn_q.y != -yaw_cap / 2:
		return "input under the caps was changed: %s" % slow.turn_q
	if full.thrust_q != Vector3i(0, 0, -1000):
		return "capping changed thrust"
	return ""


func test_presets_three_and_four_are_not_capped() -> String:
	for preset_name: String in ["pilot", "unrestricted"]:
		var filter: ComfortInputFilter = ComfortInputFilter.new(_load(preset_name))
		for sign_value: int in [1, -1]:
			var input: ShipInput = _turn(FULL_PITCH_Q * sign_value, FULL_YAW_Q * sign_value)
			var out: ShipInput = filter.filter(input, Basis(Vector3.RIGHT, deg_to_rad(80.0)))
			if out.turn_q.x != input.turn_q.x or out.turn_q.y != input.turn_q.y:
				return "%s changed full stick %s to %s" % [preset_name, input.turn_q, out.turn_q]
	return ""


func test_preset_one_snaps_stop_at_the_pitch_limit() -> String:
	var limit: float = _load("anchored").pitch_limit_deg
	for direction: int in [1, -1]:
		# Held full pitch for ten seconds: a single snap.
		var held: Array = _fly(ComfortInputFilter.new(_load("anchored")), TEN_SECONDS,
			func(_i: int) -> int: return FULL_PITCH_Q * direction)
		if float(held[0]) > limit + ONE_TICK_DEG:
			return "held pitch %d reached %f deg" % [direction, held[0]]
		# Pushed and released every 20 ticks for ten seconds: snap after snap.
		var pulsed: Array = _fly(ComfortInputFilter.new(_load("anchored")), TEN_SECONDS,
			func(i: int) -> int: return FULL_PITCH_Q * direction if i % 20 < 10 else 0)
		if float(pulsed[0]) > limit + ONE_TICK_DEG:
			return "pulsed pitch %d reached %f deg, limit %f + %f" \
				% [direction, pulsed[0], limit, ONE_TICK_DEG]
		if float(pulsed[0]) < limit - 1.0:
			return "pulsed pitch %d only reached %f deg: snaps up to the limit were dropped" \
				% [direction, pulsed[0]]
	return ""


func test_smooth_pitch_with_a_limit_stops_at_it() -> String:
	var preset: ComfortPreset = _load("anchored")
	preset.pitch_mode = ComfortPreset.PitchMode.SMOOTH
	for direction: int in [1, -1]:
		var flown: Array = _fly(ComfortInputFilter.new(preset), TEN_SECONDS,
			func(_i: int) -> int: return FULL_PITCH_Q * direction)
		var worst: float = float(flown[0])
		if worst > preset.pitch_limit_deg + ONE_TICK_DEG:
			return "smooth pitch %d reached %f deg" % [direction, worst]
		if worst < preset.pitch_limit_deg - ONE_TICK_DEG:
			return "smooth pitch %d stopped early at %f deg" % [direction, worst]
	return ""


func test_pitch_back_towards_the_horizon_passes() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	var at_limit: Basis = Basis(Vector3.RIGHT, deg_to_rad(60.0))
	var up: ShipInput = filter.filter(_turn(FULL_PITCH_Q, 0), at_limit)
	if up.turn_q.x != 0:
		return "a snap past the limit was emitted: %d" % up.turn_q.x
	filter.filter(_turn(0, 0), at_limit)
	var down: ShipInput = filter.filter(_turn(-FULL_PITCH_Q, 0), at_limit)
	if down.turn_q.x != -filter.snap_rate_q():
		return "a snap back towards the horizon was dropped: %d" % down.turn_q.x
	# Past the limit already: nose-down still passes, nose-up does not.
	var past: Basis = Basis(Vector3.RIGHT, deg_to_rad(75.0))
	filter.filter(_turn(0, 0), past)
	if filter.filter(_turn(FULL_PITCH_Q, 0), past).turn_q.x != 0:
		return "a snap further past the limit was emitted"
	filter.filter(_turn(0, 0), past)
	if filter.filter(_turn(-FULL_PITCH_Q, 0), past).turn_q.x == 0:
		return "a ship past the limit could not pitch back"
	return ""


func test_filter_never_writes_the_ship_it_reads() -> String:
	var preset: ComfortPreset = _load("anchored")
	for pitch_mode: ComfortPreset.PitchMode in [
			ComfortPreset.PitchMode.SNAP, ComfortPreset.PitchMode.SMOOTH]:
		preset.pitch_mode = pitch_mode
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		var sim: Sim = Sim.new()
		var ship: ShipState = sim.ships[0]
		ship.orientation = Basis(Vector3.RIGHT, deg_to_rad(59.0))
		ship.velocity = Vector3(1, 2, 3)
		var before_hash: int = sim.state_hash()
		var before_orientation: Basis = ship.orientation
		for i: int in 120:
			var stick: int = FULL_PITCH_Q if i % 2 == 0 else -FULL_PITCH_Q
			filter.filter(_turn(stick, FULL_YAW_Q), ship.orientation)
		if sim.state_hash() != before_hash or ship.orientation != before_orientation:
			return "pitch mode %d: filtering changed the ship" % pitch_mode
	return ""
