extends RefCounted

## The gripped stick and throttle models shown in the hands (#789, PLT-5,
## CMF-1, ARC-3, MP-2): shown only in the gripped scheme, the grab-relative
## pose passed through each frame, a release dims and rests the model beside
## the hand, the rest points from `controller_anchors.json`, the menu's scheme
## switch shows or hides them at once, left-handed mode swaps the hands, and
## the session's state hash is the same with the models as without.

const FRAME: float = 1.0 / 72.0

var NONE: PackedStringArray = PackedStringArray()


## A scheme switch with its models hung under a fresh rig node.
static func _switch(scheme: String) -> ControlSchemeSwitch:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(PackedStringArray(), scheme)
	chosen.attach_models(Node3D.new())
	return chosen


static func _done(chosen: ControlSchemeSwitch) -> void:
	chosen.models.stick.get_parent().get_parent().free()


## Values with both hands at `left` / `right` and the grips as given.
static func _values(left: Transform3D, right: Transform3D, left_grip: float, right_grip: float) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_grip"] = left_grip
	values["right_grip"] = right_grip
	values[ControllerSampler.POSES] = {"left": left, "right": right}
	return values


static func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.0001


func test_shown_only_in_the_gripped_scheme() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var values: Dictionary = _values(Transform3D.IDENTITY, Transform3D.IDENTITY, 0.0, 0.0)
	var thumbs: ControlSchemeSwitch = _switch(ControlSchemeSwitch.THUMBSTICKS)
	thumbs.map_values(mapping, values)
	var thumbs_shown: bool = thumbs.models.is_shown()
	_done(thumbs)
	var gripped: ControlSchemeSwitch = _switch(ControlSchemeSwitch.GRIPPED)
	gripped.map_values(mapping, values)
	var gripped_shown: bool = gripped.models.is_shown() and gripped.models.stick.visible \
		and gripped.models.throttle.visible
	_done(gripped)
	if thumbs_shown or not gripped_shown:
		return "shown with thumbsticks: %s, with gripped: %s" % [thumbs_shown, gripped_shown]
	return ""


func test_the_grab_relative_pose_is_passed_through_each_frame() -> String:
	var chosen: ControlSchemeSwitch = _switch(ControlSchemeSwitch.GRIPPED)
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var right_grab: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.2, 1.0, -0.3))
	var left_grab: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.0, -0.3))
	chosen.map_values(mapping, _values(left_grab, right_grab, 1.0, 1.0))
	var result: String = ""
	for frame: int in 5:
		var tilt: Basis = Basis(Vector3.RIGHT, 0.05 * frame) * Basis(Vector3.UP, 0.04 * frame)
		var right: Transform3D = Transform3D(tilt, right_grab.origin)
		var left: Transform3D = Transform3D(Basis.IDENTITY, left_grab.origin + Vector3(0.0, 0.01, -0.02) * frame)
		chosen.map_values(mapping, _values(left, right, 1.0, 1.0))
		var stick: GrippedControlsModel = chosen.models.stick
		var throttle: GrippedControlsModel = chosen.models.throttle
		var stick_relative: Transform3D = chosen.gripped.relative("right", {"right": right})
		var want_stick: Basis = GrippedControlsModel.clamped_stick_basis(stick_relative.basis)
		var want_throttle: Vector3 = GrippedControlsModel.clamped_throttle_offset(left.origin - left_grab.origin)
		if not stick.shown_pose().basis.is_equal_approx(want_stick) or stick.dimmed():
			result = "frame %d: the stick shows %s, wanted %s" % [frame, stick.shown_pose().basis, want_stick]
		elif not _near(throttle.shown_pose().origin, want_throttle) or throttle.dimmed():
			result = "frame %d: the throttle shows %s, wanted %s" % [frame, throttle.shown_pose().origin, want_throttle]
		elif not _near(stick.position, right_grab.origin) or not _near(throttle.position, left_grab.origin):
			result = "frame %d: the models are not at the grab points: %s %s" % [frame, stick.position, throttle.position]
		elif not stick.basis.is_equal_approx(Basis.IDENTITY):
			result = "frame %d: the stick's base is not upright in the rig's axes" % frame
		if result != "":
			break
	_done(chosen)
	return result


func test_before_a_grip_and_after_a_release_the_model_rests_dimmed_beside_the_hand() -> String:
	var chosen: ControlSchemeSwitch = _switch(ControlSchemeSwitch.GRIPPED)
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var anchors: ControllerAnchors = chosen.models.anchors
	var turned: Basis = Basis(Vector3.UP, 0.7)
	var right: Transform3D = Transform3D(turned, Vector3(0.25, 1.1, -0.2))
	var left: Transform3D = Transform3D(turned, Vector3(-0.25, 1.1, -0.2))
	var result: String = ""
	# Hands not seen yet: nothing floats at the origin.
	chosen.map_values(mapping, ControllerSampler.idle_values())
	if chosen.models.stick.visible or chosen.models.throttle.visible:
		result = "the models showed before any hand was seen"
	chosen.map_values(mapping, _values(left, right, 0.0, 0.0))
	var stick_rest: Vector3 = right * anchors.rest_offset("stick", "right")
	var throttle_rest: Vector3 = left * anchors.rest_offset("throttle", "left")
	if result == "" and (not _near(chosen.models.stick.position, stick_rest)
			or not _near(chosen.models.throttle.position, throttle_rest)):
		result = "before a grip: stick at %s (want %s), throttle at %s (want %s)" % [
			chosen.models.stick.position, stick_rest, chosen.models.throttle.position, throttle_rest]
	elif result == "" and (not chosen.models.stick.dimmed() or _near(stick_rest, Vector3.ZERO)):
		result = "the resting stick is not dimmed or rests at the origin"
	# Grip, tilt, let go: centred, dimmed, back beside the hand.
	chosen.map_values(mapping, _values(left, right, 1.0, 1.0))
	chosen.map_values(mapping, _values(left, Transform3D(Basis(Vector3.RIGHT, 0.3) * turned, right.origin), 1.0, 1.0))
	if result == "" and chosen.models.stick.dimmed():
		result = "a held stick is dimmed"
	chosen.map_values(mapping, _values(left, right, 1.0, 0.0))
	var stick: GrippedControlsModel = chosen.models.stick
	if result == "" and (not stick.dimmed() or stick.shown_pose() != Transform3D.IDENTITY
			or not _near(stick.position, stick_rest)):
		result = "after a release: dimmed %s, pose %s, at %s" % [stick.dimmed(), stick.shown_pose(), stick.position]
	if result == "" and chosen.models.throttle.dimmed():
		result = "the throttle let go with the stick"
	_done(chosen)
	return result


