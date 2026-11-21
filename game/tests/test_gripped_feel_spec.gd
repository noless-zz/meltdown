extends RefCounted

## The gripped stick and throttle's feel values as data (issue #854, PLT-5,
## ARC-4): the shipped file holds the old constants, each bad field is
## rejected by name, a rejected file falls back to the built-in values as a
## whole, and the mapping gives the same `ShipInput` as the constants did.

const GOOD: Dictionary = {
	"grip_hold_threshold": 0.5,
	"stick_tilt_dead_zone_deg": 4.0,
	"stick_tilt_full_deg": 30.0,
	"stick_twist_dead_zone_deg": 5.0,
	"stick_twist_full_deg": 25.0,
	"throttle_dead_zone_m": 0.02,
	"throttle_full_m": 0.10,
}


static func _with(key: String, value: Variant) -> String:
	return _with_all({key: value})


static func _with_all(changes: Dictionary) -> String:
	var data: Dictionary = GOOD.duplicate()
	data.merge(changes, true)
	return JSON.stringify(data)


static func _without(key: String) -> String:
	var data: Dictionary = GOOD.duplicate()
	data.erase(key)
	return JSON.stringify(data)


## A spec's values equal the built-in ones exactly.
static func _check_built_in(spec: GrippedFeelSpec, label: String) -> String:
	var pairs: Array[Array] = [
		[spec.grip_hold_threshold, GrippedStickMapping.GRIP_HOLD_THRESHOLD, "grip"],
		[spec.stick_tilt_dead_zone_rad, GrippedStickMapping.STICK_TILT_DEAD_ZONE_RAD, "tilt dz"],
		[spec.stick_tilt_full_rad, GrippedStickMapping.STICK_TILT_FULL_RAD, "tilt full"],
		[spec.stick_twist_dead_zone_rad, GrippedStickMapping.STICK_TWIST_DEAD_ZONE_RAD, "twist dz"],
		[spec.stick_twist_full_rad, GrippedStickMapping.STICK_TWIST_FULL_RAD, "twist full"],
		[spec.throttle_dead_zone_m, GrippedStickMapping.THROTTLE_DEAD_ZONE_M, "throttle dz"],
		[spec.throttle_full_m, GrippedStickMapping.THROTTLE_FULL_M, "throttle full"],
	]
	for pair: Array in pairs:
		if float(pair[0]) != float(pair[1]):
			return "%s: %s is %s, want %s" % [label, pair[2], pair[0], pair[1]]
	return ""


func test_shipped_file_loads_the_old_values() -> String:
	var spec: GrippedFeelSpec = GrippedFeelSpec.load_file()
	if spec.error != "":
		return "shipped file rejected: %s" % spec.error
	var values: String = _check_built_in(spec, "shipped file")
	if values != "":
		return values
	if GrippedFeelSpec.shipped().error != "":
		return "shipped() reports %s" % GrippedFeelSpec.shipped().error
	return ""


func test_shipped_file_values_match_the_old_constants() -> String:
	# The constants as they were before #854, so a change to the defaults
	# cannot slip past the comparison above.
	var spec: GrippedFeelSpec = GrippedFeelSpec.load_file()
	var want: Array[float] = [0.5, deg_to_rad(4.0), deg_to_rad(30.0), deg_to_rad(5.0),
		deg_to_rad(25.0), 0.02, 0.10]
	var got: Array[float] = [spec.grip_hold_threshold, spec.stick_tilt_dead_zone_rad,
		spec.stick_tilt_full_rad, spec.stick_twist_dead_zone_rad, spec.stick_twist_full_rad,
		spec.throttle_dead_zone_m, spec.throttle_full_m]
	if got != want:
		return "shipped values %s, want %s" % [got, want]
	return ""


func test_a_new_mapping_uses_the_shipped_file() -> String:
	var mapping: GrippedStickMapping = GrippedStickMapping.new()
	if mapping.feel != GrippedFeelSpec.shipped():
		return "a new mapping does not use the shipped feel"
	return ""


func test_each_bad_field_is_rejected_by_name() -> String:
	var cases: Array[Array] = []
	for key: String in GrippedFeelSpec.RANGES:
		var low: float = GrippedFeelSpec.RANGES[key][0]
		var high: float = GrippedFeelSpec.RANGES[key][1]
		cases.append([_without(key), key, "missing"])
		cases.append([_with(key, "1"), key, "a string"])
		cases.append([_with(key, true), key, "a bool"])
		cases.append([_with(key, low - 0.01), key, "below range"])
		cases.append([_with(key, high + 1.0), key, "above range"])
	cases.append([_with_all({"stick_tilt_dead_zone_deg": 12.0, "stick_tilt_full_deg": 10.0}),
		"stick_tilt_dead_zone_deg", "tilt dead zone above full"])
	cases.append([_with("stick_twist_full_deg", 5.0), "stick_twist_dead_zone_deg",
		"twist dead zone equal to full"])
	cases.append([_with_all({"throttle_dead_zone_m": 0.05, "throttle_full_m": 0.04}),
		"throttle_dead_zone_m", "throttle dead zone above full"])
	cases.append([_with("stick_length_m", 0.2), "stick_length_m", "unknown key"])
	for case: Array in cases:
		var spec: GrippedFeelSpec = GrippedFeelSpec.parse_json(case[0])
		if spec.error == "":
			return "%s %s was accepted: %s" % [case[1], case[2], case[0]]
		if not spec.error.contains("\"%s\"" % case[1]):
			return "%s %s: error does not name the field: %s" % [case[1], case[2], spec.error]
	return ""


