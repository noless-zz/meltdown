extends RefCounted

## Box-shaped meltdown entries drawn as slabs (#459, RUN-4, ARC-4, MP-2): the
## snapshot carries each entry's size and leaves sphere values as they were; a
## level with one sphere and one box shows a sphere and a slab of the right size
## at each stage; held boxes are not drawn; slabs have their own look keys, which
## are checked like the others; and the view keeps no clock of its own, so a
## paused session, which hands it the same snapshot, leaves it as it was.

const EPSILON: float = 1e-4
const SCRATCH_DIR: String = "user://test_debris_view_boxes"
## A 2 m sphere at (0, 0, -20) and a 6 x 6 x 0.5 m door at (0, 0, -40), both
## falling 2 s after the reactor dies.
const MIXED: String = '[{"position": [0, 0, -20], "radius": 2, "after_seconds": 2},' \
	+ ' {"position": [0, 0, -40], "size": [6, 6, 0.5], "after_seconds": 2}]'
const SPHERES: String = '[{"position": [1, 2, 3], "radius": 1.5, "after_seconds": 1},' \
	+ ' {"position": [0, 0, -10], "radius": 0.75, "after_seconds": 4}]'
const DOOR: Vector3 = Vector3(6, 6, 0.5)


func _debris(text: String, elapsed_seconds: float) -> MeltdownDebris:
	var debris: MeltdownDebris = MeltdownDebris.parse_json(text)
	debris.elapsed_ticks = roundi(elapsed_seconds * MeltdownDebris.TICKS_PER_SECOND)
	return debris


func _show(view: DebrisView, snapshot: Dictionary) -> void:
	view.show_debris(snapshot[SessionSnapshots.DEBRIS_POSITIONS], snapshot[SessionSnapshots.DEBRIS_RADII],
		snapshot[SessionSnapshots.DEBRIS_SOLID], snapshot[SessionSnapshots.DEBRIS_HELD],
		snapshot[SessionSnapshots.DEBRIS_SECONDS], snapshot[SessionSnapshots.DEBRIS_SIZES])


func test_snapshot_carries_sizes_and_keeps_sphere_values() -> String:
	var mixed: Dictionary = SessionSnapshots.debris(_debris(MIXED, 0.5))
	var sizes: Array[Vector3] = mixed[SessionSnapshots.DEBRIS_SIZES]
	if sizes.size() != 2 or sizes[0] != Vector3.ZERO or not sizes[1].is_equal_approx(DOOR):
		return "sizes %s, expected [zero, %s]" % [sizes, DOOR]
	var spheres: Dictionary = SessionSnapshots.debris(_debris(SPHERES, 2.0))
	var want: Dictionary = {
		SessionSnapshots.DEBRIS_POSITIONS: [Vector3(1, 2, 3), Vector3(0, 0, -10)] as Array[Vector3],
		SessionSnapshots.DEBRIS_RADII: [1.5, 0.75] as Array[float],
		SessionSnapshots.DEBRIS_SIZES: [Vector3.ZERO, Vector3.ZERO] as Array[Vector3],
		SessionSnapshots.DEBRIS_SOLID: [true, false] as Array[bool],
		SessionSnapshots.DEBRIS_HELD: [false, false] as Array[bool],
		SessionSnapshots.DEBRIS_SECONDS: [0.0, 2.0] as Array[float],
		SessionSnapshots.DEBRIS_KINDS: [MeltdownFire.KIND_SOLID, MeltdownFire.KIND_SOLID] as Array[String],
	}
	if spheres.keys().size() != want.keys().size():
		return "sphere-only snapshot has keys %s" % [spheres.keys()]
	for key: String in want:
		if spheres[key] != want[key]:
			return "sphere-only %s is %s, expected %s" % [key, spheres[key], want[key]]
	var empty: Dictionary = SessionSnapshots.debris(null)
	if not (empty[SessionSnapshots.DEBRIS_SIZES] as Array).is_empty():
		return "no debris gave sizes %s" % [empty[SessionSnapshots.DEBRIS_SIZES]]
	return ""


func test_sphere_and_box_show_two_shapes_at_each_stage() -> String:
	var view: DebrisView = DebrisView.new()
	# Seconds after the reactor's death around the 2 s fall: before the clock
	# starts, a quarter second before (inside any allowed `warn_seconds`), after.
	var stages: Dictionary[float, DebrisView.EntryState] = {
		0.0: DebrisView.EntryState.HIDDEN,
		1.75: DebrisView.EntryState.WARNING,
		2.5: DebrisView.EntryState.SOLID,
	}
	var result: String = ""
	for elapsed: float in stages:
		_show(view, SessionSnapshots.debris(_debris(MIXED, elapsed)))
		var want: DebrisView.EntryState = stages[elapsed]
		result = _check_pair(view, want)
		if result != "":
			result = "%s s after the meltdown: %s" % [elapsed, result]
			break
	view.free()
	return result


