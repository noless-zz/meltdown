extends RefCounted

## The view guard in the main scene (#651): a head lost from the window for
## longer than the cockpit file allows gets the frame and panel back in front
## of it, while the rig, and so the world, stays where the ship puts it
## (CMF-8, ARC-3).

const Scene := preload("res://tests/cockpit_scene.gd")


## A seated main scene whose comfort clock reads `now[0]`.
static func _main_with_clock(now: Array[float]) -> Node:
	var main: Node = Scene.seated_main()
	(main.get("comfort") as ComfortWiring).clock = func() -> float: return now[0]
	return main


static func _frames(main: Node, now: Array[float], seconds: float) -> void:
	for i: int in int(ceil(seconds / Scene.FRAME)):
		now[0] += Scene.FRAME
		main.call("advance_frame", Scene.FRAME)


func test_a_lost_head_gets_the_frame_and_panel_back_and_the_rig_stays() -> String:
	var now: Array[float] = [100.0]
	var main: Node = _main_with_clock(now)
	var comfort: ComfortWiring = main.get("comfort")
	var spec: CockpitSpec = comfort.cockpit_frame.spec
	var panel: StatusPanel = main.get("status_panel")
	var head: Transform3D = Transform3D(Basis(Vector3.UP, -deg_to_rad(150.0)), Scene.SEATED_HEAD)
	Scene.camera(main).transform = head
	_frames(main, now, spec.guard_after_s * 0.5)
	var message: String = Scene.one_frame_at_the_eye(main)
	if message != "":
		main.free()
		return "before the wait: %s" % message
	var rig_before: Transform3D = Scene.rig(main).transform
	_frames(main, now, spec.guard_after_s)
	var frame: CockpitFrame = comfort.cockpit_frame
	var expected: Transform3D = ViewGuard.point_for(head)
	if not frame.transform.is_equal_approx(expected):
		message = "frame at %s, not around the head %s" % [frame.transform, expected]
	elif not panel.transform.is_equal_approx(StatusPanel.rig_transform(frame.transform)):
		message = "the panel %s did not follow the frame %s" % [panel.transform, frame.transform]
	elif not Scene.rig(main).transform.is_equal_approx(rig_before):
		message = "the re-place moved the rig from %s to %s" % [rig_before, Scene.rig(main).transform]
	elif comfort.view_guard.replacements != 1:
		message = "%d re-placements, not 1" % comfort.view_guard.replacements
	main.free()
	return message


func test_a_recentre_after_a_re_place_puts_the_frame_at_the_head_point() -> String:
	var now: Array[float] = [5.0]
	var main: Node = _main_with_clock(now)
	var comfort: ComfortWiring = main.get("comfort")
	Scene.camera(main).transform = Transform3D(Basis(Vector3.UP, 2.6), Scene.SEATED_HEAD)
	_frames(main, now, comfort.cockpit_frame.spec.guard_after_s + 0.2)
	if comfort.view_guard.replacements != 1:
		main.free()
		return "the lost head was not re-placed, so the test shows nothing"
	(main.get("head_recentre") as HeadRecentre).request()
	_frames(main, now, Scene.FRAME)
	var message: String = Scene.one_frame_at_the_eye(main)
	main.free()
	return message


func test_the_guard_leaves_the_simulation_alone() -> String:
	var now: Array[float] = [0.0]
	var main: Node = _main_with_clock(now)
	var session: LocalSession = main.get("session")
	Scene.camera(main).transform = Transform3D(Basis(Vector3.UP, 3.0), Scene.SEATED_HEAD + Vector3(0.0, 0.0, 0.7))
	var still: Node = _main_with_clock([0.0] as Array[float])
	for i: int in 400:
		now[0] += Scene.FRAME
		main.call("advance_frame", Scene.FRAME)
		still.call("advance_frame", Scene.FRAME)
	var a: ShipState = session.current_ship()
	var b: ShipState = (still.get("session") as LocalSession).current_ship()
	var message: String = ""
	if (main.get("comfort") as ComfortWiring).view_guard.replacements == 0:
		message = "the guard never acted, so the test shows nothing"
	elif not a.position.is_equal_approx(b.position) or not a.orientation.is_equal_approx(b.orientation) \
			or a.hull != b.hull:
		message = "the guard changed the ship: %s / %s against %s / %s" % [a.position, a.hull, b.position, b.hull]
	main.free()
	still.free()
	return message
