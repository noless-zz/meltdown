extends RefCounted

## Solo pause when the headset loses focus (issue #62, PLT-7, CMF-8, MP-2).


func _flying_session() -> LocalSession:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000), Vector3i(200, 0, 0)))
	var session: LocalSession = LocalSession.new(7, source)
	for i: int in 50:
		session.advance(1.0 / 90.0)
	return session


func test_advancing_while_paused_changes_neither_tick_nor_hash() -> String:
	var session: LocalSession = _flying_session()
	var tick_before: int = session.sim.tick
	var hash_before: int = session.sim.state_hash()
	var fraction_before: float = session.interpolation_fraction
	var pose_before: Vector3 = session.current_ship().position
	session.paused = true
	var ticks: int = 0
	for i: int in 900:
		ticks += session.advance(1.0 / 90.0)
	ticks += session.advance(120.0)
	if ticks != 0 or session.ticks_last_advance != 0:
		return "paused advances ran %d ticks" % ticks
	if session.sim.tick != tick_before:
		return "tick moved from %d to %d while paused" % [tick_before, session.sim.tick]
	if session.sim.state_hash() != hash_before:
		return "state hash changed while paused"
	if session.interpolation_fraction != fraction_before:
		return "interpolation fraction moved from %f to %f" % [fraction_before, session.interpolation_fraction]
	if session.current_ship().position != pose_before:
		return "the ship copy moved while paused"
	if session.dropped_seconds != 0.0:
		return "paused time was counted as dropped: %f s" % session.dropped_seconds
	return ""


func test_resuming_after_a_long_pause_runs_at_most_one_tick() -> String:
	var session: LocalSession = _flying_session()
	session.paused = true
	for i: int in 90 * 30:
		session.advance(1.0 / 90.0)
	session.paused = false
	var first: int = session.advance(1.0 / 90.0)
	if first > 1:
		return "first frame after resuming ran %d ticks" % first
	return ""


func test_a_resume_frame_reporting_the_whole_pause_runs_one_tick() -> String:
	var session: LocalSession = _flying_session()
	session.paused = true
	session.advance(1.0 / 90.0)
	session.paused = false
	var first: int = session.advance(45.0)
	if first > 1:
		return "a 45 s resume frame ran %d ticks" % first
	# The limit is for that one frame only; normal flight continues after it.
	var ticks: int = 0
	for i: int in 90:
		ticks += session.advance(1.0 / 90.0)
	if ticks < 59 or ticks > 61:
		return "one second after resuming ran %d ticks" % ticks
	return ""


func test_pause_and_resume_keep_the_replay_reproducible() -> String:
	var session: LocalSession = _flying_session()
	session.paused = true
	session.advance(3.0)
	session.paused = false
	for i: int in 45:
		session.advance(1.0 / 90.0)
	var replayed: Sim = session.replay.run()
	if replayed.state_hash() != session.sim.state_hash():
		return "replay does not reproduce the paused-and-resumed run"
	return ""


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


func test_main_scene_handlers_set_and_clear_paused() -> String:
	var main: Node = _main()
	if main == null:
		return "main.tscn did not load"
	var session: LocalSession = main.get("session")
	var failures: Array[String] = []
	if session.paused:
		failures.append("the scene starts paused")
	for handler: String in ["on_session_visible", "on_session_loss_pending", "on_session_stopping"]:
		session.paused = false
		main.call(handler)
		if not session.paused:
			failures.append("%s did not pause" % handler)
		main.call("on_session_focussed")
		if session.paused:
			failures.append("on_session_focussed did not resume after %s" % handler)
	main.free()
	if not failures.is_empty():
		return ", ".join(failures)
	return ""


func test_paused_main_scene_holds_the_rig_still() -> String:
	var main: Node = _main()
	if main == null:
		return "main.tscn did not load"
	var session: LocalSession = main.get("session")
	(main.get("input_source") as LatestInputSource).set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	for i: int in 40:
		main.call("advance_frame", 1.0 / 90.0)
	var rig: Node3D = main.get_node("XRRig") as Node3D
	var held: Transform3D = rig.transform
	var tick_held: int = session.sim.tick
	main.call("on_session_visible")
	for i: int in 180:
		main.call("advance_frame", 1.0 / 90.0)
	var after_pause: Transform3D = rig.transform
	var tick_after_pause: int = session.sim.tick
	main.call("on_session_focussed")
	main.call("advance_frame", 10.0)
	var tick_resumed: int = session.sim.tick
	main.free()
	if tick_after_pause != tick_held:
		return "the scene ran %d ticks while paused" % (tick_after_pause - tick_held)
	if after_pause != held:
		return "the rig moved while paused: %s to %s" % [held.origin, after_pause.origin]
	if tick_resumed - tick_held > 1:
		return "the resume frame ran %d ticks" % (tick_resumed - tick_held)
	return ""
