extends RefCounted

## The cockpit frame in the main scene (CMF-1, ARC-3, #160, #478): one frame
## under the rig origin at the recentred head point, fixed to the ship while
## the head turns, built from the active preset's cockpit file and rebuilt on
## every preset change. The frame's own geometry is tested in
## `test_cockpit_frame.gd`.

const Scene := preload("res://tests/cockpit_scene.gd")


const FrameTests := preload("res://tests/test_cockpit_frame.gd")


## The nearest any part of the frame comes to the eye.
static func _nearest_surface(frame: CockpitFrame) -> float:
	return FrameTests.distance_range(frame).x


func test_the_start_up_frame_is_the_start_presets() -> String:
	var main: Node = Scene.new_main()
	if main == null:
		return "main.tscn did not load"
	var rig: Node = main.get_node("XRRig")
	# Outside the tree no `_ready` runs by itself; call them in tree order.
	rig.call("build")
	main.call("_ready")
	var message: String = Scene.one_frame_at_the_eye(main)
	var comfort: ComfortWiring = main.get("comfort")
	if message == "":
		message = Scene.spec_mismatch(comfort.cockpit_frame.spec, comfort.number)
	main.free()
	return message


func test_each_preset_shows_its_own_frame() -> String:
	var main: Node = Scene.new_main()
	main.call("attach_cockpit_frame")
	var comfort: ComfortWiring = main.get("comfort")
	var message: String = ""
	for number: int in [1, 2, 3, 4]:
		main.call("set_comfort_preset", number)
		message = Scene.one_frame_at_the_eye(main)
		if message == "":
			message = Scene.spec_mismatch(comfort.cockpit_frame.spec, number)
		if message == "" and comfort.cockpit_frame.instance_count("Solid") \
				+ comfort.cockpit_frame.instance_count("Glass") == 0:
			message = "preset %d: the frame has no shell" % number
		if message != "":
			break
	main.free()
	return message


func test_the_preset_button_swaps_the_frame_at_once() -> String:
	var main: Node = Scene.new_main()
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
		message = Scene.one_frame_at_the_eye(main)
	if message == "":
		message = Scene.spec_mismatch(comfort.cockpit_frame.spec, 2)
	main.free()
	return message


func test_attaching_twice_keeps_one_frame() -> String:
	var main: Node = Scene.new_main()
	main.call("attach_cockpit_frame")
	main.call("attach_cockpit_frame")
	var message: String = Scene.one_frame_at_the_eye(main)
	main.free()
	return message


func test_preset_one_has_a_smaller_window_than_preset_four() -> String:
	var main: Node = Scene.new_main()
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
	var main: Node = Scene.new_main()
	main.call("attach_cockpit_frame")
	main.call("attach_fade_overlay")
	var comfort: ComfortWiring = main.get("comfort")
	var fade: FadeOverlay = main.get("fade_overlay")
	var message: String = ""
	if fade == null or fade.get_parent() != Scene.camera(main):
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
	var main: Node = Scene.new_main()
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
		return "set_preset built a frame with no rig to put it under"
	return ""