func test_rest_points_come_from_the_anchor_file_and_are_range_checked() -> String:
	var shipped: ControllerAnchors = ControllerAnchors.load_file()
	if shipped.error != "" or not shipped.gripped_rest.has("stick") or not shipped.gripped_rest.has("throttle"):
		return "the shipped file: %s %s" % [shipped.gripped_rest, shipped.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ControllerAnchors.DEFAULT_FILE))
	data["gripped_rest"] = {"stick": [0.03, -0.02, -0.05], "throttle": [0.0, 0.0, -0.1]}
	var custom: ControllerAnchors = ControllerAnchors.parse_data(data)
	if custom.error != "" or not _near(custom.rest_offset("stick", "right"), Vector3(0.03, -0.02, -0.05)) \
			or not _near(custom.rest_offset("stick", "left"), Vector3(-0.03, -0.02, -0.05)):
		return "a custom rest point was not used, or not mirrored: %s" % custom.error
	var bad_cases: Array = [
		{"stick": [0.0, 0.0, -0.5], "throttle": [0.0, 0.0, 0.0]},
		{"stick": [0.0, 0.0], "throttle": [0.0, 0.0, 0.0]},
		{"stick": [0.0, 0.0, 0.0]},
		{"stick": [0.0, 0.0, 0.0], "throttle": [0.0, 0.0, 0.0], "wheel": [0.0, 0.0, 0.0]},
		"ahead",
	]
	for bad: Variant in bad_cases:
		data["gripped_rest"] = bad
		var parsed: ControllerAnchors = ControllerAnchors.parse_data(data)
		if parsed.error == "" or not parsed.error.contains("gripped_rest"):
			return "gripped_rest %s gave \"%s\"" % [bad, parsed.error]
	data.erase("gripped_rest")
	var without: ControllerAnchors = ControllerAnchors.parse_data(data)
	if without.error != "" or without.gripped_rest != ControllerAnchors.GRIPPED_REST_DEFAULT:
		return "a file without gripped_rest gave %s \"%s\"" % [without.gripped_rest, without.error]
	return ""


func test_a_scheme_switch_from_the_menu_shows_or_hides_them_at_once() -> String:
	var chosen: ControlSchemeSwitch = _switch(ControlSchemeSwitch.THUMBSTICKS)
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	chosen.map_values(mapping, _values(Transform3D.IDENTITY, Transform3D.IDENTITY, 0.0, 0.0))
	var before: bool = chosen.models.is_shown()
	chosen.switch_to(ControlSchemeSwitch.GRIPPED, false)
	var after_gripped: bool = chosen.models.is_shown()
	chosen.switch_to(ControlSchemeSwitch.THUMBSTICKS, false)
	var after_thumbs: bool = chosen.models.is_shown()
	_done(chosen)
	if before or not after_gripped or after_thumbs:
		return "shown before %s, after gripped %s, after thumbsticks %s" % [before, after_gripped, after_thumbs]
	return ""


func test_left_handed_mode_puts_the_stick_in_the_left_hand() -> String:
	var chosen: ControlSchemeSwitch = _switch(ControlSchemeSwitch.GRIPPED)
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.left_handed = true
	var left: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.0, -0.3))
	var right: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.2, 1.0, -0.3))
	chosen.map_values(mapping, _values(left, right, 1.0, 0.0))
	var stick_at: Vector3 = chosen.models.stick.position
	var held: bool = not chosen.models.stick.dimmed() and chosen.models.throttle.dimmed()
	_done(chosen)
	if not _near(stick_at, left.origin) or not held:
		return "left-handed: the stick at %s (want %s), held by the left grip %s" % [stick_at, left.origin, held]
	return ""


func test_the_state_hash_is_the_same_with_the_models_as_without() -> String:
	var hashes: Array[int] = []
	var shown: bool = false
	for with_models: bool in [true, false]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.get_node("XRRig").call("build")
		main.call("_ready")
		var scheme: ControlSchemeSwitch = main.get("scheme")
		scheme.scheme = ControlSchemeSwitch.GRIPPED
		if not with_models:
			scheme.models.set_shown(false)
			scheme.models = null
		for frame: int in 90:
			var right: Transform3D = Transform3D(Basis(Vector3.RIGHT, -0.004 * frame), Vector3(0.2, 1.0, -0.3))
			var left: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.0, -0.3 - 0.001 * frame))
			main.call("apply_controls", _values(left, right, 1.0, 1.0 if frame < 70 else 0.0))
			main.call("advance_frame", FRAME)
		if with_models:
			shown = scheme.models.is_shown() and scheme.models.throttle.visible
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
	if not shown:
		return "the models were not shown through main.gd"
	if hashes[0] != hashes[1]:
		return "the models changed the simulation: %s" % [hashes]
	return ""
