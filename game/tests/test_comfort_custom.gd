extends RefCounted

## The custom comfort mode (CMF-1): a base preset with any row of the comfort
## table changed, read from JSON; bad fields rejected by name with the base kept
## (CMF-6, ARC-3, ARC-4).

const SCRATCH_DIR: String = "user://test_comfort_custom"
## One override per row of the comfort table, each different from preset 2
## (Guided), the base used below.
const ROWS: Dictionary = {
	"yaw": {"yaw_mode": "SNAP", "snap_angle_deg": 45.0, "yaw_rate_cap_deg_per_s": 75.0},
	"pitch": {"pitch_mode": "SNAP", "pitch_rate_cap_deg_per_s": 40.0, "pitch_limit_deg": 50.0},
	"roll": {"roll_mode": "MANUAL", "auto_level": false, "auto_level_rate_deg_per_s": 12.0,
		"auto_level_snap_threshold_deg": 8.0},
	"vignette": {"vignette_strength": 0.35, "vignette_trigger": "ALL_MOTION"},
	"cockpit": {"cockpit_frame": "OPEN_CANOPY", "cockpit_file": "res://xr/cockpits/open.json"},
	"acceleration feel": {"acceleration_softening": false, "inertia_drift": true},
	"hits": {"hit_shake": 0.9, "hit_spin": true},
	"refresh rate": {"refresh_rate_hz": 72, "allow_120_hz": true},
	"breaks": {"break_reminder_minutes": 45.0},
	"swivel chair": {"swivel_enabled": true, "swivel_dead_zone_deg": 20.0, "swivel_gain_per_deg": 0.05,
		"swivel_max_input": 0.7, "swivel_follow_deg_per_s": 10.0},
}
const FIELDS_SEEN: Array[String] = ["display_name"]


static func parse(data: Dictionary) -> ComfortCustom:
	return ComfortCustom.parse(JSON.stringify(data))


static func expected(field: String, json_value: Variant) -> Variant:
	if typeof(json_value) == TYPE_STRING and field != "cockpit_file":
		var enums: Dictionary = {"yaw_mode": ComfortPreset.YawMode, "pitch_mode": ComfortPreset.PitchMode,
			"roll_mode": ComfortPreset.RollMode, "vignette_trigger": ComfortPreset.VignetteTrigger,
			"cockpit_frame": ComfortPreset.CockpitKind}
		return enums[field][json_value]
	return json_value


func test_default_path() -> String:
	if ComfortCustom.DEFAULT_PATH != "user://meltdown_comfort_custom.json":
		return "default path is %s" % ComfortCustom.DEFAULT_PATH
	return ""


func test_base_only_gives_the_base_preset_named_custom() -> String:
	for number: int in [1, 2, 3, 4]:
		var result: ComfortCustom = parse({"base": number})
		if not result.error.is_empty():
			return "base %d rejected: %s" % [number, result.error]
		var base: ComfortPreset = ComfortPresetFiles.load_number(number)
		for field: String in ComfortCustom.settable_fields():
			if field == "display_name":
				continue
			if result.preset.get(field) != base.get(field):
				return "base %d: %s is %s, base has %s" % [number, field, result.preset.get(field), base.get(field)]
		if result.preset.display_name != "Custom":
			return "display_name defaulted to \"%s\", expected Custom" % result.preset.display_name
		if result.preset == base:
			return "base %d: the custom preset is the shipped resource, not a copy" % number
	return ""


func test_display_name_can_be_set() -> String:
	var result: ComfortCustom = parse({"base": 3, "display_name": "Mine"})
	if not result.error.is_empty() or result.preset.display_name != "Mine":
		return "display_name not set: %s" % result.error
	return ""


func test_each_table_row_can_be_overridden() -> String:
	var seen: Array[String] = FIELDS_SEEN.duplicate()
	for row: String in ROWS:
		var data: Dictionary = {"base": 2}
		data.merge(ROWS[row])
		var result: ComfortCustom = parse(data)
		if not result.error.is_empty():
			return "row %s rejected: %s" % [row, result.error]
		var base: ComfortPreset = ComfortPresetFiles.load_number(2)
		for field: String in ROWS[row]:
			seen.append(field)
			var want: Variant = expected(field, ROWS[row][field])
			if result.preset.get(field) != want:
				return "row %s: %s is %s, expected %s" % [row, field, result.preset.get(field), want]
			if base.get(field) == want:
				return "row %s: %s already %s in the base, so the test proves nothing" % [row, field, want]
	# Every exported field is covered, so the table cannot gain a row the test misses.
	for field: String in ComfortCustom.settable_fields():
		if not seen.has(field):
			return "field %s has no override in the test" % field
	return ""


