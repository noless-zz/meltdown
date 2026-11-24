extends RefCounted

## Fire entries drawn by `DebrisView` (#496, RUN-4, GFX-6, CMF-8, ARC-3): the
## snapshot names each entry's kind and keeps every other value; a fire sphere
## and a fire box are hidden, then warn like spheres, then burn see-through in
## their own shape; the flicker follows the snapshot's tick, so a paused session
## draws the same frame; without kinds every entry is drawn as before; bad fire
## look keys are named and the built-in look kept.

const EPSILON: float = 1e-4
const SCRATCH_DIR: String = "user://test_debris_view_fire"
## A solid 2 m sphere, a 1.5 m fire sphere and a 3 x 2 x 1 m fire box, all
## falling (or catching) 2 s after the reactor dies.
const MIXED: String = '[{"position": [0, 0, -20], "radius": 2, "after_seconds": 2},' \
	+ ' {"position": [0, 0, -30], "radius": 1.5, "after_seconds": 2, "kind": "fire",' \
	+ ' "damage_per_second": 5},' \
	+ ' {"position": [0, 0, -40], "size": [3, 2, 1], "after_seconds": 2, "kind": "fire",' \
	+ ' "damage_per_second": 5}]'
const FIRE_BOX: Vector3 = Vector3(3, 2, 1)


func _debris(text: String, elapsed_seconds: float) -> MeltdownDebris:
	var debris: MeltdownDebris = MeltdownDebris.parse_json(text)
	debris.elapsed_ticks = roundi(elapsed_seconds * MeltdownDebris.TICKS_PER_SECOND)
	return debris


func _show(view: DebrisView, snapshot: Dictionary, tick: int) -> void:
	view.show_debris(snapshot[SessionSnapshots.DEBRIS_POSITIONS], snapshot[SessionSnapshots.DEBRIS_RADII],
		snapshot[SessionSnapshots.DEBRIS_SOLID], snapshot[SessionSnapshots.DEBRIS_HELD],
		snapshot[SessionSnapshots.DEBRIS_SECONDS], snapshot[SessionSnapshots.DEBRIS_SIZES],
		snapshot[SessionSnapshots.DEBRIS_KINDS], tick)


func test_snapshot_names_each_kind() -> String:
	var debris: MeltdownDebris = _debris(MIXED, 2.5)
	if debris.error != "":
		return "fixture rejected: %s" % debris.error
	var snapshot: Dictionary = SessionSnapshots.debris(debris)
	var want: Array[String] = [MeltdownFire.KIND_SOLID, MeltdownFire.KIND_FIRE, MeltdownFire.KIND_FIRE]
	if snapshot[SessionSnapshots.DEBRIS_KINDS] != want:
		return "kinds %s, expected %s" % [snapshot[SessionSnapshots.DEBRIS_KINDS], want]
	# A fire never becomes solid; its seconds run to its fall like any entry's.
	if snapshot[SessionSnapshots.DEBRIS_SOLID] != ([true, false, false] as Array[bool]):
		return "solid %s" % [snapshot[SessionSnapshots.DEBRIS_SOLID]]
	if snapshot[SessionSnapshots.DEBRIS_SECONDS] != ([0.0, 0.0, 0.0] as Array[float]):
		return "seconds %s" % [snapshot[SessionSnapshots.DEBRIS_SECONDS]]
	var empty: Dictionary = SessionSnapshots.debris(null)
	if not (empty[SessionSnapshots.DEBRIS_KINDS] as Array).is_empty():
		return "no debris gave kinds %s" % [empty[SessionSnapshots.DEBRIS_KINDS]]
	return ""


func test_solid_and_fire_entries_at_each_stage() -> String:
	var view: DebrisView = DebrisView.new()
	var stages: Dictionary[float, Array] = {
		0.0: [DebrisView.EntryState.HIDDEN, DebrisView.EntryState.HIDDEN],
		1.75: [DebrisView.EntryState.WARNING, DebrisView.EntryState.WARNING],
		2.5: [DebrisView.EntryState.SOLID, DebrisView.EntryState.BURNING],
	}
	var result: String = ""
	for elapsed: float in stages:
		var debris: MeltdownDebris = _debris(MIXED, elapsed)
		_show(view, SessionSnapshots.debris(debris), debris.elapsed_ticks)
		result = _check_stage(view, stages[elapsed][0], stages[elapsed][1])
		if result != "":
			result = "%s s after the meltdown: %s" % [elapsed, result]
			break
	view.free()
	return result


