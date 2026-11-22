extends RefCounted

## Gate G1's comfort limit tests (#92): every preset file is flown through the
## real `ComfortInputFilter` and the real `Sim` with seeded random stick input,
## and each comfort-table row the filter is responsible for is checked on
## every tick (CMF-1, CMF-2, CMF-3, CMF-6, ARC-2, ARC-3).
##
## One test per preset and table row, named `test_preset_<n>_<row>_<setting>`,
## so the gate issue can quote them. Vignette and cockpit rows are view code
## and are checked in their own tests.
##
## The random numbers live in this test only: the filter and the simulation
## stay deterministic, and a failure is reproduced by its seed and tick.

const PRESET_DIR: String = "res://xr/presets"
## Preset files in table order: index 0 is preset 1.
const PRESETS: Array[String] = ["anchored", "guided", "pilot", "unrestricted"]
const SEQUENCES: int = 20
const TICKS: int = 600
const FULL_PITCH_Q: int = roundi(ThumbstickMapping.MAX_PITCH_RATE * ShipInput.SCALE)
const FULL_YAW_Q: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
const FULL_ROLL_Q: int = roundi(ThumbstickMapping.MAX_ROLL_RATE * ShipInput.SCALE)
## Stated tolerance for the pitch limit: one tick of full-stick pitch, as in
## `test_comfort_rate_limits.gd`.
const PITCH_TOLERANCE_DEG: float = rad_to_deg(ThumbstickMapping.MAX_PITCH_RATE * ShipState.TICK_DT)
## Bank left after a preset 1 roll snap. The snap rate is truncated to whole
## milliradians per second, which leaves well under a thousandth of a degree.
const LEVEL_TOLERANCE_RAD: float = 0.001
## Longest a random stick value is held, in ticks.
const MAX_HOLD: int = 90

## Preset index to {row name: first failure, or "" when the row held}.
var _results: Dictionary = {}


static func _load(index: int) -> ComfortPreset:
	return ResourceLoader.load("%s/comfort_%s.tres" % [PRESET_DIR, PRESETS[index]], "",
		ResourceLoader.CACHE_MODE_IGNORE) as ComfortPreset


## Random input for one sequence. Each axis holds a value for a random number
## of ticks, often zero, so snaps fire, re-arm and auto-level gets its turn.
static func _random_inputs(seed_value: int) -> Array[ShipInput]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var limits: Array[int] = [1000, 1000, 1000, FULL_PITCH_Q, FULL_YAW_Q, FULL_ROLL_Q]
	var values: Array[int] = [0, 0, 0, 0, 0, 0]
	var holds: Array[int] = [0, 0, 0, 0, 0, 0]
	var afterburner: bool = false
	var inputs: Array[ShipInput] = []
	for _tick: int in TICKS:
		for axis: int in limits.size():
			holds[axis] -= 1
			if holds[axis] <= 0:
				holds[axis] = rng.randi_range(1, MAX_HOLD)
				values[axis] = 0 if rng.randf() < 0.3 \
					else rng.randi_range(-limits[axis], limits[axis])
		if rng.randf() < 0.02:
			afterburner = not afterburner
		inputs.append(ShipInput.new(Vector3i(values[0], values[1], values[2]),
			Vector3i(values[3], values[4], values[5]), afterburner))
	return inputs


## Flies every sequence through preset `index` once and records the first
## failure of each row; the row tests only read the result.
func _rows(index: int) -> Dictionary:
	if not _results.has(index):
		_results[index] = _fly_preset(index)
	return _results[index]