func test_overrides_leave_the_shipped_preset_unchanged() -> String:
	parse({"base": 1, "yaw_mode": "SMOOTH", "hit_spin": true, "vignette_strength": 0.0})
	var anchored: ComfortPreset = ComfortPresetFiles.load_number(1)
	if anchored.has_smooth_rotation():
		return "a custom file changed the shipped preset 1 (CMF-3)"
	if anchored.vignette_strength != 0.8:
		return "shipped preset 1 vignette is %s after a custom load" % anchored.vignette_strength
	return ""


func test_bad_fields_are_rejected_by_name_and_the_base_kept() -> String:
	var cases: Array[Dictionary] = [
		{"field": "top_speed", "value": 300.0},
		{"field": "hit_spin", "value": 1.0},
		{"field": "snap_angle_deg", "value": "fast"},
		{"field": "refresh_rate_hz", "value": 90.5},
		{"field": "yaw_mode", "value": 1.0},
		{"field": "yaw_mode", "value": "SPIN"},
		{"field": "display_name", "value": 3.0},
		{"field": "cockpit_file", "value": "user://my_cockpit.json"},
		{"field": "cockpit_file", "value": "res://xr/cockpits/missing.json"},
		{"field": "vignette_strength", "value": 1.5},
		{"field": "hit_shake", "value": -0.1},
		{"field": "break_reminder_minutes", "value": -5.0},
		{"field": "swivel_dead_zone_deg", "value": -5.0},
		{"field": "swivel_follow_deg_per_s", "value": 500.0},
		{"field": "swivel_enabled", "value": "yes"},
	]
	var base: ComfortPreset = ComfortPresetFiles.load_number(3)
	for case: Dictionary in cases:
		var result: ComfortCustom = parse({"base": 3, "hit_shake": 0.1, case["field"]: case["value"]})
		if result.error.find(case["field"]) < 0:
			return "%s = %s: error \"%s\" does not name the field" % [case["field"], case["value"], result.error]
		if result.preset != base:
			return "%s = %s: the base preset was not used unchanged" % [case["field"], case["value"]]
	return ""


func test_swivel_can_be_switched_on_over_preset_two() -> String:
	# CMF-7 is a row of the custom mode (#779): only the switch changes.
	var result: ComfortCustom = parse({"base": 2, "swivel_enabled": true})
	if not result.error.is_empty():
		return "swivel_enabled rejected: %s" % result.error
	if not result.preset.swivel_enabled:
		return "swivel_enabled is still off"
	var base: ComfortPreset = ComfortPresetFiles.load_number(2)
	for field: String in ComfortCustom.settable_fields():
		if field == "display_name" or field == "swivel_enabled":
			continue
		if result.preset.get(field) != base.get(field):
			return "%s is %s, preset 2 has %s" % [field, result.preset.get(field), base.get(field)]
	var swivel: SwivelYaw = SwivelYaw.from_preset(result.preset)
	if not swivel.enabled or swivel.error != "":
		return "SwivelYaw from the custom preset is off: %s" % swivel.error
	return ""


func test_bad_base_is_rejected_by_name() -> String:
	var start: ComfortPreset = ComfortPresetFiles.load_number(ComfortPresetFiles.START_NUMBER)
	for data: Dictionary in [{}, {"base": 0.0}, {"base": 5.0}, {"base": 2.5}, {"base": "2"}]:
		var result: ComfortCustom = parse(data)
		if result.error.find("base") < 0:
			return "%s: error \"%s\" does not name base" % [data, result.error]
		if result.preset != start:
			return "%s: did not fall back to the start preset" % data
	return ""


func test_garbled_text_is_reported() -> String:
	for text: String in ["", "{", "[1, 2]", "\"base\""]:
		var result: ComfortCustom = ComfortCustom.parse(text)
		if result.error.is_empty() or result.preset == null:
			return "\"%s\" was not reported, or left no preset" % text
	return ""


func test_file_round_trip_and_missing_file() -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/custom.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if ComfortPresetFiles.load_custom(path) != null:
		return "a missing file gave a preset"
	if not ComfortCustom.load_from(path).error.is_empty():
		return "a missing file was reported as an error"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"base": 4, "display_name": "Steady", "pitch_limit_deg": 70.0}))
	file.close()
	var preset: ComfortPreset = ComfortPresetFiles.load_custom(path)
	if preset == null or preset.display_name != "Steady" or preset.pitch_limit_deg != 70.0:
		return "the saved custom file was not read back"
	return ""


func test_the_custom_file_holds_no_simulation_setting() -> String:
	# CMF-6: only ComfortPreset fields can be set, and none of them is speed, damage or time.
	for field: String in ComfortCustom.settable_fields():
		for word: String in ["speed", "damage", "timer", "health", "thrust"]:
			if field.contains(word):
				return "settable field %s looks like simulation state" % field
	var source: String = FileAccess.get_file_as_string("res://xr/comfort_custom.gd")
	if source.contains("res://core/") or source.contains("ShipState"):
		return "comfort_custom.gd refers to the simulation"
	return ""