func _check_pair(view: DebrisView, want: DebrisView.EntryState) -> String:
	if view.entry_count() != 2 or view.get_child_count() != 2:
		return "%d entries and %d children, expected 2" % [view.entry_count(), view.get_child_count()]
	var sphere: MeshInstance3D = view.entry(0)
	var slab: MeshInstance3D = view.entry(1)
	if view.entry_state(0) != want or view.entry_state(1) != want:
		return "states %d and %d, expected %d" % [view.entry_state(0), view.entry_state(1), want]
	if sphere.visible != (want != DebrisView.EntryState.HIDDEN) or slab.visible != sphere.visible:
		return "visible %s and %s" % [sphere.visible, slab.visible]
	if not sphere.mesh is SphereMesh or view.entry_is_box(0):
		return "the sphere entry is not drawn as a sphere"
	if not slab.mesh is BoxMesh or not view.entry_is_box(1):
		return "the box entry is not drawn as a slab"
	if absf(view.entry_radius(0) - 2.0) > EPSILON:
		return "sphere radius %s, expected 2" % view.entry_radius(0)
	if not view.entry_size(1).is_equal_approx(DOOR):
		return "slab size %s, expected %s" % [view.entry_size(1), DOOR]
	if not slab.position.is_equal_approx(Vector3(0, 0, -40)) or slab.rotation != Vector3.ZERO:
		return "slab at %s turned %s; it must be axis-aligned at its entry" % [slab.position, slab.rotation]
	if want != DebrisView.EntryState.HIDDEN:
		if slab.material_override != view.slab_material_for(want):
			return "the slab has the wrong material"
		if slab.material_override == sphere.material_override:
			return "the slab shares the sphere's material"
	return ""


func test_held_boxes_are_not_drawn() -> String:
	var view: DebrisView = DebrisView.new()
	var debris: MeltdownDebris = _debris(MIXED, 3.0)
	debris.skipped = [true, true] as Array[bool]
	_show(view, SessionSnapshots.debris(debris))
	var result: String = ""
	if view.entry_count() != 2:
		result = "%d entries, expected 2" % view.entry_count()
	elif view.entry(1).visible or view.entry_state(1) != DebrisView.EntryState.HIDDEN:
		result = "a held box is drawn"
	elif not view.entry(0).visible or view.entry_state(0) != DebrisView.EntryState.HELD:
		result = "the held sphere lost its cracked-shell look"
	view.free()
	return result


func test_without_sizes_every_entry_stays_a_sphere() -> String:
	var view: DebrisView = DebrisView.new()
	var snapshot: Dictionary = SessionSnapshots.debris(_debris(SPHERES, 2.0))
	view.show_debris(snapshot[SessionSnapshots.DEBRIS_POSITIONS], snapshot[SessionSnapshots.DEBRIS_RADII],
		snapshot[SessionSnapshots.DEBRIS_SOLID], snapshot[SessionSnapshots.DEBRIS_HELD],
		snapshot[SessionSnapshots.DEBRIS_SECONDS])
	var result: String = ""
	for index: int in view.entry_count():
		if view.entry_is_box(index) or not view.entry(index).mesh is SphereMesh:
			result = "entry %d is not a sphere without a sizes array" % index
	view.free()
	return result


func test_same_snapshot_leaves_the_view_still_and_unwritten() -> String:
	var view: DebrisView = DebrisView.new()
	var snapshot: Dictionary = SessionSnapshots.debris(_debris(MIXED, 1.5))
	var before: Dictionary = snapshot.duplicate(true)
	_show(view, snapshot)
	var transforms: Array[Transform3D] = [view.entry(0).transform, view.entry(1).transform]
	var builds: int = view.mesh_builds
	var result: String = ""
	# A paused session hands over the same snapshot frame after frame.
	for frame: int in 30:
		_show(view, snapshot)
	if view.entry(0).transform != transforms[0] or view.entry(1).transform != transforms[1]:
		result = "the same snapshot moved an entry"
	elif view.mesh_builds != builds:
		result = "showing the same snapshot rebuilt a mesh"
	elif snapshot != before:
		result = "the view wrote to the snapshot it was given"
	for method: Dictionary in view.get_script().get_script_method_list():
		if str(method["name"]) in ["_process", "_physics_process"]:
			result = "DebrisView has %s; it must change only when shown a snapshot" % method["name"]
	view.free()
	return result


func test_slab_look_keys_are_applied_and_checked() -> String:
	var view: DebrisView = DebrisView.new()
	var result: String = ""
	var solid: StandardMaterial3D = view.slab_material_for(DebrisView.EntryState.SOLID)
	var warn: StandardMaterial3D = view.slab_material_for(DebrisView.EntryState.WARNING)
	var look: Dictionary = view.look()
	if solid.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		result = "a solid slab is see-through"
	elif warn.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		result = "a slab warning is opaque"
	elif not (solid.emission as Color).is_equal_approx(look["slab_color"]):
		result = "the solid slab is not in slab_color"
	elif not (warn.emission as Color).is_equal_approx(look["slab_warn_color"]) \
			or absf(warn.albedo_color.a - float(look["slab_warn_alpha"])) > EPSILON:
		result = "the slab warning is not in slab_warn_color at slab_warn_alpha"
	elif view.slab_material_for(DebrisView.EntryState.HELD) != null:
		result = "a held slab has a material"
	if result == "":
		result = _bad_slab_keys_are_named(view)
	view.free()
	return result


func _bad_slab_keys_are_named(view: DebrisView) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var cases: Dictionary[String, Variant] = {
		"slab_color": [0.5, 0.5],
		"slab_energy": 20.0,
		"slab_warn_color": [0.5, 2.0, 0.5],
		"slab_warn_energy": "bright",
		"slab_warn_alpha": -0.1,
	}
	for key: String in cases:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DebrisLook.DEFAULT_FILE))
		data[key] = cases[key]
		var path: String = "%s/%s.json" % [SCRATCH_DIR, key]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		var error: String = view.load_look(path)
		if not error.contains(key):
			return "rejecting %s gave \"%s\"" % [key, error]
		if not (view.look()["slab_color"] as Color).is_equal_approx(DebrisLook.FALLBACK["slab_color"]):
			return "rejecting %s did not keep the built-in slab look" % key
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DebrisLook.DEFAULT_FILE))
	shipped.erase("slab_warn_alpha")
	if not str(DebrisLook.parse(JSON.stringify(shipped)).get("error", "")).contains("slab_warn_alpha"):
		return "a missing slab key was not named"
	return ""