func _check_stage(view: DebrisView, rock: DebrisView.EntryState, fire: DebrisView.EntryState) -> String:
	if view.entry_count() != 3 or view.get_child_count() != 3:
		return "%d entries and %d children, expected 3" % [view.entry_count(), view.get_child_count()]
	var wants: Array[DebrisView.EntryState] = [rock, fire, fire]
	for index: int in 3:
		var node: MeshInstance3D = view.entry(index)
		if view.entry_state(index) != wants[index]:
			return "entry %d is in state %d, expected %d" % [index, view.entry_state(index), wants[index]]
		if node.visible != (wants[index] != DebrisView.EntryState.HIDDEN):
			return "entry %d visible is %s" % [index, node.visible]
		# Particles may hang under an entry (#1331); a collision may not.
		if not node.find_children("*", "CollisionObject3D", true, false).is_empty() \
				or not node.find_children("*", "CollisionShape3D", true, false).is_empty():
			return "entry %d has a collision; fire must add none" % index
		if view.entry_is_fire(index) != (index > 0):
			return "entry %d fire is %s" % [index, view.entry_is_fire(index)]
	if absf(view.entry_radius(1) - 1.5) > EPSILON:
		return "the fire sphere is not 1.5 m across its radius"
	# Burning, a fire sphere is a flame (a cone), never a ball like the reactor (#1208).
	var flame: CylinderMesh = view.entry(1).mesh as CylinderMesh
	if fire == DebrisView.EntryState.BURNING and (flame == null or flame.top_radius != 0.0):
		return "a burning fire sphere is drawn as %s, not a flame" % view.entry(1).mesh
	if fire == DebrisView.EntryState.WARNING and not view.entry(1).mesh is SphereMesh:
		return "a fire sphere's warning is not the sphere warning"
	if not view.entry(2).mesh is BoxMesh or not view.entry_size(2).is_equal_approx(FIRE_BOX):
		return "the fire box is %s, expected a %s slab" % [view.entry_size(2), FIRE_BOX]
	if not view.entry(2).position.is_equal_approx(Vector3(0, 0, -40)):
		return "the fire box is at %s" % view.entry(2).position
	if fire == DebrisView.EntryState.WARNING:
		var warn: StandardMaterial3D = view.material_for(DebrisView.EntryState.WARNING)
		if view.entry(1).material_override != warn or view.entry(2).material_override != warn:
			return "a fire warning does not use the sphere warning look"
	if fire == DebrisView.EntryState.BURNING:
		var burning: StandardMaterial3D = view.fire_material_for(fire)
		if view.entry(1).material_override != burning or view.entry(2).material_override != burning:
			return "a burning fire does not use the fire look"
		if burning.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			return "fire is opaque; it must not read as a solid rock"
		if burning == view.material_for(DebrisView.EntryState.SOLID):
			return "fire shares the rock's material"
	return ""


func test_paused_snapshot_draws_the_same_frame() -> String:
	var view: DebrisView = DebrisView.new()
	var debris: MeltdownDebris = _debris(MIXED, 2.5)
	var snapshot: Dictionary = SessionSnapshots.debris(debris)
	var before: Dictionary = snapshot.duplicate(true)
	var tick: int = debris.elapsed_ticks
	_show(view, snapshot, tick)
	var fire: StandardMaterial3D = view.fire_material_for(DebrisView.EntryState.BURNING)
	var energy: float = fire.emission_energy_multiplier
	var transforms: Array[Transform3D] = []
	for index: int in view.entry_count():
		transforms.append(view.entry(index).transform)
	var builds: int = view.mesh_builds
	var result: String = ""
	for frame: int in 30:
		_show(view, snapshot, tick)
		if fire.emission_energy_multiplier != energy:
			result = "frame %d changed the fire glow from %s to %s" % [frame, energy, fire.emission_energy_multiplier]
			break
	for index: int in view.entry_count():
		if result == "" and view.entry(index).transform != transforms[index]:
			result = "the same snapshot moved entry %d" % index
	if result == "" and view.mesh_builds != builds:
		result = "showing the same snapshot built a mesh"
	elif result == "" and snapshot != before:
		result = "the view wrote to the snapshot it was given"
	elif result == "" and view.fire_material_for(DebrisView.EntryState.BURNING) != fire:
		result = "the fire material was replaced"
	if result == "":
		# A later tick moves the glow, so the flicker comes from the tick alone.
		_show(view, snapshot, tick + 7)
		if is_equal_approx(fire.emission_energy_multiplier, energy):
			result = "a new tick left the fire glow at %s" % energy
	view.free()
	return result


