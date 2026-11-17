extends RefCounted

## The cockpit frame is fixed to the ship, not the head (#478, CMF-1, ARC-3):
## it sits under the rig origin at the recentred head point with the status
## panel, so turning the head leaves it still and only a recentre moves it.

const Scene := preload("res://tests/cockpit_scene.gd")


func test_turning_the_head_leaves_the_frame_still() -> String:
	var main: Node = Scene.seated_main()
	var frame: CockpitFrame = (main.get("comfort") as ComfortWiring).cockpit_frame
	var camera: Node3D = Scene.camera(main)
	var frame_before: Transform3D = Scene.in_main(frame, main)
	var camera_before: Transform3D = Scene.in_main(camera, main)
	camera.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(30.0), deg_to_rad(90.0), 0.0)),
		Scene.SEATED_HEAD)
	for i: int in 5:
		main.call("advance_frame", Scene.FRAME)
	var frame_after: Transform3D = Scene.in_main(frame, main)
	var camera_after: Transform3D = Scene.in_main(camera, main)
	var message: String = Scene.one_frame_at_the_eye(main)
	main.free()
	if message != "":
		return message
	if camera_after.is_equal_approx(camera_before):
		return "the camera did not turn, so the test shows nothing"
	if not frame_after.is_equal_approx(frame_before):
		return "turning the head moved the frame from %s to %s" % [frame_before, frame_after]
	return ""


func test_a_recentre_moves_the_frame_with_the_panel() -> String:
	var main: Node = Scene.seated_main()
	var frame: CockpitFrame = (main.get("comfort") as ComfortWiring).cockpit_frame
	var panel: StatusPanel = main.get("status_panel")
	var before: Transform3D = frame.transform
	Scene.camera(main).transform = Transform3D(Basis(Vector3.UP, deg_to_rad(40.0)), Vector3(0.1, 1.0, 0.05))
	(main.get("head_recentre") as HeadRecentre).request()
	main.call("advance_frame", Scene.FRAME)
	var message: String = Scene.one_frame_at_the_eye(main)
	if message == "" and frame.transform.is_equal_approx(before):
		message = "the recentre left the frame where it was"
	if message == "" and not panel.transform.is_equal_approx(StatusPanel.rig_transform(frame.transform)):
		message = "the panel %s is not placed from the frame's head point %s" % [panel.transform, frame.transform]
	main.free()
	return message


func test_a_preset_change_rebuilds_the_frame_in_the_same_place() -> String:
	var main: Node = Scene.seated_main()
	var comfort: ComfortWiring = main.get("comfort")
	var frame: CockpitFrame = comfort.cockpit_frame
	var placed: Transform3D = frame.transform
	var message: String = ""
	for number: int in [1, 4, 3, 2]:
		main.call("set_comfort_preset", number)
		main.call("advance_frame", Scene.FRAME)
		message = Scene.one_frame_at_the_eye(main)
		if message == "" and comfort.cockpit_frame != frame:
			message = "preset %d replaced the frame node instead of rebuilding it" % number
		if message == "" and not comfort.cockpit_frame.transform.is_equal_approx(placed):
			message = "preset %d moved the frame from %s to %s" % [number, placed, comfort.cockpit_frame.transform]
		if message != "":
			break
	main.free()
	return message


## Head motion is view only: the same frames flown with the head still and
## with it turning end on the same simulation hash (ARC-3, MP-2).
func test_turning_the_head_leaves_the_simulation_alone() -> String:
	var hashes: Array[int] = []
	for turning: bool in [false, true]:
		var main: Node = Scene.seated_main()
		main.call("attach_fade_overlay")
		var values: Dictionary = ControllerSampler.idle_values()
		values["left_stick"] = Vector2(0.0, 1.0)
		for i: int in 60:
			if turning:
				Scene.camera(main).transform = Transform3D(Basis(Vector3.UP, 0.05 * i), Scene.SEATED_HEAD)
			main.call("apply_controls", values)
			main.call("advance_frame", Scene.FRAME)
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
	if hashes[0] != hashes[1]:
		return "turning the head changed the simulation hash: %d against %d" % [hashes[0], hashes[1]]
	return ""
