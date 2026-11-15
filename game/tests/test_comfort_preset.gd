extends RefCounted

## The four comfort presets against the table in requirements section 3
## (CMF-1, CMF-2, CMF-3) and their separation from the simulation (CMF-6, ARC-3).

const PRESET_DIR: String = "res://xr/presets"
const PRESET_SCRIPT: String = "res://xr/comfort_preset.gd"
const CORE_DIR: String = "res://core"
## Simulation quantities a comfort preset must never hold (CMF-6).
const SIM_WORDS: Array[String] = ["speed", "damage", "timer", "health", "energy", "thrust"]

const Yaw = ComfortPreset.YawMode
const Pitch = ComfortPreset.PitchMode
const Roll = ComfortPreset.RollMode
const Trigger = ComfortPreset.VignetteTrigger
const Frame = ComfortPreset.CockpitFrame
const NONE: float = ComfortPreset.NO_LIMIT

## One entry per preset, one key per table row. Numbers the table leaves open
## are the defaults chosen in pull request for #43.
var expected: Dictionary[String, Dictionary] = {
	"anchored": {
		"display_name": "Anchored",
		"yaw_mode": Yaw.SNAP, "snap_angle_deg": 30.0, "yaw_rate_cap_deg_per_s": NONE,
		"pitch_mode": Pitch.SNAP, "pitch_rate_cap_deg_per_s": NONE, "pitch_limit_deg": 60.0,
		"roll_mode": Roll.OFF_AUTO_LEVEL, "auto_level": true,
		"vignette_strength": 0.8, "vignette_trigger": Trigger.ALL_MOTION,
		"cockpit_frame": Frame.SOLID_SMALL_WINDOWS,
		"acceleration_softening": true, "inertia_drift": false,
		"hit_shake": 0.0, "hit_spin": false,
		"refresh_rate_hz": 90, "allow_120_hz": false,
	},
	"guided": {
		"display_name": "Guided",
		"yaw_mode": Yaw.SMOOTH, "snap_angle_deg": 30.0, "yaw_rate_cap_deg_per_s": 60.0,
		"pitch_mode": Pitch.SMOOTH, "pitch_rate_cap_deg_per_s": 45.0, "pitch_limit_deg": NONE,
		"roll_mode": Roll.OFF_AUTO_LEVEL, "auto_level": true,
		"vignette_strength": 0.5, "vignette_trigger": Trigger.ROTATION,
		"cockpit_frame": Frame.SOLID_WIDE_CANOPY,
		"acceleration_softening": true, "inertia_drift": false,
		"hit_shake": 0.3, "hit_spin": false,
		"refresh_rate_hz": 90, "allow_120_hz": false,
	},
	"pilot": {
		"display_name": "Pilot",
		"yaw_mode": Yaw.SMOOTH, "snap_angle_deg": 30.0, "yaw_rate_cap_deg_per_s": NONE,
		"pitch_mode": Pitch.SMOOTH, "pitch_rate_cap_deg_per_s": NONE, "pitch_limit_deg": NONE,
		"roll_mode": Roll.MANUAL, "auto_level": true,
		"vignette_strength": 0.25, "vignette_trigger": Trigger.FAST_ROTATION,
		"cockpit_frame": Frame.OPEN_CANOPY,
		"acceleration_softening": false, "inertia_drift": false,
		"hit_shake": 1.0, "hit_spin": false,
		"refresh_rate_hz": 90, "allow_120_hz": false,
	},
	"unrestricted": {
		"display_name": "Unrestricted",
		"yaw_mode": Yaw.SMOOTH, "snap_angle_deg": 30.0, "yaw_rate_cap_deg_per_s": NONE,
		"pitch_mode": Pitch.SMOOTH, "pitch_rate_cap_deg_per_s": NONE, "pitch_limit_deg": NONE,
		"roll_mode": Roll.FULLY_MANUAL, "auto_level": false,
		"vignette_strength": 0.0, "vignette_trigger": Trigger.NEVER,
		"cockpit_frame": Frame.MINIMAL_GLASS,
		"acceleration_softening": false, "inertia_drift": true,
		"hit_shake": 1.0, "hit_spin": true,
		"refresh_rate_hz": 90, "allow_120_hz": true,
	},
}


