extends RefCounted

## The reactor drawn as a glowing sphere with one light (RUN-2, LGT-1, GFX-4,
## ARC-4): node tree and radius, a pulse that speeds up with lost hull and
## with the meltdown countdown, a wreck look once destroyed, a look file that
## falls back when rejected, no reference to layers above core, and no mesh
## rebuild when the same state is shown every frame.

const SCRIPT_PATHS: Array[String] = ["res://view/reactor_view.gd", "res://view/reactor_look.gd",
	"res://view/reactor_machine.gd", "res://view/reactor_machine_look.gd", "res://view/reactor_flames.gd"]
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
const SCRATCH_DIR: String = "user://test_reactor_view"
const EPSILON: float = 1e-4


func _valid_look() -> Dictionary:
	var data: Dictionary = {}
	for key: String in ReactorLook.FALLBACK:
		var value: Variant = ReactorLook.FALLBACK[key]
		if value is Color:
			var color: Color = value
			data[key] = [color.r, color.g, color.b]
		else:
			data[key] = value
	return data


func test_one_mesh_and_one_light_of_the_reactor_radius() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3(0, -39, -114), 2.5, 1.0, false, 90.0)
	var meshes: int = 0
	var lights: int = 0
	for child: Node in view.get_children():
		if child is MeshInstance3D:
			meshes += 1
		elif child is Light3D:
			lights += 1
			if not child is OmniLight3D:
				lights += 100
	var result: String = ""
	if meshes != 1 or lights != 1:
		result = "expected one mesh and one omni light, got %d meshes and %d lights" % [meshes, lights]
	elif not view.core().mesh is SphereMesh:
		result = "the core is not a sphere"
	elif absf(view.core_radius() - 2.5 * view.core_scale()) > EPSILON:
		result = "core radius %s, expected %s" % [view.core_radius(), 2.5 * view.core_scale()]
	elif absf(view.radius() - 2.5) > EPSILON:
		result = "reactor radius %s, expected 2.5" % view.radius()
	elif not view.position.is_equal_approx(Vector3(0, -39, -114)):
		result = "placed at %s" % view.position
	elif view.light().shadow_enabled:
		result = "the reactor light casts shadows; only the headlight may (GFX-4)"
	elif not view.visible:
		result = "a reactor with a radius is hidden"
	view.free()
	return result


func test_zero_radius_hides_the_reactor() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 0.0, 1.0, false, 0.0)
	var result: String = "" if not view.visible else "a zero-radius reactor is shown"
	view.free()
	return result


func test_lower_hull_pulses_faster() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 1.0, false, 90.0)
	var full: float = view.pulse_period()
	view.show_state(Vector3.ZERO, 2.5, 0.5, false, 90.0)
	var half: float = view.pulse_period()
	view.show_state(Vector3.ZERO, 2.5, 0.0, false, 90.0)
	var none: float = view.pulse_period()
	view.free()
	if not (none < half and half < full):
		return "periods at hull 1, 0.5, 0: %s, %s, %s; expected shorter at lower hull" % [full, half, none]
	return ""


func test_less_time_left_flickers_faster_and_fastest_under_30_s() -> String:
	var view: ReactorView = ReactorView.new()
	var periods: Array[float] = []
	for seconds: float in [90.0, 60.0, 40.0, 30.0, 10.0, 0.0]:
		view.show_state(Vector3.ZERO, 2.5, 0.0, true, seconds)
		periods.append(view.pulse_period())
	var fast: float = float(view.look()["flicker_period_fast"])
	view.free()
	if not (periods[0] > periods[1] and periods[1] > periods[2] and periods[2] > periods[3]):
		return "flicker periods at 90, 60, 40, 30 s: %s; expected shorter as time runs down" % [periods]
	for index: int in range(3, periods.size()):
		if absf(periods[index] - fast) > EPSILON:
			return "flicker period %s at or under 30 s, expected the fastest %s" % [periods[index], fast]
	return ""


func test_pulse_changes_brightness_over_time() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 1.0, false, 90.0)
	var start: float = view.light().light_energy
	view.advance(view.pulse_period() * 0.5)
	var trough: float = view.light().light_energy
	view.advance(view.pulse_period() * 0.5)
	var back: float = view.light().light_energy
	view.free()
	if trough >= start - EPSILON:
		return "light energy %s at half a pulse, not below %s at its start" % [trough, start]
	if absf(back - start) > 1e-3:
		return "light energy %s after a full pulse, expected %s" % [back, start]
	return ""


func test_destroyed_look_differs_from_intact() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 0.2, false, 90.0)
	var intact_emission: Color = view.material().emission
	var intact_energy: float = view.material().emission_energy_multiplier
	var intact_light: Color = view.light().light_color
	view.show_state(Vector3.ZERO, 2.5, 0.0, true, 90.0)
	var result: String = ""
	if view.material().emission.is_equal_approx(intact_emission):
		result = "the destroyed core keeps the intact colour"
	elif view.light().light_color.is_equal_approx(intact_light):
		result = "the meltdown light keeps the intact colour"
	elif view.material().emission_energy_multiplier >= intact_energy:
		result = "the destroyed core is not dimmer (%s vs %s)" % [view.material().emission_energy_multiplier, intact_energy]
	view.free()
	return result


func test_same_state_every_frame_does_not_rebuild_the_mesh() -> String:
	var view: ReactorView = ReactorView.new()
	var mesh: Mesh = view.core().mesh
	var material: Material = view.material()
	var builds: int = view.mesh_builds
	for frame: int in 120:
		view.show_state(Vector3(1, 2, 3), 2.5, 0.7, false, 90.0)
		view.advance(1.0 / 72.0)
	view.show_state(Vector3(1, 2, 3), 3.0, 0.0, true, 20.0)
	var result: String = ""
	if view.mesh_builds != builds:
		result = "the mesh was built %d more times" % (view.mesh_builds - builds)
	elif view.core().mesh != mesh or (view.core().mesh as SphereMesh).material != material:
		result = "the mesh or material was replaced"
	elif view.get_child_count() != 3:
		result = "%d children after 120 frames, expected the core, the light and the machine" % view.get_child_count()
	view.free()
	return result


