extends RefCounted

## The main scene as the cockpit tests build it (#160, #478): shared by
## `test_main_cockpit.gd` and `test_main_cockpit_head.gd`.

## Where a seated player's eyes are tracked, as in `test_cockpit_preset1_view.gd`.
const SEATED_HEAD: Vector3 = Vector3(0.0, 1.2, 0.0)
const FRAME: float = 1.0 / 90.0


static func new_main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


static func camera(main: Node) -> Node3D:
	return main.get_node_or_null("XRRig/Camera") as Node3D


static func rig(main: Node) -> Node3D:
	return main.get_node_or_null("XRRig") as Node3D


## `node`'s transform in the main scene's space, without a scene tree.
static func in_main(node: Node3D, main: Node) -> Transform3D:
	var result: Transform3D = node.transform
	var parent: Node3D = node.get_parent() as Node3D
	while parent != null and parent != main:
		result = parent.transform * result
		parent = parent.get_parent() as Node3D
	return result


## A main scene with the frame and panel attached, the camera at a seated
## head and recentred there by a first frame.
static func seated_main() -> Node:
	var main: Node = new_main()
	main.call("attach_cockpit_frame")
	main.call("attach_status_panel")
	camera(main).transform = Transform3D(Basis(), SEATED_HEAD)
	(main.get("head_recentre") as HeadRecentre).request()
	main.call("advance_frame", FRAME)
	return main


## Every `CockpitFrame` anywhere under `node`.
static func all_frames(node: Node) -> Array[CockpitFrame]:
	var found: Array[CockpitFrame] = []
	for child: Node in node.get_children():
		if child is CockpitFrame:
			found.append(child as CockpitFrame)
		found.append_array(all_frames(child))
	return found


## Empty when `spec` holds the same values as the file of preset `number`.
static func spec_mismatch(spec: CockpitSpec, number: int) -> String:
	if spec == null:
		return "preset %d: the frame has no spec" % number
	var expected: CockpitSpec = CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))
	if expected.error != "":
		return "preset %d: its cockpit file is rejected: %s" % [number, expected.error]
	for key: String in CockpitSpec.KEYS:
		if not is_equal_approx(float(spec.get(key)), float(expected.get(key))):
			return "preset %d: %s is %s, its file says %s" % [number, key, spec.get(key), expected.get(key)]
	return ""


## Empty when the scene holds exactly one frame, under the rig origin at the
## recentred head point (#478).
static func one_frame_at_the_eye(main: Node) -> String:
	var frames: Array[CockpitFrame] = all_frames(main)
	if frames.size() != 1:
		return "the scene holds %d cockpit frames, not one" % frames.size()
	if frames[0].get_parent() != rig(main):
		return "the frame is not under the rig origin"
	var head_point: Transform3D = RigViews.head_point(main.get("head_recentre") as HeadRecentre)
	if not frames[0].transform.is_equal_approx(head_point):
		return "the frame's origin %s is not at the head point %s" % [frames[0].transform, head_point]
	return ""