static func preset_path(preset_name: String) -> String:
	return "%s/comfort_%s.tres" % [PRESET_DIR, preset_name]


static func load_preset(preset_name: String) -> ComfortPreset:
	return ResourceLoader.load(preset_path(preset_name), "", ResourceLoader.CACHE_MODE_IGNORE) \
		as ComfortPreset


## Names of the fields the preset script declares, in declaration order.
static func field_names() -> Array[String]:
	var names: Array[String] = []
	var script: GDScript = load(PRESET_SCRIPT) as GDScript
	for property: Dictionary in script.get_script_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(str(property["name"]))
	return names


func test_each_preset_loads() -> String:
	for preset_name: String in expected:
		if load_preset(preset_name) == null:
			return "%s does not load as a ComfortPreset" % preset_path(preset_name)
	return ""


func test_preset_folder_holds_exactly_the_four_presets() -> String:
	var dir: DirAccess = DirAccess.open(PRESET_DIR)
	if dir == null:
		return "cannot open %s" % PRESET_DIR
	var found: Array[String] = []
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			found.append(file)
	found.sort()
	var wanted: Array[String] = []
	for preset_name: String in expected:
		wanted.append("comfort_%s.tres" % preset_name)
	wanted.sort()
	if found != wanted:
		return "expected %s, found %s" % [str(wanted), str(found)]
	return ""


func test_table_covers_every_field() -> String:
	var fields: Array[String] = field_names()
	if fields.is_empty():
		return "no fields read from %s" % PRESET_SCRIPT
	for preset_name: String in expected:
		var keys: Array[String] = []
		keys.assign(expected[preset_name].keys())
		for field: String in fields:
			if not keys.has(field):
				return "%s: the test table has no value for %s" % [preset_name, field]
		for key: String in keys:
			if not fields.has(key):
				return "%s: %s is not a field of ComfortPreset" % [preset_name, key]
	return ""


func test_each_field_matches_the_table() -> String:
	for preset_name: String in expected:
		var preset: ComfortPreset = load_preset(preset_name)
		if preset == null:
			return "%s does not load" % preset_name
		var row: Dictionary = expected[preset_name]
		for field: String in row:
			var got: Variant = preset.get(field)
			if got != row[field]:
				return "%s.%s is %s, expected %s" % [preset_name, field, str(got), str(row[field])]
	return ""


func test_every_preset_file_states_every_field() -> String:
	# A field left out of a file would follow the class default, so changing
	# a default would silently change a preset.
	var fields: Array[String] = field_names()
	for preset_name: String in expected:
		var text: String = FileAccess.get_file_as_string(preset_path(preset_name))
		for field: String in fields:
			if not text.contains("\n%s = " % field):
				return "%s does not state %s" % [preset_path(preset_name), field]
	return ""


func test_anchored_never_rotates_smoothly() -> String:
	var preset: ComfortPreset = load_preset("anchored")
	if preset.yaw_mode != Yaw.SNAP:
		return "preset 1 yaw is not snap"
	if preset.pitch_mode != Pitch.SNAP:
		return "preset 1 pitch is not snap"
	if preset.pitch_limit_deg != 60.0:
		return "preset 1 pitch limit is %s, expected 60" % preset.pitch_limit_deg
	if preset.roll_mode != Roll.OFF_AUTO_LEVEL:
		return "preset 1 roll is not off"
	if preset.hit_spin or preset.hit_shake != 0.0:
		return "preset 1 moves the view on a hit"
	if preset.has_smooth_rotation():
		return "preset 1 reports smooth rotation"
	return ""


func test_only_anchored_is_free_of_smooth_rotation() -> String:
	for preset_name: String in ["guided", "pilot", "unrestricted"]:
		if not load_preset(preset_name).has_smooth_rotation():
			return "%s reports no smooth rotation" % preset_name
	return ""


