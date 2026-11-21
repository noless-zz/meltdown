extends RefCounted

## The visible gripped stick and throttle (#740, PLT-5, ARC-3, ARC-4): shows
## the pose the mapping reads, clamped to full deflection, centres and dims on
## release, takes its look from the data file and knows nothing of `core/`.

const EPSILON: float = 0.0001


func _top(model: GrippedControlsModel) -> Vector3:
	return model.shown_pose().basis * Vector3.UP


func test_a_centred_pose_leaves_the_stick_upright() -> String:
	var model: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.STICK)
	model.show_pose(Transform3D.IDENTITY)
	var result: String = ""
	if not _top(model).is_equal_approx(Vector3.UP):
		result = "a centred pose tilts the stick to %s" % _top(model)
	elif not model.shown_pose().basis.is_equal_approx(Basis.IDENTITY):
		result = "a centred pose twists the stick"
	elif model.dimmed():
		result = "a held stick is dimmed"
	model.free()
	return result


func test_a_pose_within_full_deflection_is_shown_as_it_is() -> String:
	var pose: Basis = Basis(Vector3.RIGHT, deg_to_rad(-12.0)) * Basis(Vector3.UP, deg_to_rad(-8.0))
	var model: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.STICK)
	model.show_pose(Transform3D(pose, Vector3(0.05, 0.0, 0.0)))
	var shown: Vector3 = GrippedStickMapping.stick_angles(model.shown_pose().basis)
	var wanted: Vector3 = GrippedStickMapping.stick_angles(pose)
	model.free()
	if not shown.is_equal_approx(wanted):
		return "a pose within range shows angles %s, the mapping reads %s" % [shown, wanted]
	return ""


func test_a_stick_pose_past_full_deflection_is_clamped_to_it() -> String:
	var full: float = GrippedStickMapping.STICK_TILT_FULL_RAD
	var twist_full: float = GrippedStickMapping.STICK_TWIST_FULL_RAD
	# Tilt the top 60 degrees ahead and 50 to the right, twist 70 clockwise.
	var pose: Basis = Basis(Vector3.BACK, deg_to_rad(-50.0)) * Basis(Vector3.RIGHT, deg_to_rad(-60.0)) \
			* Basis(Vector3.UP, deg_to_rad(-70.0))
	var raw: Vector3 = GrippedStickMapping.stick_angles(pose)
	if absf(raw.x) <= full or absf(raw.z) <= full or absf(raw.y) <= twist_full:
		return "test pose %s is not past full deflection" % raw
	var model: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.STICK)
	model.show_pose(Transform3D(pose, Vector3.ZERO))
	var shown: Vector3 = GrippedStickMapping.stick_angles(model.shown_pose().basis)
	model.free()
	var wanted: Vector3 = Vector3(signf(raw.x) * full, signf(raw.y) * twist_full, signf(raw.z) * full)
	if not shown.is_equal_approx(wanted):
		return "a pose past full deflection shows %s, expected %s" % [shown, wanted]
	# What is shown still gives full deflection through the mapping.
	var mapping: GrippedStickMapping = GrippedStickMapping.new()
	var axes: Dictionary = mapping.axes(Transform3D.IDENTITY, Transform3D(GrippedControlsModel.clamped_stick_basis(pose), Vector3.ZERO), 0.0, 1.0)
	for axis: String in ["pitch", "roll", "yaw"]:
		if absf(absf(float(axes[axis])) - 1.0) > 0.001:
			return "the shown stick gives %s %s, expected full" % [axis, axes[axis]]
	return ""


func test_a_throttle_pose_past_full_travel_is_clamped_to_it() -> String:
	var full: float = GrippedStickMapping.THROTTLE_FULL_M
	var model: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.THROTTLE)
	model.show_pose(Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.3, -0.04, -0.25)))
	var shown: Transform3D = model.shown_pose()
	model.free()
	if not shown.origin.is_equal_approx(Vector3(full, -0.04, -full)):
		return "the throttle shows %s, expected %s" % [shown.origin, Vector3(full, -0.04, -full)]
	if not shown.basis.is_equal_approx(Basis.IDENTITY):
		return "the throttle handle turned with the hand, which the mapping ignores"
	return ""


