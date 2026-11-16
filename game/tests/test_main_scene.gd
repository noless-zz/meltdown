extends RefCounted

## Structure checks for the entry scene and the stereo test tunnel
## (PLT-2, PLT-4). Scenes are instantiated outside the tree, so `_ready`
## does not run and no XR session or renderer is needed.


func _instantiate(path: String) -> Node:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


func test_main_scene_has_rig_and_tunnel() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	var missing: Array[String] = []
	var expected: Array[String] = ["TestTunnel", "XRRig", "XRRig/Camera", "XRRig/LeftHand", "XRRig/RightHand"]
	for path: String in expected:
		if main.get_node_or_null(path) == null:
			missing.append(path)
	var rig_ok: bool = main.get_node_or_null("XRRig") is XROrigin3D
	var camera_ok: bool = main.get_node_or_null("XRRig/Camera") is XRCamera3D
	var hands_ok: bool = main.get_node_or_null("XRRig/LeftHand") is XRController3D \
			and main.get_node_or_null("XRRig/RightHand") is XRController3D
	main.free()
	if not missing.is_empty():
		return "missing nodes: %s" % str(missing)
	if not rig_ok:
		return "XRRig is not an XROrigin3D"
	if not camera_ok:
		return "XRRig/Camera is not an XRCamera3D"
	if not hands_ok:
		return "hands are not XRController3D nodes"
	return ""


func test_tunnel_builds_lights_and_markers() -> String:
	var tunnel: Node = _instantiate("res://view/test_tunnel.tscn")
	if tunnel == null:
		return "test_tunnel.tscn did not load"
	tunnel.call("build")
	var lights: Node = tunnel.get_node_or_null("Lights")
	var markers: Node = tunnel.get_node_or_null("Markers")
	var light_count: int = lights.get_child_count() if lights != null else 0
	var marker_count: int = markers.get_child_count() if markers != null else 0
	var has_shell: bool = tunnel.get_node_or_null("Shell/Floor") != null
	tunnel.free()
	if light_count < 3:
		return "expected at least 3 lights, found %d" % light_count
	if marker_count != 3:
		return "expected 3 distance markers, found %d" % marker_count
	if not has_shell:
		return "tunnel shell is missing its floor"
	return ""


func test_tunnel_build_is_idempotent() -> String:
	var tunnel: Node = _instantiate("res://view/test_tunnel.tscn")
	if tunnel == null:
		return "test_tunnel.tscn did not load"
	tunnel.call("build")
	var first: int = tunnel.get_child_count()
	tunnel.call("build")
	var second: int = tunnel.get_child_count()
	tunnel.free()
	if first != second:
		return "second build() added nodes: %d then %d" % [first, second]
	return ""


## Runs `frames` frames at 90 Hz through the main scene's own frame step.
func _fly(main: Node, frames: int) -> void:
	for i: int in frames:
		main.call("advance_frame", 1.0 / 90.0)


func test_forward_thrust_moves_the_rig_along_minus_z() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	var source: LatestInputSource = main.get("input_source")
	var session: LocalSession = main.get("session")
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	_fly(main, 90)
	var rig: Node3D = main.get_node("XRRig") as Node3D
	var rig_position: Vector3 = rig.position
	var expected: Transform3D = ComfortWiring.interpolated_pose(
			session.previous_ship(), session.current_ship(), session.interpolation_fraction)
	var ship_position: Vector3 = session.current_ship().position
	var tick_travel: float = session.current_ship().position.distance_to(session.previous_ship().position)
	var ticks: int = session.sim.tick
	main.free()
	if ticks != 60:
		return "one second of frames ran %d ticks" % ticks
	if rig_position.z > -1.0:
		return "rig did not move forward along -z: %s" % str(rig_position)
	if absf(rig_position.x) > 1.0e-4 or absf(rig_position.y) > 1.0e-4:
		return "rig drifted sideways: %s" % str(rig_position)
	if not rig_position.is_equal_approx(expected.origin):
		return "rig %s is not at the interpolated ship pose %s" % [rig_position, expected.origin]
	if rig_position.distance_to(ship_position) > tick_travel + 1.0e-4:
		return "rig %s is more than one tick from the ship %s" % [rig_position, ship_position]
	return ""


