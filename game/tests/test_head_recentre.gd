extends RefCounted

## The eye point at the ship's centre, so the view cannot reach a wall before
## the ship does (#102): CMF-8, CMF-11, FLT-3, ARC-3. The main-scene tests run
## flat, with the camera's local transform standing in for the tracked head.

const FRAME: float = 1.0 / 90.0
const SEATED_HEAD: Vector3 = Vector3(0.0, 1.6, 0.0)
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


static func _camera(main: Node) -> Node3D:
	return main.get_node("XRRig/Camera") as Node3D


## The camera's world transform, worked out by hand: the scene is not in a tree.
static func _camera_global(main: Node) -> Transform3D:
	return (main.get_node("XRRig") as Node3D).transform * _camera(main).transform


static func _ship_pose(main: Node) -> Transform3D:
	var session: LocalSession = main.get("session") as LocalSession
	return main.call("interpolated_pose", session.previous_ship(), session.current_ship(),
		session.interpolation_fraction) as Transform3D


## Flies forward while turning, so the ship is away from the start and rotated.
static func _fly(main: Node, frames: int) -> void:
	(main.get("input_source") as LatestInputSource).set_input(
		ShipInput.new(Vector3i(0, 0, -1000), Vector3i(200, 400, 0)))
	for i: int in frames:
		main.call("advance_frame", FRAME)


func test_head_reach_keeps_the_near_plane_inside_the_ship() -> String:
	var tuning: ShipTuning = LocalSession.load_tuning(SHIP_TUNING_PATH)
	var rig: Node = (load("res://xr/xr_rig.tscn") as PackedScene).instantiate()
	var camera: Camera3D = rig.get_node_or_null("Camera") as Camera3D
	var near: float = camera.near if camera != null else -1.0
	rig.free()
	if tuning == null:
		return "the shipped tuning file was rejected"
	if near <= 0.0:
		return "the rig scene has no camera with a near plane"
	if not is_equal_approx(HeadRecentre.HEAD_REACH, 0.4):
		return "HEAD_REACH is %f, not 0.4 m" % HeadRecentre.HEAD_REACH
	if tuning.radius - HeadRecentre.HEAD_REACH < 2.0 * near:
		return "radius %f minus reach %f leaves less than twice the near plane %f" \
			% [tuning.radius, HeadRecentre.HEAD_REACH, near]
	return ""


func test_the_offset_takes_the_head_to_the_origin_facing_forward() -> String:
	var tilt: Basis = Basis(Vector3.RIGHT, 0.2)
	var head: Transform3D = Transform3D(Basis(Vector3.UP, 0.7) * tilt, Vector3(0.1, 1.6, 0.3))
	var seen: Transform3D = HeadRecentre.offset_for(head) * head
	if seen.origin.length() > 1.0e-5:
		return "the head ends at %s, not the origin" % seen.origin
	if not seen.basis.is_equal_approx(tilt):
		return "the head's basis is %s; only its tilt should remain" % seen.basis
	return ""


func test_looking_straight_up_has_no_heading() -> String:
	var heading: float = HeadRecentre.heading(Basis(Vector3.RIGHT, PI / 2.0))
	if heading != 0.0:
		return "straight up gave heading %f" % heading
	return ""


func test_nothing_recentres_until_asked() -> String:
	var recentre: HeadRecentre = HeadRecentre.new()
	var moved: bool = recentre.update(Transform3D(Basis(), SEATED_HEAD), false)
	if moved or recentre.offset != Transform3D.IDENTITY:
		return "an unrequested update recentred"
	return ""


func test_in_xr_it_waits_for_a_tracked_head() -> String:
	var recentre: HeadRecentre = HeadRecentre.new()
	recentre.request()
	# Headless CI has no head tracker, like the first frames of a session.
	var moved: bool = recentre.update(Transform3D(Basis(), SEATED_HEAD), true)
	if moved or not recentre.pending or recentre.offset != Transform3D.IDENTITY:
		return "recentred on an untracked head"
	if not recentre.update(Transform3D(Basis(), SEATED_HEAD), false) or recentre.pending:
		return "the flat camera did not take the pending recentre"
	return ""


func test_flat_recentre_puts_the_camera_at_the_ship_centre() -> String:
	var main: Node = _main()
	_fly(main, 45)
	_camera(main).transform = Transform3D(Basis(), SEATED_HEAD)
	var session: LocalSession = main.get("session") as LocalSession
	var hash_before: int = session.sim.state_hash()
	(main.get("head_recentre") as HeadRecentre).request()
	main.call("place_rig")
	var hash_after: int = session.sim.state_hash()
	var camera_at: Vector3 = _camera_global(main).origin
	var ship_at: Vector3 = _ship_pose(main).origin
	main.free()
	if ship_at.length() < 1.0:
		return "the ship did not leave the start"
	if camera_at.distance_to(ship_at) > 0.01:
		return "camera at %s, ship at %s" % [camera_at, ship_at]
	if hash_before != hash_after:
		return "the recentre changed the simulation"
	return ""


func test_the_view_follows_the_ship_without_recentring_again() -> String:
	var main: Node = _main()
	_camera(main).transform = Transform3D(Basis(), SEATED_HEAD)
	var recentre: HeadRecentre = main.get("head_recentre") as HeadRecentre
	recentre.request()
	main.call("place_rig")
	var offset: Transform3D = recentre.offset
	# The player leans; flight must carry the lean, not take it away.
	var lean: Vector3 = Vector3(0.3, -0.1, 0.0)
	_camera(main).transform = Transform3D(Basis(), SEATED_HEAD + lean)
	_fly(main, 90)
	var camera_at: Vector3 = _camera_global(main).origin
	var expected: Vector3 = _ship_pose(main) * lean
	main.free()
	if recentre.offset != offset:
		return "flying changed the recentre offset"
	if camera_at.distance_to(expected) > 0.01:
		return "leaning camera at %s, expected %s" % [camera_at, expected]
	return ""


func test_reset_to_start_recentres() -> String:
	var main: Node = _main()
	_camera(main).transform = Transform3D(Basis(), SEATED_HEAD)
	(main.get("head_recentre") as HeadRecentre).request()
	main.call("place_rig")
	# The player has shifted in the seat by the time they reset.
	_camera(main).transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.2, 1.4, 0.1))
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = {"left_stick_click": true, "right_stick_click": true}
	var hold: ResetHold = main.get("reset_hold") as ResetHold
	var frames: int = 0
	while not hold.reset_due() and frames < 600:
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)
		frames += 1
	for i: int in 3:
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)
	var camera: Transform3D = _camera_global(main)
	var ship: Transform3D = _ship_pose(main)
	main.free()
	if frames >= 600:
		return "the reset never came due"
	if camera.origin.distance_to(ship.origin) > 0.01:
		return "after the reset the camera is at %s, the ship at %s" % [camera.origin, ship.origin]
	if absf(HeadRecentre.heading(ship.basis.inverse() * camera.basis)) > 1.0e-3:
		return "after the reset the view does not face the ship's forward"
	return ""
