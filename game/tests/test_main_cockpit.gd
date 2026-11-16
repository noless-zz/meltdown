extends RefCounted

## The cockpit frame in the main scene (CMF-1, ARC-3, #160): one frame under
## the rig's camera, built from the active preset's cockpit file and rebuilt
## on every preset change. The frame's own geometry is tested in
## `test_cockpit_frame.gd`.


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


static func _camera(main: Node) -> Node3D:
	return main.get_node_or_null("XRRig/Camera") as Node3D


## Every `CockpitFrame` anywhere under `node`.
static func _frames(node: Node) -> Array[CockpitFrame]:
	var found: Array[CockpitFrame] = []
	for child: Node in node.get_children():
		if child is CockpitFrame:
			found.append(child as CockpitFrame)
		found.append_array(_frames(child))
	return found


## Empty when `spec` holds the same values as the file of preset `number`.
static func _spec_mismatch(spec: CockpitSpec, number: int) -> String:
	if spec == null:
		return "preset %d: the frame has no spec" % number
	var expected: CockpitSpec = CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))
	if expected.error != "":
		return "preset %d: its cockpit file is rejected: %s" % [number, expected.error]
	for key: String in CockpitSpec.KEYS:
		if not is_equal_approx(float(spec.get(key)), float(expected.get(key))):
			return "preset %d: %s is %s, its file says %s" % [number, key, spec.get(key), expected.get(key)]
	return ""


## Empty when the scene holds exactly one frame, under the camera at the eye.
static func _one_frame_at_the_eye(main: Node) -> String:
	var frames: Array[CockpitFrame] = _frames(main)
	if frames.size() != 1:
		return "the scene holds %d cockpit frames, not one" % frames.size()
	if frames[0].get_parent() != _camera(main):
		return "the frame is not under the rig's camera"
	if not frames[0].transform.is_equal_approx(Transform3D.IDENTITY):
		return "the frame's origin is not at the eye: %s" % frames[0].transform
	return ""


## The nearest any part of the frame can come to the eye: each instance's
## centre distance less half the sum of its scaled unit axes, which bounds
## its half diagonal from above. Shell panels are flat quads, so their third
## axis adds no depth; struts are boxes and it does.
static func _nearest_surface(frame: CockpitFrame) -> float:
	var nearest: float = INF
	for part_name: String in ["Solid", "Glass", "Struts"]:
		var deep: bool = part_name == "Struts"
		for placed: Transform3D in frame.instance_transforms(part_name):
			var reach: float = 0.5 * (placed.basis.x.length() + placed.basis.y.length()
				+ (placed.basis.z.length() if deep else 0.0))
			nearest = minf(nearest, placed.origin.length() - reach)
	return nearest


func test_the_start_up_frame_is_the_start_presets() -> String:
	var main: Node = _main()
	if main == null:
		return "main.tscn did not load"
	var rig: Node = main.get_node("XRRig")
	# Outside the tree no `_ready` runs by itself; call them in tree order.
	rig.call("build")
	main.call("_ready")
	var message: String = _one_frame_at_the_eye(main)
	var comfort: ComfortWiring = main.get("comfort")
	if message == "":
		message = _spec_mismatch(comfort.cockpit_frame.spec, comfort.number)
	main.free()
	return message


func test_each_preset_shows_its_own_frame() -> String:
	var main: Node = _main()
	main.call("attach_cockpit_frame")
	var comfort: ComfortWiring = main.get("comfort")
	var message: String = ""
	for number: int in [1, 2, 3, 4]:
		main.call("set_comfort_preset", number)
		message = _one_frame_at_the_eye(main)
		if message == "":
			message = _spec_mismatch(comfort.cockpit_frame.spec, number)
		if message == "" and comfort.cockpit_frame.instance_count("Solid") \
				+ comfort.cockpit_frame.instance_count("Glass") == 0:
			message = "preset %d: the frame has no shell" % number
		if message != "":
			break
	main.free()
	return message


func test_the_preset_button_swaps_the_frame_at_once() -> String:
	var main: Node = _main()
	main.call("attach_cockpit_frame")
	main.call("set_comfort_preset", 1)
	var comfort: ComfortWiring = main.get("comfort")
	var frame_before: CockpitFrame = comfort.cockpit_frame
	var spec_before: CockpitSpec = frame_before.spec
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = {"left_button_upper": true}
	main.call("apply_controls", values)
	var message: String = ""
	if comfort.number != 2:
		message = "Y on preset 1 gave preset %d" % comfort.number
	elif comfort.cockpit_frame != frame_before:
		message = "the switch replaced the frame node instead of rebuilding it"
	elif comfort.cockpit_frame.spec == spec_before:
		message = "the frame still holds preset 1's spec"
	if message == "":
		message = _one_frame_at_the_eye(main)
	if message == "":
		message = _spec_mismatch(comfort.cockpit_frame.spec, 2)
	main.free()
	return message


func test_attaching_twice_keeps_one_frame() -> String:
	var main: Node = _main()
	main.call("attach_cockpit_frame")
	main.call("attach_cockpit_frame")
	var message: String = _one_frame_at_the_eye(main)
	main.free()
	return message


func test_preset_one_has_a_smaller_window_than_preset_four() -> String:
	var main: Node = _main()
	main.call("attach_cockpit_frame")
	var comfort: ComfortWiring = main.get("comfort")
	main.call("set_comfort_preset", 1)
	var narrow: float = comfort.cockpit_frame.spec.window_solid_angle()
	main.call("set_comfort_preset", 4)
	var wide: float = comfort.cockpit_frame.spec.window_solid_angle()
	main.free()
	if narrow >= wide:
		return "preset 1's window (%.3f sr) is not smaller than preset 4's (%.3f sr)" % [narrow, wide]
	return ""


func test_the_fade_sits_nearer_the_eye_than_every_frame() -> String:
	var main: Node = _main()
	main.call("attach_cockpit_frame")
	main.call("attach_fade_overlay")
	var comfort: ComfortWiring = main.get("comfort")
	var fade: FadeOverlay = main.get("fade_overlay")
	var message: String = ""
	if fade == null or fade.get_parent() != _camera(main):
		message = "the fade quad is not under the camera"
	for number: int in [1, 2, 3, 4]:
		if message != "":
			break
		main.call("set_comfort_preset", number)
		var nearest: float = _nearest_surface(comfort.cockpit_frame)
		if nearest <= fade.position.length():
			message = "preset %d: the frame comes %.3f m from the eye, not beyond the fade at %.3f m" % [
				number, nearest, fade.position.length()]
	main.free()
	return message


func test_the_frame_leaves_the_simulation_alone() -> String:
	var main: Node = _main()
	var session: LocalSession = main.get("session")
	for i: int in 10:
		main.call("advance_frame", 1.0 / 90.0)
	var hash_before: int = session.sim.state_hash()
	main.call("attach_cockpit_frame")
	for number: int in [1, 3, 4, 2]:
		main.call("set_comfort_preset", number)
	var hash_after: int = session.sim.state_hash()
	main.free()
	if hash_before != hash_after:
		return "building and rebuilding the cockpit frame changed the simulation"
	return ""


func test_a_wiring_outside_a_scene_owns_no_frame() -> String:
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	wiring.set_preset(1)
	if wiring.cockpit_frame != null:
		return "set_preset built a frame with no camera to put it under"
	return ""