func test_without_input_the_rig_stays_put() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	_fly(main, 90)
	var rig: Node3D = main.get_node("XRRig") as Node3D
	var rig_transform: Transform3D = rig.transform
	var ticks: int = (main.get("session") as LocalSession).sim.tick
	main.free()
	if ticks != 60:
		return "one second of frames ran %d ticks" % ticks
	if not rig_transform.is_equal_approx(Transform3D.IDENTITY):
		return "idle rig moved to %s" % str(rig_transform)
	return ""


func test_main_scene_records_one_input_object_per_tick() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	(main.get("input_source") as LatestInputSource).set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	_fly(main, 45)
	var frames: Array[Array] = (main.get("session") as LocalSession).replay.frames
	main.free()
	if frames.size() != 30:
		return "expected 30 recorded ticks, found %d" % frames.size()
	for i: int in range(1, frames.size()):
		if is_same(frames[i][0], frames[i - 1][0]):
			return "ticks %d and %d share one input object" % [i - 1, i]
	return ""


func test_interpolation_ends_match_previous_and_current_pose() -> String:
	var previous: ShipState = ShipState.new()
	previous.position = Vector3(1.0, 2.0, 3.0)
	previous.orientation = Basis(Vector3.UP, 0.3)
	var current: ShipState = ShipState.new()
	current.position = Vector3(1.5, 2.0, 2.0)
	current.orientation = Basis(Vector3.RIGHT, 0.2) * Basis(Vector3.UP, 0.5)
	var at_start: Transform3D = ComfortWiring.interpolated_pose(previous, current, 0.0)
	var at_end: Transform3D = ComfortWiring.interpolated_pose(previous, current, 1.0)
	var halfway: Transform3D = ComfortWiring.interpolated_pose(previous, current, 0.5)
	if not at_start.is_equal_approx(Transform3D(previous.orientation, previous.position)):
		return "fraction 0 is %s, not the previous pose" % str(at_start)
	if not at_end.is_equal_approx(Transform3D(current.orientation, current.position)):
		return "fraction 1 is %s, not the current pose" % str(at_end)
	if not halfway.origin.is_equal_approx(Vector3(1.25, 2.0, 2.5)):
		return "fraction 0.5 position is %s" % str(halfway.origin)
	if not is_equal_approx(halfway.basis.determinant(), 1.0):
		return "the blended rotation is not a pure rotation"
	return ""


func test_flying_the_rig_leaves_ship_copies_untouched() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	var session: LocalSession = main.get("session")
	(main.get("input_source") as LatestInputSource).set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	_fly(main, 30)
	var hash_before: int = session.sim.state_hash()
	main.call("place_rig")
	var hash_after: int = session.sim.state_hash()
	main.free()
	if hash_before != hash_after:
		return "placing the rig changed the simulation"
	return ""


func test_rig_labels_follow_the_main_scene_mapping() -> String:
	var main: Node = _instantiate("res://main.tscn")
	if main == null:
		return "main.tscn did not load"
	var rig: Node = main.get_node("XRRig")
	# Outside the tree no `_ready` runs by itself; call them in tree order.
	rig.call("build")
	main.call("_ready")
	var mapping: ThumbstickMapping = main.get("mapping") as ThumbstickMapping
	var message: String = ""
	if not is_same(rig.get("mapping"), mapping):
		message = "the rig does not read the main scene's mapping"
	mapping.left_handed = true
	rig.call("_process", 0.0)
	var left: ControllerModel = rig.call("model_for", "left") as ControllerModel
	var right: ControllerModel = rig.call("model_for", "right") as ControllerModel
	if message == "" and left.label_texts().get("button_lower", "") != "boost":
		message = "left-handed boost should label X: %s" % left.label_texts()
	if message == "" and right.label_texts().get("button_lower", "") == "boost":
		message = "A still reads boost: %s" % right.label_texts()
	main.free()
	return message
