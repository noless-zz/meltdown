extends RefCounted

## Preset 4's inertia drift as a view effect (#840; CMF-1, CMF-3, CMF-6,
## ARC-3, ARC-4): a boost pushes the eye back and it settles within the file's
## time, presets 1 to 3 get nothing, the offset never passes the file's limit
## and never rotates, a preset change drops it, and the file is range-checked.

const SCRIPT_PATH: String = "res://xr/inertia_drift.gd"
## One headset frame at 90 Hz.
const FRAME_S: float = 1.0 / 90.0
## Boost acceleration of the shipped ship tuning, metres per second squared.
const BOOST_ACCEL: float = 80.0


func _valid_data() -> Dictionary:
	return {"lag_m_per_m_per_s": 0.002, "settle_s": 0.5, "max_offset_m": 0.04}


func _drift() -> InertiaDrift:
	return InertiaDrift.load_file()


static func _preset(number: int) -> ComfortPreset:
	return ComfortPresetFiles.load_number(number)


## Flies `seconds` of a boost from a stop along the ship's forward (-Z) and
## returns the offset of every frame.
static func _boost(drift: InertiaDrift, preset: ComfortPreset, seconds: float,
		orientation: Basis = Basis.IDENTITY) -> Array[Transform3D]:
	var offsets: Array[Transform3D] = []
	var speed: float = 0.0
	drift.advance(preset, Vector3.ZERO, orientation, FRAME_S)
	var t: float = 0.0
	while t < seconds:
		speed += BOOST_ACCEL * FRAME_S
		offsets.append(drift.advance(preset, orientation * Vector3(0.0, 0.0, -speed), orientation, FRAME_S))
		t += FRAME_S
	return offsets


func test_data_file_loads() -> String:
	var drift: InertiaDrift = _drift()
	if drift.error != "":
		return drift.error
	if drift.max_offset_m <= 0.0 or drift.lag_m_per_m_per_s <= 0.0:
		return "the shipped file shows no drift: %f m, %f" % [drift.max_offset_m, drift.lag_m_per_m_per_s]
	return ""


func test_keys_match_the_fields() -> String:
	var fields: Array[String] = []
	for property: Dictionary in load(SCRIPT_PATH).get_script_property_list():
		if property["type"] == TYPE_FLOAT and not property["name"].begins_with("_"):
			fields.append(property["name"])
	for key: String in InertiaDrift.KEYS:
		if not fields.has(key):
			return "key %s has no field" % key
		if not InertiaDrift.RANGES.has(key):
			return "key %s has no range" % key
	for field: String in fields:
		if not InertiaDrift.KEYS.has(field):
			return "field %s has no key" % field
	return ""


func test_the_largest_offset_stays_inside_the_head_reach() -> String:
	if InertiaDrift.OFFSET_CEILING_M >= HeadRecentre.HEAD_REACH:
		return "the ceiling %f m is not inside the head reach %f m" % [
			InertiaDrift.OFFSET_CEILING_M, HeadRecentre.HEAD_REACH]
	if float(InertiaDrift.RANGES["max_offset_m"][1]) > InertiaDrift.OFFSET_CEILING_M:
		return "max_offset_m may pass the ceiling"
	return ""


func test_a_boost_on_preset_4_pushes_the_eye_back_then_settles() -> String:
	var drift: InertiaDrift = _drift()
	var preset: ComfortPreset = _preset(4)
	if not preset.inertia_drift:
		return "preset 4 has no inertia_drift"
	var offsets: Array[Transform3D] = _boost(drift, preset, 0.3)
	var last: Vector3 = offsets[offsets.size() - 1].origin
	# Forward is -Z, so lagging behind a forward boost is +Z.
	if last.z <= 0.0:
		return "a forward boost moved the eye to %s, not back" % last
	if absf(last.x) > 1e-6 or absf(last.y) > 1e-6:
		return "a straight boost moved the eye sideways: %s" % last
	var speed: Vector3 = Vector3(0.0, 0.0, -BOOST_ACCEL * 0.3)
	var elapsed: float = 0.0
	while elapsed < drift.settle_s:
		drift.advance(preset, speed, Basis.IDENTITY, FRAME_S)
		elapsed += FRAME_S
	var settled: Vector3 = drift.offset().origin
	return "" if settled == Vector3.ZERO else "still %s off after %f s" % [settled, elapsed]


func test_the_offset_is_in_the_ships_frame() -> String:
	var drift: InertiaDrift = _drift()
	var turned: Basis = Basis(Vector3.UP, PI / 2.0)
	var offsets: Array[Transform3D] = _boost(drift, _preset(4), 0.1, turned)
	var last: Vector3 = offsets[offsets.size() - 1].origin
	if last.z <= 0.0 or absf(last.x) > 1e-5:
		return "a boost of a turned ship drifted to %s, not straight back in its frame" % last
	return ""


func test_presets_1_to_3_get_no_offset() -> String:
	for number: int in [1, 2, 3]:
		var drift: InertiaDrift = _drift()
		for offset: Transform3D in _boost(drift, _preset(number), 0.5):
			if offset != Transform3D.IDENTITY:
				return "preset %d drifted to %s" % [number, offset.origin]
	var none: InertiaDrift = _drift()
	for offset: Transform3D in _boost(none, null, 0.2):
		if offset != Transform3D.IDENTITY:
			return "no preset drifted"
	return ""