func test_flicker_stays_within_its_swing() -> String:
	var look: Dictionary = DebrisLook.FALLBACK
	var energy: float = float(look["fire_energy"])
	var swing: float = energy * float(look["fire_flicker"])
	var lowest: float = INF
	var highest: float = -INF
	for tick: int in 600:
		var value: float = DebrisLook.fire_energy_at(look, tick)
		if value != DebrisLook.fire_energy_at(look, tick):
			return "tick %d gave two glows" % tick
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	if lowest < energy - swing - EPSILON or highest > energy + swing + EPSILON:
		return "glow ran %s..%s, outside %s +- %s" % [lowest, highest, energy, swing]
	if highest - lowest < swing * 0.5:
		return "glow ran only %s..%s; it does not flicker" % [lowest, highest]
	var steady: Dictionary = look.duplicate()
	steady["fire_flicker"] = 0.0
	if not is_equal_approx(DebrisLook.fire_energy_at(steady, 123), energy):
		return "a zero flicker still moves the glow"
	return ""


func test_without_kinds_every_entry_is_drawn_as_before() -> String:
	var view: DebrisView = DebrisView.new()
	var snapshot: Dictionary = SessionSnapshots.debris(_debris(MIXED, 2.5))
	view.show_debris(snapshot[SessionSnapshots.DEBRIS_POSITIONS], snapshot[SessionSnapshots.DEBRIS_RADII],
		snapshot[SessionSnapshots.DEBRIS_SOLID], snapshot[SessionSnapshots.DEBRIS_HELD],
		snapshot[SessionSnapshots.DEBRIS_SECONDS], snapshot[SessionSnapshots.DEBRIS_SIZES])
	var result: String = ""
	var sizes: Array[Vector3] = snapshot[SessionSnapshots.DEBRIS_SIZES]
	for index: int in view.entry_count():
		var want: DebrisView.EntryState = view.state_for(snapshot[SessionSnapshots.DEBRIS_RADII][index],
			snapshot[SessionSnapshots.DEBRIS_SOLID][index], false, snapshot[SessionSnapshots.DEBRIS_SECONDS][index])
		var material: StandardMaterial3D = view.material_for(want)
		if sizes[index] != Vector3.ZERO:
			want = view.box_state_for(sizes[index], snapshot[SessionSnapshots.DEBRIS_SOLID][index], false,
				snapshot[SessionSnapshots.DEBRIS_SECONDS][index])
			material = view.slab_material_for(want)
		if view.entry_is_fire(index) or view.entry_state(index) != want:
			result = "entry %d is in state %d, expected %d as before fire" % [index, view.entry_state(index), want]
		elif view.entry(index).material_override != material:
			result = "entry %d has a different material than before fire" % index
		if result != "":
			break
	view.free()
	return result


func test_held_fire_is_not_drawn() -> String:
	var view: DebrisView = DebrisView.new()
	var debris: MeltdownDebris = _debris(MIXED, 3.0)
	debris.skipped = [false, true, true] as Array[bool]
	_show(view, SessionSnapshots.debris(debris), debris.elapsed_ticks)
	var result: String = ""
	for index: int in [1, 2]:
		if view.entry(index).visible or view.entry_state(index) != DebrisView.EntryState.HIDDEN:
			result = "held fire entry %d is drawn" % index
	view.free()
	return result


func test_fire_look_keys_are_applied_and_checked() -> String:
	var view: DebrisView = DebrisView.new()
	var look: Dictionary = view.look()
	var fire: StandardMaterial3D = view.fire_material_for(DebrisView.EntryState.BURNING)
	var result: String = ""
	if not (fire.emission as Color).is_equal_approx(look["fire_color"]) \
			or absf(fire.albedo_color.a - float(look["fire_alpha"])) > EPSILON:
		result = "the fire is not in fire_color at fire_alpha"
	elif view.fire_material_for(DebrisView.EntryState.HIDDEN) != null:
		result = "a hidden fire has a material"
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var cases: Dictionary[String, Variant] = {
		"fire_color": [1.0, 0.5],
		"fire_energy": 20.0,
		"fire_alpha": -0.1,
		"fire_flicker": 0.9,
	}
	for key: String in cases:
		if result != "":
			break
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DebrisLook.DEFAULT_FILE))
		data[key] = cases[key]
		data["fire_energy"] = 9.0 if key != "fire_energy" else data["fire_energy"]
		var path: String = "%s/%s.json" % [SCRATCH_DIR, key]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		var error: String = view.load_look(path)
		if not error.contains(key):
			result = "rejecting %s gave \"%s\"" % [key, error]
		elif absf(float(view.look()["fire_energy"]) - float(DebrisLook.FALLBACK["fire_energy"])) > EPSILON:
			result = "rejecting %s did not keep the built-in look" % key
	if result == "":
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DebrisLook.DEFAULT_FILE))
		data.erase("fire_flicker")
		if not str(DebrisLook.parse(JSON.stringify(data)).get("error", "")).contains("fire_flicker"):
			result = "a missing fire_flicker was not named"
	view.free()
	return result
