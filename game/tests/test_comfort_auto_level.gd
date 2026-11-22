extends RefCounted

## Auto-level roll for comfort presets 1 to 3 (CMF-1, CMF-3, CMF-5): a banked
## ship with no roll input rolls back to level through its input, smoothly in
## presets 2 and 3 and as one snap tick in preset 1; preset 4 is untouched
## (CMF-2) and thrust never changes (CMF-6, ARC-3).

const PRESET_DIR: String = "res://xr/presets"
const PRESETS: Array[String] = ["anchored", "guided", "pilot", "unrestricted"]
const FULL_YAW_Q: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
const FULL_PITCH_Q: int = roundi(ThumbstickMapping.MAX_PITCH_RATE * ShipInput.SCALE)
## Bank left after levelling: the rate is truncated to whole milliradians per
## second, which leaves well under a hundredth of a degree.
const LEVEL_DEG: float = 0.01


static func _load(preset_name: String) -> ComfortPreset:
	return ResourceLoader.load("%s/comfort_%s.tres" % [PRESET_DIR, preset_name], "",
		ResourceLoader.CACHE_MODE_IGNORE) as ComfortPreset


static func _input(pitch_q: int = 0, yaw_q: int = 0, roll_q: int = 0) -> ShipInput:
	return ShipInput.new(Vector3i(100, -200, -900), Vector3i(pitch_q, yaw_q, roll_q), true)


## A ship with its nose `elevation_deg` above the horizon, banked by
## `bank_deg` about the nose in the direction a positive roll rate turns.
static func _banked(bank_deg: float, elevation_deg: float = 0.0) -> Basis:
	var pitched: Basis = Basis(Vector3.RIGHT, deg_to_rad(elevation_deg))
	return pitched.rotated(pitched.z.normalized(), deg_to_rad(bank_deg)).orthonormalized()


static func _bank_deg(orientation: Basis) -> float:
	return rad_to_deg(ComfortAutoLevel.bank(orientation))


## Flies `ticks` ticks with no stick input through a real `Sim` from
## `orientation`; returns the bank in degrees after each tick.
static func _fly_level(filter: ComfortInputFilter, orientation: Basis, ticks: int) -> Array[float]:
	var sim: Sim = Sim.new()
	sim.ships[0].orientation = orientation
	var banks: Array[float] = []
	for i: int in ticks:
		var inputs: Array[ShipInput] = [filter.filter(_input(), sim.ships[0].orientation)]
		sim.step(inputs)
		banks.append(_bank_deg(sim.ships[0].orientation))
	return banks


func test_bank_is_measured_about_the_nose() -> String:
	for elevation: float in [-60.0, -20.0, 0.0, 30.0, 70.0]:
		for bank: float in [-120.0, -35.0, 0.0, 15.0, 90.0]:
			var got: float = _bank_deg(_banked(bank, elevation))
			if absf(got - bank) > 0.001:
				return "elevation %s bank %s measured as %f" % [elevation, bank, got]
	return ""


func test_preset_two_levels_at_its_rate_without_overshoot() -> String:
	var preset: ComfortPreset = _load("guided")
	for start: float in [40.0, -40.0, 170.0]:
		for elevation: float in [0.0, 35.0, -50.0]:
			var expected_ticks: int = ceili(
				absf(start) / preset.auto_level_rate_deg_per_s * ShipState.TICK_RATE)
			var banks: Array[float] = _fly_level(ComfortInputFilter.new(preset),
				_banked(start, elevation), expected_ticks + 30)
			var previous: float = start
			for i: int in banks.size():
				var step: float = absf(banks[i] - previous)
				if step > preset.auto_level_rate_deg_per_s / ShipState.TICK_RATE + 0.001:
					return "bank %s: tick %d rolled %f deg, over the rate" % [start, i, step]
				if signf(banks[i]) == -signf(start) and absf(banks[i]) > LEVEL_DEG:
					return "bank %s: overshot to %f at tick %d" % [start, banks[i], i]
				previous = banks[i]
			if absf(banks[expected_ticks - 1]) > LEVEL_DEG:
				return "bank %s elevation %s: still %f after %d ticks" \
					% [start, elevation, banks[expected_ticks - 1], expected_ticks]
			if absf(banks[expected_ticks - 3]) < 0.1:
				return "bank %s: level before the rate allows" % start
	return ""


func test_preset_one_levels_in_one_snap_above_the_threshold() -> String:
	var preset: ComfortPreset = _load("anchored")
	for start: float in [25.0, -25.0, preset.auto_level_snap_threshold_deg + 1.0, 150.0]:
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		var banks: Array[float] = _fly_level(filter, _banked(start, 20.0), 30)
		if absf(banks[0]) > LEVEL_DEG:
			return "bank %s: %f after the snap tick" % [start, banks[0]]
		for i: int in banks.size():
			if absf(banks[i]) > LEVEL_DEG:
				return "bank %s: %f at tick %d" % [start, banks[i], i]
	return ""


func test_preset_one_ignores_a_bank_below_the_threshold() -> String:
	var preset: ComfortPreset = _load("anchored")
	for start: float in [preset.auto_level_snap_threshold_deg - 1.0, -4.0, 0.5]:
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		var orientation: Basis = _banked(start, -15.0)
		if filter.filter(_input(), orientation).turn_q.z != 0:
			return "bank %s below the threshold was corrected" % start
		var banks: Array[float] = _fly_level(filter, orientation, 120)
		if absf(banks[-1] - start) > 0.001:
			return "bank %s drifted to %f" % [start, banks[-1]]
	return ""