func test_shipped_look_file_is_accepted() -> String:
	var view: ReactorView = ReactorView.new()
	var result: String = view.look_error
	view.free()
	return result


func test_rejected_look_file_keeps_the_built_in_look_and_names_the_field() -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var cases: Dictionary[String, Variant] = {
		"light_range": 100.0,
		"core_color": [1.0, 0.5],
		"pulse_depth": true,
		"flicker_period_fast": 0.1,
	}
	var view: ReactorView = ReactorView.new()
	var result: String = ""
	for field: String in cases:
		var data: Dictionary = _valid_look()
		data[field] = cases[field]
		data["light_energy"] = 9.0
		var path: String = "%s/%s.json" % [SCRATCH_DIR, field]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		var error: String = view.load_look(path)
		if not error.contains(field):
			result = "rejecting %s gave \"%s\"" % [field, error]
		elif absf(float(view.look()["light_energy"]) - float(ReactorLook.FALLBACK["light_energy"])) > EPSILON:
			result = "rejecting %s did not keep the built-in look" % field
		if result != "":
			break
	if result == "":
		var data: Dictionary = _valid_look()
		data["pulse_period_no_hull"] = 5.0
		var ordered: Dictionary = ReactorLook.parse(JSON.stringify(data))
		if not str(ordered.get("error", "")).contains("pulse_period_no_hull"):
			result = "a no-hull pulse slower than the full-hull one was accepted"
	if result == "":
		var data: Dictionary = _valid_look()
		data["extra"] = 1
		if not str(ReactorLook.parse(JSON.stringify(data)).get("error", "")).contains("extra"):
			result = "an unknown key was accepted"
	if result == "" and view.load_look("%s/missing.json" % SCRATCH_DIR) == "":
		result = "a missing file was not reported"
	if result == "":
		var good: Dictionary = _valid_look()
		good["light_energy"] = 9.0
		var good_path: String = "%s/good.json" % SCRATCH_DIR
		var good_file: FileAccess = FileAccess.open(good_path, FileAccess.WRITE)
		good_file.store_string(JSON.stringify(good))
		good_file.close()
		if view.load_look(good_path) != "" or absf(float(view.look()["light_energy"]) - 9.0) > EPSILON:
			result = "a valid look file was not applied"
	view.free()
	return result


func test_fallback_matches_the_shipped_file() -> String:
	var parsed: Dictionary = ReactorLook.parse(FileAccess.get_file_as_string(ReactorLook.DEFAULT_FILE))
	if parsed.has("error"):
		return parsed["error"]
	for key: String in ReactorLook.FALLBACK:
		var want: Variant = ReactorLook.FALLBACK[key]
		var got: Variant = parsed[key]
		if want is Color:
			if not (got as Color).is_equal_approx(want):
				return "%s: file %s, built-in %s" % [key, got, want]
		elif absf(float(got) - float(want)) > EPSILON:
			return "%s: file %s, built-in %s" % [key, got, want]
	return ""


func test_reads_no_layer_above_core() -> String:
	for script_path: String in SCRIPT_PATHS:
		var source: String = FileAccess.get_file_as_string(script_path)
		for root: String in OUTSIDE_DIRS:
			for file: String in DirAccess.get_files_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray():
				if not file.ends_with(".gd"):
					continue
				var head: String = FileAccess.get_file_as_string("%s/%s" % [root, file]).get_slice("\n", 0)
				if head.begins_with("class_name "):
					var class_id: String = head.trim_prefix("class_name ").strip_edges()
					var found: RegEx = RegEx.create_from_string("\\b%s\\b" % class_id)
					if found.search(source) != null:
						return "%s references %s from %s" % [script_path, class_id, root]
	return ""


func test_frozen_defaults_to_false() -> String:
	var view: ReactorView = ReactorView.new()
	var result: String = "" if not view.frozen else "a new reactor view starts frozen"
	view.free()
	return result


func test_frozen_view_holds_its_pulse_and_resumes_from_it() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 0.0, true, 60.0)
	view._process(view.pulse_period() * 0.3)
	var held: float = view.pulse_level()
	var held_light: float = view.light().light_energy
	var held_emission: float = view.material().emission_energy_multiplier
	view.frozen = true
	for frame: int in 144:
		view._process(1.0 / 72.0)
	var result: String = ""
	if absf(view.pulse_level() - held) > EPSILON:
		result = "pulse level %s after 2 s frozen, expected %s" % [view.pulse_level(), held]
	elif absf(view.light().light_energy - held_light) > EPSILON:
		result = "light energy %s after 2 s frozen, expected %s" % [view.light().light_energy, held_light]
	elif absf(view.material().emission_energy_multiplier - held_emission) > EPSILON:
		result = "core emission %s after 2 s frozen, expected %s" % [view.material().emission_energy_multiplier, held_emission]
	if result == "":
		view.frozen = false
		var step: float = view.pulse_period() * 0.05
		var phase: float = view.pulse_phase
		view._process(step)
		var expected: float = fposmod(phase + step / view.pulse_period(), 1.0)
		if absf(view.pulse_level() - held) <= EPSILON:
			result = "the pulse did not move after unfreezing"
		elif absf(view.pulse_phase - expected) > EPSILON:
			result = "unfrozen phase %s, expected %s: it jumped instead of resuming" % [view.pulse_phase, expected]
	view.free()
	return result