func test_release_centres_and_dims() -> String:
	for kind: String in GrippedControlsModel.KINDS:
		var model: GrippedControlsModel = GrippedControlsModel.new(kind)
		var look: Dictionary = model.look()
		var result: String = ""
		if not model.dimmed() or not is_equal_approx(model.alpha(), float(look["dimmed_alpha"])):
			result = "a new %s is not dimmed" % kind
		model.show_pose(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.05, 0.05, -0.05)))
		if result == "" and (model.dimmed() or not is_equal_approx(model.alpha(), float(look["alpha"]))):
			result = "a held %s is not at full alpha" % kind
		model.release()
		if result == "" and not model.shown_pose().is_equal_approx(Transform3D.IDENTITY):
			result = "a released %s shows %s, not the centre" % [kind, model.shown_pose()]
		if result == "" and (not model.dimmed() or not is_equal_approx(model.alpha(), float(look["dimmed_alpha"]))):
			result = "a released %s is not dimmed" % kind
		model.free()
		if result != "":
			return result
	return ""


func test_values_come_from_the_data_file() -> String:
	var shipped: Dictionary = GrippedControlsLook.load_file()
	if shipped["error"] != "":
		return "shipped look rejected: %s" % shipped["error"]
	var path: String = "user://gripped_controls_look_test.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GrippedControlsLook.DEFAULT_FILE))
	data["color"] = [0.1, 0.2, 0.3]
	data["alpha"] = 0.9
	data["dimmed_alpha"] = 0.1
	data["stick_length_m"] = 0.2
	data["knob_radius_m"] = 0.03
	data["throttle_handle_m"] = 0.05
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var stick: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.STICK, path)
	var throttle: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.THROTTLE, path)
	var result: String = ""
	var knob: MeshInstance3D = stick.get_node("Moving/Knob")
	var shaft: MeshInstance3D = stick.get_node("Moving/Shaft")
	var handle: MeshInstance3D = throttle.get_node("Moving/Handle")
	if stick.look_error != "":
		result = "test look rejected: %s" % stick.look_error
	elif not is_equal_approx((shaft.mesh as CylinderMesh).height, 0.2) or not knob.position.is_equal_approx(Vector3(0.0, 0.2, 0.0)):
		result = "stick length not from the file"
	elif not is_equal_approx((knob.mesh as SphereMesh).radius, 0.03):
		result = "knob radius not from the file"
	elif not (handle.mesh as BoxMesh).size.is_equal_approx(Vector3.ONE * 0.05):
		result = "throttle handle size not from the file"
	elif not is_equal_approx(stick.alpha(), 0.1):
		result = "dimmed alpha is %s, file says 0.1" % stick.alpha()
	stick.show_pose(Transform3D.IDENTITY)
	var material: StandardMaterial3D = (knob.mesh as SphereMesh).material
	if result == "" and not material.albedo_color.is_equal_approx(Color(0.1, 0.2, 0.3, 0.9)):
		result = "colour is %s, file says 0.1, 0.2, 0.3 at 0.9" % material.albedo_color
	if result == "" and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		result = "the model is lit; it must read in a dark mine"
	stick.free()
	throttle.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result


func test_a_bad_look_is_rejected_naming_the_field() -> String:
	var cases: Array[Array] = [
		[{"dimmed_alpha": 0.7}, "dimmed_alpha"],
		[{"stick_length_m": 2.0}, "stick_length_m"],
		[{"color": [1, 2]}, "color"],
		[{"alpha": true}, "alpha"],
		[{"size": 1}, "size"],
	]
	for item: Array in cases:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GrippedControlsLook.DEFAULT_FILE))
		data.merge(item[0], true)
		var parsed: Dictionary = GrippedControlsLook.parse(JSON.stringify(data))
		if not str(parsed.get("error", "")).contains(item[1]):
			return "a bad %s gave %s" % [item[1], parsed]
	var missing: GrippedControlsModel = GrippedControlsModel.new(GrippedControlsModel.STICK, "user://no_such_look.json")
	var error: String = missing.look_error
	missing.free()
	if error == "":
		return "a missing look file was not reported"
	return ""


func test_the_class_mentions_nothing_from_core() -> String:
	var core_names: Array[String] = []
	for file_name: String in DirAccess.get_files_at("res://core"):
		if not file_name.ends_with(".gd"):
			continue
		var source: String = FileAccess.get_file_as_string("res://core/" + file_name)
		var found: RegExMatch = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(source)
		if found != null:
			core_names.append(found.get_string(1))
	if core_names.is_empty():
		return "found no core classes to check against"
	for path: String in ["res://xr/gripped_controls_model.gd", "res://xr/gripped_controls_look.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		if source.contains("res://core/"):
			return "%s loads from core/" % path
		for core_name: String in core_names:
			if RegEx.create_from_string("\\b%s\\b" % core_name).search(source) != null:
				return "%s mentions %s from core/" % [path, core_name]
	return ""