func test_unrestricted_has_no_intervention() -> String:
	var preset: ComfortPreset = load_preset("unrestricted")
	if preset.yaw_mode == Yaw.SNAP or preset.pitch_mode == Pitch.SNAP:
		return "preset 4 snaps"
	if preset.vignette_strength != 0.0 or preset.vignette_trigger != Trigger.NEVER:
		return "preset 4 has a vignette"
	if preset.acceleration_softening:
		return "preset 4 softens acceleration"
	if preset.auto_level or preset.roll_mode != Roll.FULLY_MANUAL:
		return "preset 4 levels the view"
	if preset.yaw_rate_cap_deg_per_s != NONE or preset.pitch_rate_cap_deg_per_s != NONE \
			or preset.pitch_limit_deg != NONE:
		return "preset 4 caps rotation"
	if not preset.has_no_intervention():
		return "preset 4 reports an intervention"
	return ""


func test_other_presets_report_an_intervention() -> String:
	for preset_name: String in ["anchored", "guided", "pilot"]:
		if load_preset(preset_name).has_no_intervention():
			return "%s reports no intervention" % preset_name
	return ""


func test_custom_preset_from_any_preset_changes_any_field() -> String:
	var replacement: Dictionary = {
		"display_name": "Custom", "yaw_mode": Yaw.SMOOTH, "snap_angle_deg": 45.0,
		"yaw_rate_cap_deg_per_s": 75.0, "pitch_mode": Pitch.SNAP,
		"pitch_rate_cap_deg_per_s": 20.0, "pitch_limit_deg": 30.0,
		"roll_mode": Roll.MANUAL, "auto_level": false, "vignette_strength": 0.6,
		"vignette_trigger": Trigger.FAST_ROTATION, "cockpit_frame": Frame.OPEN_CANOPY,
		"acceleration_softening": false, "inertia_drift": true, "hit_shake": 0.5,
		"hit_spin": true, "refresh_rate_hz": 72, "allow_120_hz": true,
	}
	for preset_name: String in expected:
		var original: ComfortPreset = load_preset(preset_name)
		var custom: ComfortPreset = original.duplicate() as ComfortPreset
		for field: String in field_names():
			if not replacement.has(field):
				return "the test has no replacement value for %s" % field
			custom.set(field, replacement[field])
			if custom.get(field) != replacement[field]:
				return "%s: custom %s did not take %s" % [preset_name, field, str(replacement[field])]
		for field: String in expected[preset_name]:
			if original.get(field) != expected[preset_name][field]:
				return "%s: changing the custom copy changed %s" % [preset_name, field]
	return ""


func test_presets_reference_nothing_in_core() -> String:
	var core_names: Array[String] = _core_class_names()
	if not core_names.has("Sim"):
		return "core classes were not read"
	var sources: Dictionary[String, String] = {PRESET_SCRIPT: FileAccess.get_file_as_string(PRESET_SCRIPT)}
	for preset_name: String in expected:
		sources[preset_path(preset_name)] = FileAccess.get_file_as_string(preset_path(preset_name))
	for path: String in sources:
		var text: String = sources[path]
		if text.is_empty():
			return "%s could not be read" % path
		if text.contains(CORE_DIR):
			return "%s refers to %s" % [path, CORE_DIR]
		for core_name: String in core_names:
			if RegEx.create_from_string("\\b%s\\b" % core_name).search(text) != null:
				return "%s refers to the core class %s" % [path, core_name]
	return ""


func test_preset_fields_hold_no_simulation_value() -> String:
	for field: String in field_names():
		for word: String in SIM_WORDS:
			if field.contains(word):
				return "ComfortPreset.%s looks like a simulation value (%s)" % [field, word]
	return ""


static func _core_class_names() -> Array[String]:
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open(CORE_DIR)
	if dir == null:
		return names
	var declares: RegEx = RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			var found: RegExMatch = declares.search(FileAccess.get_file_as_string(CORE_DIR.path_join(file)))
			if found != null:
				names.append(found.get_string(1))
	return names
