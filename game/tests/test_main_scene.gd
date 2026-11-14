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
