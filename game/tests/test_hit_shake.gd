extends RefCounted

## The "Hits" row of the comfort table as a view effect (CMF-1, CMF-2, CMF-3,
## ARC-3): preset 1 never moves the view, preset 2 shakes less than preset 3,
## only a preset with `hit_spin` rolls, every hit fades out within the decay
## time, and the data file is range-checked.

const SCRIPT_PATH: String = "res://xr/hit_shake.gd"
const CORE_DIR: String = "res://core"
## One headset frame at 90 Hz.
const FRAME_S: float = 1.0 / 90.0


func _valid_data() -> Dictionary:
	return {
		"max_offset_m": 0.02, "max_roll_deg": 6.0, "decay_s": 0.4,
		"full_impact_speed_m_per_s": 15.0, "shake_frequency_hz": 18.0,
	}


func _shake_for(number: int) -> HitShake:
	var shake: HitShake = HitShake.load_file()
	shake.preset = ComfortPresetFiles.load_number(number)
	return shake


func _impact(speed: float, ship: int = 0, normal: Vector3 = Vector3.BACK) -> Array[SimEvent]:
	var events: Array[SimEvent] = [SimEvent.new(SimEvent.Kind.WALL_IMPACT, ship, speed, normal)]
	return events


## Largest translation and roll (radians) over `seconds` of frames.
static func _peaks(shake: HitShake, seconds: float) -> Vector2:
	var peak: Vector2 = Vector2.ZERO
	var t: float = 0.0
	while t < seconds:
		var offset: Transform3D = shake.advance(FRAME_S)
		peak.x = maxf(peak.x, offset.origin.length())
		peak.y = maxf(peak.y, offset.basis.get_rotation_quaternion().get_angle())
		t += FRAME_S
	return peak


func test_data_file_loads() -> String:
	var shake: HitShake = HitShake.load_file()
	if shake.error != "":
		return shake.error
	if shake.max_offset_m <= 0.0 or shake.decay_s <= 0.0:
		return "shipped file shows no shake: offset %f, decay %f" % [shake.max_offset_m, shake.decay_s]
	return ""


func test_keys_match_the_fields() -> String:
	var fields: Array[String] = []
	for property: Dictionary in load(SCRIPT_PATH).get_script_property_list():
		if property["type"] == TYPE_FLOAT and not property["name"].begins_with("_"):
			fields.append(property["name"])
	for key: String in HitShake.KEYS:
		if not fields.has(key):
			return "key %s has no field" % key
		if not HitShake.RANGES.has(key):
			return "key %s has no range" % key
	if fields.size() != HitShake.KEYS.size():
		return "fields %s do not match keys %s" % [fields, HitShake.KEYS]
	return ""


func test_bad_values_are_rejected_with_the_field_named() -> String:
	for key: String in HitShake.KEYS:
		var high: Dictionary = _valid_data()
		high[key] = float(HitShake.RANGES[key][1]) + 1.0
		var shake: HitShake = HitShake.parse_json(JSON.stringify(high))
		if shake.error == "" or not key in shake.error:
			return "%s above its range gave error \"%s\"" % [key, shake.error]
		var missing: Dictionary = _valid_data()
		missing.erase(key)
		shake = HitShake.parse_json(JSON.stringify(missing))
		if shake.error == "" or not key in shake.error:
			return "missing %s gave error \"%s\"" % [key, shake.error]
		var wrong_type: Dictionary = _valid_data()
		wrong_type[key] = true
		shake = HitShake.parse_json(JSON.stringify(wrong_type))
		if shake.error == "" or not key in shake.error:
			return "%s as a bool gave error \"%s\"" % [key, shake.error]
	var unknown: Dictionary = _valid_data()
	unknown["shake_amount"] = 1.0
	var rejected: HitShake = HitShake.parse_json(JSON.stringify(unknown))
	if not "shake_amount" in rejected.error:
		return "unknown key gave error \"%s\"" % rejected.error
	if HitShake.parse_json(JSON.stringify(_valid_data())).error != "":
		return "valid data was rejected"
	if HitShake.load_file("res://xr/no_such_file.json").error == "":
		return "missing file was accepted"
	return ""


func test_preset_1_is_identity_for_a_burst_of_strong_impacts() -> String:
	var shake: HitShake = _shake_for(1)
	for frame: int in 120:
		if frame % 3 == 0:
			shake.feed(_impact(500.0, 0, Vector3(1.0, 0.0, 0.0)), 0, Basis.IDENTITY)
		var offset: Transform3D = shake.advance(FRAME_S)
		if offset != Transform3D.IDENTITY:
			return "preset 1 moved the view on frame %d: %s" % [frame, offset]
	return ""


func test_preset_2_peak_is_below_preset_3_peak() -> String:
	var guided: HitShake = _shake_for(2)
	var pilot: HitShake = _shake_for(3)
	guided.feed(_impact(12.0), 0, Basis.IDENTITY)
	pilot.feed(_impact(12.0), 0, Basis.IDENTITY)
	var low: Vector2 = _peaks(guided, 0.5)
	var high: Vector2 = _peaks(pilot, 0.5)
	if high.x <= 0.0:
		return "preset 3 did not shake"
	if low.x <= 0.0 or low.x >= high.x:
		return "preset 2 peak %f m, preset 3 peak %f m" % [low.x, high.x]
	return ""