func _fly_preset(index: int) -> Dictionary:
	var rows: Dictionary = {"yaw": "", "pitch": "", "roll": "", "all": ""}
	var preset: ComfortPreset = _load(index)
	if preset == null:
		for row: String in rows:
			rows[row] = "preset file %s did not load" % PRESETS[index]
		return rows
	for sequence: int in SEQUENCES:
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		# Fed the same input without its roll: equal output means the
		# player's roll never reached the ship.
		var rollless: ComfortInputFilter = ComfortInputFilter.new(preset)
		var sim: Sim = Sim.new(sequence)
		var tick: int = 0
		for raw: ShipInput in _random_inputs(sequence + 1):
			var orientation: Basis = sim.ships[0].orientation
			var out: ShipInput = filter.filter(raw, orientation)
			var no_roll: ShipInput = ComfortInputFilter.copy_input(raw)
			no_roll.turn_q.z = 0
			var out_no_roll: ShipInput = rollless.filter(no_roll, orientation)
			var inputs: Array[ShipInput] = [out]
			sim.step(inputs)
			var at: String = "sequence %d tick %d: " % [sequence, tick]
			var found: Dictionary = _check(index, preset, filter, raw, out, out_no_roll,
				sim.ships[0].orientation)
			for row: String in found:
				if rows[row] == "" and found[row] != "":
					rows[row] = at + String(found[row])
			tick += 1
	return rows


## Checks one tick. `turned` is the ship's orientation after the tick.
func _check(index: int, preset: ComfortPreset, filter: ComfortInputFilter, raw: ShipInput,
		out: ShipInput, out_no_roll: ShipInput, turned: Basis) -> Dictionary:
	var found: Dictionary = {}
	var t: Vector3i = out.turn_q
	var r: Vector3i = raw.turn_q
	if index == 0:
		var snaps: Array[int] = [0, filter.snap_rate_q(), -filter.snap_rate_q()]
		if not snaps.has(t.y):
			found["yaw"] = "yaw rate %d is neither 0 nor one snap" % t.y
		var elevation: float = absf(rad_to_deg(ComfortInputFilter.nose_elevation(turned)))
		if not snaps.has(t.x):
			found["pitch"] = "pitch rate %d is neither 0 nor one snap" % t.x
		elif elevation > preset.pitch_limit_deg + PITCH_TOLERANCE_DEG:
			found["pitch"] = "nose at %f deg, limit %f + %f" \
				% [elevation, preset.pitch_limit_deg, PITCH_TOLERANCE_DEG]
		if t != out_no_roll.turn_q:
			found["roll"] = "player roll %d changed the turn to %s" % [r.z, t]
		elif t.z != 0 and absf(ComfortAutoLevel.bank(turned)) > LEVEL_TOLERANCE_RAD:
			found["roll"] = "roll %d left a bank of %f rad: a smooth roll" \
				% [t.z, ComfortAutoLevel.bank(turned)]
	elif index == 1:
		var yaw_cap: int = ComfortInputFilter.cap_q(preset.yaw_rate_cap_deg_per_s)
		var pitch_cap: int = ComfortInputFilter.cap_q(preset.pitch_rate_cap_deg_per_s)
		if yaw_cap < 0 or absi(t.y) > yaw_cap:
			found["yaw"] = "yaw rate %d, cap %d" % [t.y, yaw_cap]
		if pitch_cap < 0 or absi(t.x) > pitch_cap:
			found["pitch"] = "pitch rate %d, cap %d" % [t.x, pitch_cap]
		var level_cap: int = ComfortInputFilter.cap_q(preset.auto_level_rate_deg_per_s)
		if t != out_no_roll.turn_q:
			found["roll"] = "player roll %d changed the turn to %s" % [r.z, t]
		elif level_cap >= 0 and absi(t.z) > level_cap:
			found["roll"] = "auto-level roll %d, cap %d" % [t.z, level_cap]
	elif index == 2:
		if t.y != r.y:
			found["yaw"] = "yaw %d became %d" % [r.y, t.y]
		if t.x != r.x:
			found["pitch"] = "pitch %d became %d" % [r.x, t.x]
		var level_cap: int = ComfortInputFilter.cap_q(preset.auto_level_rate_deg_per_s)
		if r.z != 0 and t.z != r.z:
			found["roll"] = "manual roll %d became %d" % [r.z, t.z]
		elif r.z == 0 and not preset.levels_roll() and t.z != 0:
			found["roll"] = "auto-level is off by default (#1247), yet it rolled %d" % t.z
		elif r.z == 0 and level_cap >= 0 and absi(t.z) > level_cap:
			found["roll"] = "auto-level roll %d, cap %d" % [t.z, level_cap]
	else:
		var differs: String = _difference(raw, out)
		if differs != "":
			found["all"] = differs
	if out.thrust_q != raw.thrust_q or out.afterburner != raw.afterburner:
		found["all"] = "thrust or afterburner changed"
	return found