func test_bad_json_is_rejected() -> String:
	for text: String in ["{", "[1, 2]", "0.5"]:
		if GrippedFeelSpec.parse_json(text).error == "":
			return "%s was accepted" % text
	return ""


func test_a_rejected_file_falls_back_to_the_built_in_values() -> String:
	# One good changed value next to one bad one: nothing from the file is used.
	var data: Dictionary = GOOD.duplicate()
	data["throttle_full_m"] = 0.2
	data["stick_tilt_full_deg"] = 200.0
	var spec: GrippedFeelSpec = GrippedFeelSpec.parse_json(JSON.stringify(data))
	if spec.error == "":
		return "the bad file was accepted"
	return _check_built_in(spec, "rejected file")


func test_a_missing_file_is_rejected_with_its_path() -> String:
	var path: String = "res://xr/layouts/no_such_feel.json"
	var spec: GrippedFeelSpec = GrippedFeelSpec.load_file(path)
	if not spec.error.contains(path):
		return "missing file error does not name the path: %s" % spec.error
	return _check_built_in(spec, "missing file")


func test_a_valid_file_changes_the_feel() -> String:
	var spec: GrippedFeelSpec = GrippedFeelSpec.parse_json(_with("throttle_full_m", 0.2))
	if spec.error != "":
		return "valid file rejected: %s" % spec.error
	var mapping: GrippedStickMapping = GrippedStickMapping.new()
	mapping.feel = spec
	# Half the new travel: the old travel would read as full.
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.1))
	var forward: float = mapping.axes(pose, Transform3D.IDENTITY, 1.0, 1.0)["forward"]
	var want: float = (0.1 - 0.02) / (0.2 - 0.02)
	if absf(forward - want) > 1e-6:
		return "forward is %s with 0.2 m travel, want %s" % [forward, want]
	return ""


## The mapping before #854, with its constants written out, for one frame.
static func _old_input(left: Transform3D, right: Transform3D, left_grip: float,
		right_grip: float, left_handed: bool, buttons: Dictionary) -> ShipInput:
	var stick: Transform3D = left if left_handed else right
	var throttle: Transform3D = right if left_handed else left
	var stick_held: bool = (left_grip if left_handed else right_grip) >= 0.5
	var throttle_held: bool = (right_grip if left_handed else left_grip) >= 0.5
	var thrust: Vector3 = Vector3.ZERO
	var turn: Vector3 = Vector3.ZERO
	if stick_held:
		var angles: Vector3 = GrippedStickMapping.stick_angles(stick.basis)
		var tilt_dz: float = deg_to_rad(4.0)
		var tilt_full: float = deg_to_rad(30.0)
		turn.x = -GrippedStickMapping.apply_dead_zone(angles.z, tilt_dz, tilt_full) \
			* GrippedStickMapping.MAX_PITCH_RATE
		turn.y = -GrippedStickMapping.apply_dead_zone(
			angles.y, deg_to_rad(5.0), deg_to_rad(25.0)) * GrippedStickMapping.MAX_YAW_RATE
		turn.z = -GrippedStickMapping.apply_dead_zone(angles.x, tilt_dz, tilt_full) \
			* GrippedStickMapping.MAX_ROLL_RATE
	if throttle_held:
		var o: Vector3 = throttle.origin
		thrust = Vector3(GrippedStickMapping.apply_dead_zone(o.x, 0.02, 0.10),
			GrippedStickMapping.apply_dead_zone(o.y, 0.02, 0.10),
			-GrippedStickMapping.apply_dead_zone(-o.z, 0.02, 0.10))
	var button: String = "right_button_lower" if left_handed else "left_button_lower"
	return ShipInput.from_floats(thrust, turn, throttle_held and bool(buttons.get(button, false)))


func test_same_ship_input_as_the_old_constants() -> String:
	var poses: Array[Transform3D] = [
		Transform3D.IDENTITY,
		Transform3D(Basis(Vector3.RIGHT, -0.03), Vector3(0.01, 0.0, -0.015)),
		Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.0, -0.06)),
		Transform3D(Basis(Vector3.BACK, 0.45), Vector3(0.05, -0.03, 0.02)),
		Transform3D(Basis(Vector3.UP, -0.2), Vector3(-0.12, 0.2, 0.0)),
		Transform3D(Basis.from_euler(Vector3(0.2, -0.35, 0.1)), Vector3(0.021, -0.08, -0.099)),
		Transform3D(Basis.from_euler(Vector3(-0.6, 0.7, -0.9)), Vector3(-0.03, 0.04, 0.3)),
	]
	var grips: Array[float] = [1.0, 0.5, 0.49, 0.0]
	var pressed: Dictionary = {"left_button_lower": true, "right_button_lower": true}
	var mapping: GrippedStickMapping = GrippedStickMapping.new()
	for left_handed: bool in [false, true]:
		mapping.left_handed = left_handed
		for i: int in poses.size():
			var left: Transform3D = poses[i]
			var right: Transform3D = poses[(i + 3) % poses.size()]
			for grip: float in grips:
				var got: ShipInput = mapping.map_controls(left, right, grip, 1.0 - grip, pressed)
				var want: ShipInput = _old_input(left, right, grip, 1.0 - grip, left_handed, pressed)
				if got.thrust_q != want.thrust_q or got.turn_q != want.turn_q \
						or got.afterburner != want.afterburner:
					return "pose %d grip %s left-handed %s: got %s %s %s, want %s %s %s" % [
						i, grip, left_handed, got.thrust_q, got.turn_q, got.afterburner,
						want.thrust_q, want.turn_q, want.afterburner]
	return ""