func test_preset_one_never_rolls_smoothly() -> String:
	# Each tick of preset 1 either leaves roll alone or levels completely.
	var filter: ComfortInputFilter = ComfortInputFilter.new(_load("anchored"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 400:
		var orientation: Basis = _banked(rng.randf_range(-170.0, 170.0),
			rng.randf_range(-75.0, 75.0))
		var out: ShipInput = filter.filter(_input(), orientation)
		if out.turn_q.z == 0:
			continue
		var probe: ShipState = ShipState.new()
		probe.orientation = orientation
		probe.step(Vector3.ZERO, out.turn())
		if absf(_bank_deg(probe.orientation)) > LEVEL_DEG:
			return "tick %d: roll %d left bank %f" % [i, out.turn_q.z, _bank_deg(probe.orientation)]
	return ""


## Preset 3 levels only with the menu's Auto-level option on (#1247).
static func _pilot_levelling() -> ComfortPreset:
	return AutoLevelChoice.applied(_load("pilot"), AutoLevelChoice.ON)


func test_player_roll_in_preset_three_is_not_fought() -> String:
	var filter: ComfortInputFilter = ComfortInputFilter.new(_pilot_levelling())
	var orientation: Basis = _banked(45.0, 10.0)
	for roll: int in [1500, -1500, 1]:
		var out: ShipInput = filter.filter(_input(0, 0, roll), orientation)
		if out.turn_q.z != roll:
			return "player roll %d came out as %d" % [roll, out.turn_q.z]
	if filter.filter(_input(), orientation).turn_q.z >= 0:
		return "preset 3 did not level once the player let go"
	if ComfortInputFilter.new(_load("pilot")).filter(_input(), orientation).turn_q.z != 0:
		return "preset 3 levelled with the option off, its default"
	return ""


func test_preset_four_and_auto_level_off_leave_roll_alone() -> String:
	var off: ComfortPreset = _load("guided")
	off.auto_level = false
	var manual_on: ComfortPreset = _load("unrestricted")
	manual_on.auto_level = true
	var presets: Array[ComfortPreset] = [_load("unrestricted"), off, manual_on]
	for preset: ComfortPreset in presets:
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		for roll: int in [0, 800]:
			var out: ShipInput = filter.filter(_input(0, 0, roll), _banked(60.0, 10.0))
			var want: int = roll if preset.roll_mode != ComfortPreset.RollMode.OFF_AUTO_LEVEL else 0
			if out.turn_q.z != want:
				return "%s auto_level %s: roll %d came out as %d" \
					% [preset.display_name, preset.auto_level, roll, out.turn_q.z]
	return ""


func test_nose_near_vertical_is_skipped() -> String:
	var limit: float = ComfortAutoLevel.MAX_ELEVATION_DEG
	for preset_name: String in ["anchored", "guided", "pilot"]:
		var preset: ComfortPreset = _pilot_levelling() if preset_name == "pilot" else _load(preset_name)
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		for elevation: float in [limit + 1.0, 89.9, 90.0, -90.0, -(limit + 2.0)]:
			for bank: float in [30.0, -90.0, 179.0]:
				var orientation: Basis = _banked(bank, elevation)
				if ComfortAutoLevel.bank_defined(orientation):
					return "bank reported as defined at elevation %s" % elevation
				var out: ShipInput = filter.filter(_input(), orientation)
				if out.turn_q.z != 0:
					return "%s rolled %d at elevation %s" % [preset_name, out.turn_q.z, elevation]
		if filter.filter(_input(), _banked(30.0, limit - 1.0)).turn_q.z == 0:
			return "%s did not level just below the skip elevation" % preset_name
	return ""


func test_thrust_and_afterburner_pass_through_while_levelling() -> String:
	for preset_name: String in PRESETS:
		var filter: ComfortInputFilter = ComfortInputFilter.new(_load(preset_name))
		var input: ShipInput = _input(FULL_PITCH_Q / 3, FULL_YAW_Q / 3)
		var out: ShipInput = filter.filter(input, _banked(50.0, 5.0))
		if out.thrust_q != input.thrust_q or out.afterburner != input.afterburner:
			return "%s changed thrust or afterburner while levelling" % preset_name
	return ""


func test_random_snaps_in_preset_one_keep_the_pitch_limit() -> String:
	var preset: ComfortPreset = _load("anchored")
	var tolerance: float = preset.pitch_limit_deg + preset.snap_angle_deg + 0.01
	for seed_value: int in [3, 11, 2026]:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		var sim: Sim = Sim.new()
		for i: int in 1200:
			# Half the ticks release the stick, so the snaps re-arm often.
			var pitch: int = 0
			var yaw: int = 0
			if rng.randf() < 0.5:
				pitch = [FULL_PITCH_Q, -FULL_PITCH_Q, 0][rng.randi_range(0, 2)]
				yaw = [FULL_YAW_Q, -FULL_YAW_Q, 0][rng.randi_range(0, 2)]
			var inputs: Array[ShipInput] = [
				filter.filter(_input(pitch, yaw), sim.ships[0].orientation)]
			sim.step(inputs)
			var elevation: float = absf(rad_to_deg(
				ComfortInputFilter.nose_elevation(sim.ships[0].orientation)))
			if elevation > tolerance:
				return "seed %d tick %d: nose at %f deg" % [seed_value, i, elevation]
			if ComfortAutoLevel.bank_defined(sim.ships[0].orientation) \
					and absf(_bank_deg(sim.ships[0].orientation)) \
						> preset.auto_level_snap_threshold_deg + 0.01:
				return "seed %d tick %d: left banked at %f deg" \
					% [seed_value, i, _bank_deg(sim.ships[0].orientation)]
	return ""
