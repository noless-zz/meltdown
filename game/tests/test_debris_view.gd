extends RefCounted

## Meltdown debris drawn from plain values (RUN-4, LGT-1, ARC-4, MP-2): solid,
## warning and held entries get their own node, radius, place and material; a
## warning shows only within `warn_seconds`; fewer entries free the extra
## nodes; a rejected look file names its key and keeps the built-in look; the
## view references no simulation, session or layer above core.

const SCRIPT_PATHS: Array[String] = [
	"res://view/debris_view.gd", "res://view/debris_look.gd",
	"res://view/debris_meshes.gd", "res://view/debris_materials.gd",
]
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
## Simulation classes the view must never be handed (MP-2).
const SIM_CLASSES: Array[String] = ["Sim", "MeltdownDebris", "ReactorState", "ShipState"]
const SCRATCH_DIR: String = "user://test_debris_view"
const EPSILON: float = 1e-4


func _valid_look() -> Dictionary:
	var data: Dictionary = {}
	for key: String in DebrisLook.FALLBACK:
		var value: Variant = DebrisLook.FALLBACK[key]
		if value is Color:
			var color: Color = value
			data[key] = [color.r, color.g, color.b]
		else:
			data[key] = value
	return data


## Solid at (1, 2, 3) r 1.5; warning at (0, 0, -10) r 2 falling in 1 s;
## held at (-4, 0, 0) r 0.75.
func _three(view: DebrisView) -> void:
	view.show_debris(
		[Vector3(1, 2, 3), Vector3(0, 0, -10), Vector3(-4, 0, 0)] as Array[Vector3],
		[1.5, 2.0, 0.75] as Array[float],
		[true, false, false] as Array[bool],
		[false, false, true] as Array[bool],
		[0.0, 1.0, 0.0] as Array[float])


func test_three_states_give_three_nodes_with_radius_place_and_material() -> String:
	var view: DebrisView = DebrisView.new()
	_three(view)
	var want_states: Array[DebrisView.EntryState] = [DebrisView.EntryState.SOLID, DebrisView.EntryState.WARNING, DebrisView.EntryState.HELD]
	var want_positions: Array[Vector3] = [Vector3(1, 2, 3), Vector3(0, 0, -10), Vector3(-4, 0, 0)]
	var want_radii: Array[float] = [1.5, 2.0, 0.75]
	var result: String = ""
	if view.entry_count() != 3 or view.get_child_count() != 3:
		result = "%d entries and %d children, expected 3" % [view.entry_count(), view.get_child_count()]
	for index: int in 3 if result == "" else 0:
		var node: MeshInstance3D = view.entry(index)
		if view.entry_state(index) != want_states[index]:
			result = "entry %d state %d, expected %d" % [index, view.entry_state(index), want_states[index]]
		elif not node.visible:
			result = "entry %d is hidden" % index
		elif not node.position.is_equal_approx(want_positions[index]):
			result = "entry %d at %s" % [index, node.position]
		elif absf(view.entry_radius(index) - want_radii[index]) > EPSILON:
			result = "entry %d radius %s, expected %s" % [index, view.entry_radius(index), want_radii[index]]
		elif node.material_override != view.material_for(want_states[index]):
			result = "entry %d has the wrong material" % index
		if result != "":
			break
	if result == "":
		var solid: StandardMaterial3D = view.material_for(DebrisView.EntryState.SOLID)
		var warn: StandardMaterial3D = view.material_for(DebrisView.EntryState.WARNING)
		var held: StandardMaterial3D = view.material_for(DebrisView.EntryState.HELD)
		if solid == warn or solid == held or warn == held:
			result = "two states share a material"
		elif solid.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			result = "solid debris is see-through"
		elif held.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			result = "held debris is opaque and would read as a sealed tunnel"
		elif not held.albedo_color.is_equal_approx(_with_alpha(view.look()["held_color"], float(view.look()["held_alpha"]))):
			result = "held debris is not in held_color"
		elif view.entry(2).mesh == view.entry(0).mesh:
			result = "held debris uses the whole-rock mesh, not the cracked one"
	view.free()
	return result


func test_warning_shows_only_within_warn_seconds() -> String:
	var view: DebrisView = DebrisView.new()
	var warn: float = float(view.look()["warn_seconds"])
	var cases: Dictionary[float, bool] = {warn + 0.5: false, warn + 0.01: false, warn: true, warn * 0.5: true, 0.0: true}
	var result: String = ""
	for seconds: float in cases:
		view.show_debris([Vector3.ZERO] as Array[Vector3], [1.0] as Array[float], [false] as Array[bool], [false] as Array[bool], [seconds] as Array[float])
		var shown: bool = view.entry(0).visible and view.entry_state(0) == DebrisView.EntryState.WARNING
		if shown != cases[seconds]:
			result = "%s s before falling (warn_seconds %s): shown %s" % [seconds, warn, shown]
			break
	view.free()
	return result


