extends RefCounted

## The thumbsticks dead zone comes from the layout file (#855, PLT-5, ARC-4):
## both shipped files set 0.15, a file without it uses 0.15, a bad value is
## dropped with a warning naming the file and the field while the bindings
## still load, and the value applies to both sticks in either hand.

const FILES: Array[String] = [
	ThumbstickMapping.DEFAULT_LAYOUT_FILE, ThumbstickMapping.PAIRED_LAYOUT_FILE,
]
const BINDINGS: String = "\"yaw\": {\"right_stick_x\": 1.0}, \"strafe\": {\"left_stick_x\": 1.0}"


func _with_dead_zone(value: String) -> ThumbstickMapping:
	return ThumbstickMapping.from_json(
		"{\"stick_dead_zone\": %s, %s}" % [value, BINDINGS], "res://xr/layouts/test.json")


func test_shipped_layouts_set_the_old_value() -> String:
	for path: String in FILES:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (raw is Dictionary and (raw as Dictionary).has(StickDeadZone.FIELD)):
			return "%s does not set %s" % [path, StickDeadZone.FIELD]
		var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
		if mapping.error != "" or mapping.warning != "":
			return "%s: error \"%s\" warning \"%s\"" % [path, mapping.error, mapping.warning]
		if mapping.stick_dead_zone != 0.15:
			return "%s gives %s, want 0.15" % [path, mapping.stick_dead_zone]
	return ""


func test_built_in_default_matches_the_files() -> String:
	# The game builds its mapping from the built-in layout, so the files and
	# the built-in must agree, as the bindings do.
	if ThumbstickMapping.new().stick_dead_zone != 0.15 or ThumbstickMapping.STICK_DEAD_ZONE != 0.15:
		return "built-in dead zone is %s" % ThumbstickMapping.new().stick_dead_zone
	return ""


func test_dead_zone_is_not_a_binding() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	if mapping.layout.has(StickDeadZone.FIELD):
		return "the dead zone leaked into the bindings: %s" % mapping.layout
	return ""


func test_missing_key_uses_the_default() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_json("{%s}" % BINDINGS)
	if mapping.error != "" or mapping.warning != "":
		return "error \"%s\" warning \"%s\"" % [mapping.error, mapping.warning]
	if mapping.stick_dead_zone != 0.15:
		return "got %s, want 0.15" % mapping.stick_dead_zone
	return ""


func test_bad_values_are_rejected_by_name() -> String:
	for value: String in ["true", "\"0.2\"", "null", "[0.2]", "-0.01", "0.51", "1"]:
		var mapping: ThumbstickMapping = _with_dead_zone(value)
		if mapping.error != "":
			return "%s: the whole layout was rejected: %s" % [value, mapping.error]
		if mapping.stick_dead_zone != 0.15:
			return "%s: got %s, want 0.15" % [value, mapping.stick_dead_zone]
		if not (mapping.warning.contains("test.json") and mapping.warning.contains("stick_dead_zone")):
			return "%s: warning \"%s\" names neither file nor field" % [value, mapping.warning]
		if mapping.layout != {"yaw": {"right_stick_x": 1.0}, "strafe": {"left_stick_x": 1.0}}:
			return "%s: the bindings did not load: %s" % [value, mapping.layout]
	return ""


func test_bounds_are_accepted() -> String:
	for value: String in ["0", "0.5", "0.25"]:
		var mapping: ThumbstickMapping = _with_dead_zone(value)
		if mapping.warning != "" or mapping.stick_dead_zone != float(value):
			return "%s: got %s, warning \"%s\"" % [value, mapping.stick_dead_zone, mapping.warning]
	return ""


func test_a_wider_dead_zone_zeroes_a_small_deflection() -> String:
	var mapping: ThumbstickMapping = _with_dead_zone("0.25")
	var input: ShipInput = mapping.map_controls(Vector2(0.2, 0.0), Vector2(0.2, 0.0), 0.0, 0.0, 0.0, 0.0)
	if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO:
		return "0.2 under a 0.25 dead zone moved: thrust %s turn %s" % [input.thrust_q, input.turn_q]
	var default_input: ShipInput = ThumbstickMapping.new(mapping.layout).map_controls(
		Vector2(0.2, 0.0), Vector2(0.2, 0.0), 0.0, 0.0, 0.0, 0.0)
	if default_input.thrust_q == Vector3i.ZERO or default_input.turn_q == Vector3i.ZERO:
		return "0.2 under the default 0.15 should move both axes"
	return ""


func test_both_hands_use_the_file_value() -> String:
	for left_handed: bool in [false, true]:
		var mapping: ThumbstickMapping = _with_dead_zone("0.25")
		mapping.left_handed = left_handed
		for stick: Vector2 in [Vector2(0.2, 0.0), Vector2(0.0, 0.0)]:
			var input: ShipInput = mapping.map_controls(stick, stick, 0.0, 0.0, 0.0, 0.0)
			if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO:
				return "left_handed %s: %s moved" % [left_handed, stick]
		var full: ShipInput = mapping.map_controls(Vector2(1, 0), Vector2(1, 0), 0.0, 0.0, 0.0, 0.0)
		if full.thrust_q == Vector3i.ZERO or full.turn_q == Vector3i.ZERO:
			return "left_handed %s: full deflection did nothing" % left_handed
	return ""


func test_same_sticks_give_same_input_as_before() -> String:
	# The file's 0.15 must give exactly what the built-in constant gave.
	var from_file: ThumbstickMapping = ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	var built_in: ThumbstickMapping = ThumbstickMapping.new()
	for x: float in [0.0, 0.1, 0.15, 0.151, 0.3, 0.7, 1.0]:
		for y: float in [-1.0, -0.4, 0.0, 0.2, 0.9]:
			var a: ShipInput = from_file.map_controls(Vector2(x, y), Vector2(y, x), 0.0, 0.0, 0.0, 0.0)
			var b: ShipInput = built_in.map_controls(Vector2(x, y), Vector2(y, x), 0.0, 0.0, 0.0, 0.0)
			if a.thrust_q != b.thrust_q or a.turn_q != b.turn_q:
				return "(%s, %s): file %s %s, built-in %s %s" % [x, y, a.thrust_q, a.turn_q, b.thrust_q, b.turn_q]
	return ""