func test_a_custom_preset_without_drift_gets_none() -> String:
	var custom: ComfortPreset = _preset(4).duplicate() as ComfortPreset
	custom.inertia_drift = false
	for offset: Transform3D in _boost(_drift(), custom, 0.3):
		if offset != Transform3D.IDENTITY:
			return "a preset without inertia_drift drifted"
	return ""


func test_never_larger_than_the_limit_and_never_rotated() -> String:
	var drift: InertiaDrift = _drift()
	var preset: ComfortPreset = _preset(4)
	var orientation: Basis = Basis(Vector3(1.0, 1.0, 0.0).normalized(), 0.7)
	var velocity: Vector3 = Vector3.ZERO
	var peak: float = 0.0
	for frame: int in 300:
		# Wall bounces and reversals far bigger than any boost.
		velocity = Vector3(sin(frame * 0.9), cos(frame * 1.3), sin(frame * 0.4)) * 200.0
		var offset: Transform3D = drift.advance(preset, velocity, orientation, FRAME_S)
		if offset.basis != Basis.IDENTITY:
			return "frame %d rotated the view: %s" % [frame, offset.basis]
		peak = maxf(peak, offset.origin.length())
		if offset.origin.length() > drift.max_offset_m + 1e-6:
			return "frame %d drifted %f m, past %f" % [frame, offset.origin.length(), drift.max_offset_m]
	return "" if peak > 0.0 else "nothing drifted"


func test_a_preset_change_drops_the_offset_at_once() -> String:
	var drift: InertiaDrift = _drift()
	var offsets: Array[Transform3D] = _boost(drift, _preset(4), 0.2)
	if offsets[offsets.size() - 1] == Transform3D.IDENTITY:
		return "the boost gave no offset to drop"
	var speed: Vector3 = Vector3(0.0, 0.0, -BOOST_ACCEL * 0.2)
	if drift.advance(_preset(3), speed, Basis.IDENTITY, FRAME_S) != Transform3D.IDENTITY:
		return "preset 3 kept the offset"
	# Back on preset 4 the drift starts from nothing, not from the old offset.
	if drift.advance(_preset(4), speed, Basis.IDENTITY, FRAME_S) != Transform3D.IDENTITY:
		return "returning to preset 4 brought an offset back"
	return ""


func test_a_paused_frame_holds_still() -> String:
	var drift: InertiaDrift = _drift()
	var offsets: Array[Transform3D] = _boost(drift, _preset(4), 0.1)
	var held: Transform3D = offsets[offsets.size() - 1]
	if drift.advance(_preset(4), Vector3(0.0, 0.0, -30.0), Basis.IDENTITY, 0.0) != held:
		return "a paused frame moved the drift"
	return ""


func test_a_bad_file_is_rejected_naming_the_field() -> String:
	var cases: Array = [
		["missing", "settle_s", null],
		["text", "settle_s", "fast"],
		["bool", "max_offset_m", true],
		["too large", "max_offset_m", 0.2],
		["negative", "lag_m_per_m_per_s", -0.001],
		["too short", "settle_s", 0.0],
	]
	for case: Array in cases:
		var data: Dictionary = _valid_data()
		if case[2] == null:
			data.erase(case[1])
		else:
			data[case[1]] = case[2]
		var drift: InertiaDrift = InertiaDrift.parse_json(JSON.stringify(data))
		if drift.error == "" or not drift.error.contains(case[1]):
			return "%s %s: error \"%s\" does not name the field" % [case[0], case[1], drift.error]
	var extra: Dictionary = _valid_data()
	extra["wobble"] = 1.0
	if not InertiaDrift.parse_json(JSON.stringify(extra)).error.contains("wobble"):
		return "an unknown key was not named"
	if InertiaDrift.parse_json("[1]").error == "" or InertiaDrift.parse_json("{").error == "":
		return "bad JSON was accepted"
	if InertiaDrift.parse_json(JSON.stringify(_valid_data())).error != "":
		return "a valid file was rejected"
	return ""


func test_a_rejected_file_turns_the_drift_off() -> String:
	if DriftWiring.load_drift("res://xr/no_such_drift.json") != null:
		return "a missing file gave a drift"
	var wiring: DriftWiring = DriftWiring.new()
	wiring.drift = null
	var ship: ShipState = ShipState.new()
	wiring.see(ship)
	wiring.advance(_preset(4), FRAME_S)
	ship.velocity = Vector3(0.0, 0.0, -30.0)
	wiring.see(ship)
	return "" if wiring.advance(_preset(4), FRAME_S) == Transform3D.IDENTITY else "a rejected file drifted"


func test_the_view_side_files_read_ship_state_only() -> String:
	for path: String in ["res://xr/inertia_drift.gd", "res://drift_wiring.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		for forbidden: String in [".velocity =", ".orientation =", ".position =", "Sim."]:
			if source.contains(forbidden):
				return "%s contains \"%s\"" % [path, forbidden]
	return ""