## Names the first script property in which `a` and `b` differ, or "".
static func _difference(a: ShipInput, b: ShipInput) -> String:
	for property: Dictionary in a.get_script().get_script_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name: StringName = StringName(property["name"])
			if a.get(property_name) != b.get(property_name):
				return "%s %s became %s" \
					% [property_name, a.get(property_name), b.get(property_name)]
	return ""


func _row(index: int, row: String) -> String:
	var rows: Dictionary = _rows(index)
	if String(rows[row]) != "":
		return "preset %d %s: %s" % [index + 1, row, rows[row]]
	if String(rows["all"]) != "":
		return "preset %d: %s" % [index + 1, rows["all"]]
	return ""


## Comfort table, Yaw, 1 Anchored: "Snap, 30 or 45 degrees" (CMF-3).
func test_preset_1_yaw_snap_only() -> String:
	return _row(0, "yaw")


## Pitch, 1 Anchored: "Snap or slow, limited to +-60 degrees" (CMF-3).
func test_preset_1_pitch_snap_within_limit() -> String:
	return _row(0, "pitch")


## Roll, 1 Anchored: "Off, auto-level"; any levelling is a snap (CMF-3).
func test_preset_1_roll_off_auto_level() -> String:
	return _row(0, "roll")


## Yaw, 2 Guided: "Smooth, capped".
func test_preset_2_yaw_smooth_capped() -> String:
	return _row(1, "yaw")


## Pitch, 2 Guided: "Smooth, capped".
func test_preset_2_pitch_smooth_capped() -> String:
	return _row(1, "pitch")


## Roll, 2 Guided: "Off, auto-level".
func test_preset_2_roll_off_auto_level() -> String:
	return _row(1, "roll")


## Yaw, 3 Pilot: "Smooth, full".
func test_preset_3_yaw_smooth_full() -> String:
	return _row(2, "yaw")


## Pitch, 3 Pilot: "Full".
func test_preset_3_pitch_full() -> String:
	return _row(2, "pitch")


## Roll, 3 Pilot: "Manual, optional auto-level".
func test_preset_3_roll_manual_optional_auto_level() -> String:
	return _row(2, "roll")


## Yaw, pitch and roll, 4 Unrestricted: full and fully manual; the filter
## leaves every input untouched (CMF-2).
func test_preset_4_no_intervention() -> String:
	return _row(3, "all")


## CMF-6: the same thrust-only sequence gives the same speed and energy on
## every tick whichever preset filters it.
func test_all_presets_same_speed_and_energy() -> String:
	var curves: Array[PackedFloat64Array] = []
	for index: int in PRESETS.size():
		var filter: ComfortInputFilter = ComfortInputFilter.new(_load(index))
		var sim: Sim = Sim.new(7)
		var curve: PackedFloat64Array = PackedFloat64Array()
		for raw: ShipInput in _random_inputs(1000):
			raw.turn_q = Vector3i.ZERO
			var inputs: Array[ShipInput] = [filter.filter(raw, sim.ships[0].orientation)]
			sim.step(inputs)
			curve.append(sim.ships[0].velocity.length())
			curve.append(sim.ships[0].energy)
		curves.append(curve)
	if curves[0].size() != TICKS * 2:
		return "flew %d values, want %d" % [curves[0].size(), TICKS * 2]
	for index: int in range(1, curves.size()):
		for i: int in curves[0].size():
			if curves[index][i] != curves[0][i]:
				return "preset %d tick %d: %s %f, preset 1 %f" % [index + 1, i / 2,
					"speed" if i % 2 == 0 else "energy", curves[index][i], curves[0][i]]
	var speeds: float = 0.0
	for i: int in range(0, curves[0].size(), 2):
		speeds = maxf(speeds, curves[0][i])
	if speeds <= 0.0:
		return "the thrust sequence never moved the ship"
	return ""