func test_fewer_entries_remove_the_extra_nodes() -> String:
	var view: DebrisView = DebrisView.new()
	_three(view)
	var builds: int = view.mesh_builds
	view.show_debris([Vector3(5, 0, 0)] as Array[Vector3], [1.0] as Array[float], [true] as Array[bool], [false] as Array[bool], [0.0] as Array[float])
	var result: String = ""
	if view.entry_count() != 1 or view.get_child_count() != 1:
		result = "%d entries and %d children after one entry, expected 1" % [view.entry_count(), view.get_child_count()]
	elif not view.entry(0).position.is_equal_approx(Vector3(5, 0, 0)):
		result = "the remaining node is at %s" % view.entry(0).position
	elif view.mesh_builds != builds:
		result = "showing debris again rebuilt a mesh"
	if result == "":
		view.show_debris([] as Array[Vector3], [] as Array[float], [] as Array[bool], [] as Array[bool], [] as Array[float])
		if view.get_child_count() != 0:
			result = "%d children after no entries" % view.get_child_count()
	view.free()
	return result


func test_zero_radius_entry_is_hidden() -> String:
	var view: DebrisView = DebrisView.new()
	view.show_debris([Vector3.ZERO] as Array[Vector3], [0.0] as Array[float], [true] as Array[bool], [false] as Array[bool], [0.0] as Array[float])
	var result: String = "" if not view.entry(0).visible else "a zero-radius rock is shown"
	view.free()
	return result


func test_shipped_look_file_is_accepted_and_matches_the_fallback() -> String:
	var view: DebrisView = DebrisView.new()
	var result: String = view.look_error
	view.free()
	if result != "":
		return result
	var parsed: Dictionary = DebrisLook.parse(FileAccess.get_file_as_string(DebrisLook.DEFAULT_FILE))
	for key: String in DebrisLook.FALLBACK:
		var want: Variant = DebrisLook.FALLBACK[key]
		var got: Variant = parsed[key]
		if want is Color:
			if not (got as Color).is_equal_approx(want):
				return "%s: file %s, built-in %s" % [key, got, want]
		elif absf(float(got) - float(want)) > EPSILON:
			return "%s: file %s, built-in %s" % [key, got, want]
	return ""


func test_bad_look_file_is_rejected_naming_the_key() -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var cases: Dictionary[String, Variant] = {
		"warn_seconds": 0.1,
		"held_color": [1.0, 0.5],
		"solid_energy": true,
		"warn_alpha": 2.0,
	}
	var view: DebrisView = DebrisView.new()
	var result: String = ""
	for key: String in cases:
		var data: Dictionary = _valid_look()
		data[key] = cases[key]
		data["warn_energy"] = 9.0
		var path: String = "%s/%s.json" % [SCRATCH_DIR, key]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		var error: String = view.load_look(path)
		if not error.contains(key):
			result = "rejecting %s gave \"%s\"" % [key, error]
		elif absf(float(view.look()["warn_energy"]) - float(DebrisLook.FALLBACK["warn_energy"])) > EPSILON:
			result = "rejecting %s did not keep the built-in look" % key
		if result != "":
			break
	if result == "":
		var data: Dictionary = _valid_look()
		data.erase("held_color")
		if not str(DebrisLook.parse(JSON.stringify(data)).get("error", "")).contains("held_color"):
			result = "a missing key was not named"
	if result == "":
		var data: Dictionary = _valid_look()
		data["extra"] = 1
		if not str(DebrisLook.parse(JSON.stringify(data)).get("error", "")).contains("extra"):
			result = "an unknown key was accepted"
	if result == "" and view.load_look("%s/missing.json" % SCRATCH_DIR) == "":
		result = "a missing file was not reported"
	if result == "":
		# The view keeps drawing with the built-in look after a rejection.
		_three(view)
		if view.entry_count() != 3 or view.entry(1).material_override != view.material_for(DebrisView.EntryState.WARNING):
			result = "the view stopped drawing after a rejected look file"
	if result == "":
		var good: Dictionary = _valid_look()
		good["warn_seconds"] = 6.0
		var good_path: String = "%s/good.json" % SCRATCH_DIR
		var good_file: FileAccess = FileAccess.open(good_path, FileAccess.WRITE)
		good_file.store_string(JSON.stringify(good))
		good_file.close()
		if view.load_look(good_path) != "" or absf(float(view.look()["warn_seconds"]) - 6.0) > EPSILON:
			result = "a valid look file was not applied"
	view.free()
	return result


func test_reads_no_simulation_or_layer_above_core() -> String:
	for script_path: String in SCRIPT_PATHS:
		var source: String = FileAccess.get_file_as_string(script_path)
		for class_id: String in SIM_CLASSES:
			# Mentions in comments are allowed; code must not use the class.
			var code: String = _without_comments(source)
			if RegEx.create_from_string("\\b%s\\b" % class_id).search(code) != null:
				return "%s uses %s; it must take plain values (MP-2)" % [script_path, class_id]
		for root: String in OUTSIDE_DIRS:
			for file: String in DirAccess.get_files_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray():
				if not file.ends_with(".gd"):
					continue
				var head: String = FileAccess.get_file_as_string("%s/%s" % [root, file]).get_slice("\n", 0)
				if head.begins_with("class_name "):
					var class_id: String = head.trim_prefix("class_name ").strip_edges()
					if RegEx.create_from_string("\\b%s\\b" % class_id).search(source) != null:
						return "%s references %s from %s" % [script_path, class_id, root]
	return ""


func _without_comments(source: String) -> String:
	var lines: PackedStringArray = []
	for line: String in source.split("\n"):
		lines.append(line.get_slice("#", 0))
	return "\n".join(lines)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