func test_only_spin_presets_rotate() -> String:
	for number: int in [1, 2, 3, 4]:
		var shake: HitShake = _shake_for(number)
		shake.feed(_impact(30.0, 0, Vector3(-1.0, 0.0, 0.0)), 0, Basis.IDENTITY)
		var roll: float = _peaks(shake, 0.5).y
		if shake.preset.hit_spin and roll <= 0.0:
			return "preset %d has hit_spin but did not roll" % number
		if not shake.preset.hit_spin and roll != 0.0:
			return "preset %d rolled %f rad without hit_spin" % [number, roll]
	var unrestricted: HitShake = _shake_for(4)
	unrestricted.preset = unrestricted.preset.duplicate()
	unrestricted.preset.hit_spin = false
	unrestricted.feed(_impact(30.0), 0, Basis.IDENTITY)
	if _peaks(unrestricted, 0.5).y != 0.0:
		return "preset 4 with hit_spin off still rolled"
	return ""


func test_offsets_stay_within_the_caps() -> String:
	var shake: HitShake = _shake_for(4)
	var cap_roll: float = deg_to_rad(shake.max_roll_deg)
	for frame: int in 90:
		shake.feed(_impact(1000.0), 0, Basis.IDENTITY)
		var offset: Transform3D = shake.advance(FRAME_S)
		if offset.origin.length() > shake.max_offset_m + 1e-6:
			return "offset %f m over the %f m cap" % [offset.origin.length(), shake.max_offset_m]
		if offset.basis.get_rotation_quaternion().get_angle() > cap_roll + 1e-6:
			return "roll over the cap on frame %d" % frame
	return ""


func test_back_to_identity_within_the_decay_time() -> String:
	for number: int in [2, 3, 4]:
		var shake: HitShake = _shake_for(number)
		shake.feed(_impact(100.0), 0, Basis.IDENTITY)
		var elapsed: float = 0.0
		var offset: Transform3D = shake.advance(FRAME_S)
		elapsed += FRAME_S
		if offset == Transform3D.IDENTITY:
			return "preset %d showed nothing right after a hit" % number
		while elapsed < shake.decay_s:
			offset = shake.advance(FRAME_S)
			elapsed += FRAME_S
		if offset != Transform3D.IDENTITY:
			return "preset %d still offset %s after %f s" % [number, offset, elapsed]
	return ""


func test_zero_magnitude_and_other_events_do_nothing() -> String:
	var shake: HitShake = _shake_for(4)
	var events: Array[SimEvent] = [
		SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 0.0, Vector3.BACK),
		SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, -3.0, Vector3.BACK),
		SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, 0),
		SimEvent.new(SimEvent.Kind.ENERGY_DEPLETED, 0),
		SimEvent.new(SimEvent.Kind.WALL_IMPACT, 1, 20.0, Vector3.BACK),
	]
	shake.feed(events, 0, Basis.IDENTITY)
	for frame: int in 30:
		if shake.advance(FRAME_S) != Transform3D.IDENTITY:
			return "moved on frame %d without a hit on this ship" % frame
	return ""


func test_feed_leaves_the_events_unchanged() -> String:
	var event: SimEvent = SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 9.0, Vector3.UP)
	var copy: SimEvent = SimEvent.new(event.kind, event.ship, event.magnitude, event.vector)
	var events: Array[SimEvent] = [event]
	var shake: HitShake = _shake_for(4)
	shake.feed(events, 0, Basis.IDENTITY)
	shake.advance(FRAME_S)
	if not event.equals(copy):
		return "feed changed the event to %s" % event
	return ""


## ARC-3, CMF-6: the effect may read `SimEvent` and nothing else from the
## simulation, so it has no way to write ship or sim state.
func test_reads_only_sim_events_from_core() -> String:
	var core_names: Array[String] = []
	for file: String in DirAccess.get_files_at(CORE_DIR):
		if not file.ends_with(".gd"):
			continue
		var found: RegExMatch = RegEx.create_from_string("class_name\\s+(\\w+)") \
			.search(FileAccess.get_file_as_string(CORE_DIR.path_join(file)))
		if found != null:
			core_names.append(found.get_string(1))
	if not core_names.has("Sim") or not core_names.has("SimEvent"):
		return "core classes were not read"
	var source: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	for core_name: String in core_names:
		if core_name == "SimEvent":
			continue
		if RegEx.create_from_string("\\b%s\\b" % core_name).search(source) != null:
			return "%s references core class %s" % [SCRIPT_PATH, core_name]
	return ""


## Rolled left: the camera's top leans towards its own left (-X).
static func _rolled_left(shake: HitShake) -> bool:
	return shake.advance(FRAME_S).basis.y.x < 0.0


## The hit side is read in the ship's frame (#169): a ship facing +X and one
## facing -X, each hit on its own right, both roll left; on its left, right.
func test_a_hit_on_the_ship_right_rolls_left_whichever_way_it_faces() -> String:
	# Godot's forward is -Z; a quarter turn about up faces the ship along +X or -X.
	var facings: Dictionary[String, Basis] = {
		"+X": Basis(Vector3.UP, -PI / 2.0), "-X": Basis(Vector3.UP, PI / 2.0),
		"-Z": Basis.IDENTITY,
	}
	for facing: String in facings:
		var ship_basis: Basis = facings[facing]
		# The wall on the right: its normal points back to the ship's left.
		var right_hit: HitShake = _shake_for(4)
		right_hit.feed(_impact(30.0, 0, -ship_basis.x), 0, ship_basis)
		if not _rolled_left(right_hit):
			return "ship facing %s hit on its right did not roll left" % facing
		var left_hit: HitShake = _shake_for(4)
		left_hit.feed(_impact(30.0, 0, ship_basis.x), 0, ship_basis)
		if _rolled_left(left_hit):
			return "ship facing %s hit on its left rolled left" % facing
	return ""
