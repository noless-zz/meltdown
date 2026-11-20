extends RefCounted

## Taking the headset off during a meltdown pauses it (#608; PLT-7, CMF-8,
## RUN-2): in the real main scene on G2, with the reactor destroyed, the calls
## a removed headset causes hold the simulation tick, the countdown, the ship
## and the shots in flight however much wall-clock time passes, and putting the
## headset back on resumes with at most one tick.
##
## The flat keyboard build has no pause of its own: a desktop window losing
## focus keeps flying. Only the XR session's state changes pause the run.

const FRAME: float = 1.0 / 72.0
## G2's box around the reactor, as `test_main_escape_cue.gd` uses it.
const REACTOR_BOX: int = 4
## Longer than G2's longest countdown (`meltdown_max_seconds` 120).
const AWAY_SECONDS: float = 300.0

## The headset coming off, as the OpenXR runtime reports it to the scene in
## the orders it can: focus lost only (the headset is put back soon), focus
## lost then the session stopping (it went to sleep), and the session about
## to be lost then stopping.
const OFF_SEQUENCES: Array = [
	["on_session_visible"],
	["on_session_visible", "on_session_stopping"],
	["on_session_loss_pending", "on_session_stopping"],
]


## G2 in the main scene, rig built and `_ready` run as in play, flown for a
## second and its reactor destroyed through the simulation, as a killing shot
## would, with the ship in the reactor's room; then half a second into the
## meltdown. A test may write simulation
## state; the scene never does.
func _main_in_meltdown() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("use_level", LevelSwitch.path_for("g2"))
	main.call("_ready")
	_frames(main, 72, FRAME)
	var session: LocalSession = main.get("session")
	# Away from the start, whose exit sphere would end the run at once.
	var reactor_room: BoxBounds = session.replay.walls().boxes[REACTOR_BOX]
	session.sim.ships[0].position = (reactor_room.min_corner + reactor_room.max_corner) / 2.0
	session.sim.ships[0].velocity = Vector3.ZERO
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	_frames(main, 36, FRAME)
	return main


static func _frames(main: Node, count: int, delta: float) -> void:
	for i: int in count:
		main.call("apply_controls", ControllerSampler.idle_values())
		main.call("advance_frame", delta)


static func _shots(session: LocalSession) -> Array[Vector3]:
	var at: Array[Vector3] = []
	for shot: Projectile in session.sim.projectiles:
		at.append(shot.position)
	return at


func test_the_headset_off_holds_the_meltdown_however_long_it_is_off() -> String:
	for sequence: Array in OFF_SEQUENCES:
		var message: String = _off_and_back(sequence)
		if message != "":
			return "%s: %s" % [" then ".join(sequence), message]
	return ""


func _off_and_back(sequence: Array) -> String:
	var main: Node = _main_in_meltdown()
	var session: LocalSession = main.get("session")
	var panel: StatusPanel = main.get("status_panel")
	var message: String = ""
	if not session.sim.reactor.destroyed or session.sim.reactor.meltdown_ticks_left <= 0:
		message = "the meltdown did not start"
	elif session.sim.outcome() != ExitRule.Outcome.RUNNING:
		message = "the run ended before the headset came off: %s" % session.sim.outcome()
	var tick: int = session.sim.tick
	var left: int = session.sim.reactor.meltdown_ticks_left
	var hull: float = session.sim.ships[0].hull
	var hash_before: int = session.sim.state_hash()
	var shots: Array[Vector3] = _shots(session)
	var countdown: String = str(panel.texts().get(StatusPanel.MELTDOWN_NAME, ""))
	for handler: String in sequence:
		main.call(handler)
	# A runtime may keep sending frames with the headset off, or send none and
	# report the whole time away on the next one: both, past the countdown.
	_frames(main, 72 * 5, FRAME)
	_frames(main, int(AWAY_SECONDS), 1.0)
	main.call("advance_frame", AWAY_SECONDS)
	if message == "" and session.sim.tick != tick:
		message = "the tick ran from %d to %d with the headset off" % [tick, session.sim.tick]
	elif message == "" and session.sim.reactor.meltdown_ticks_left != left:
		message = "the countdown ran from %d to %d ticks" % [left, session.sim.reactor.meltdown_ticks_left]
	elif message == "" and (session.sim.ships[0].hull != hull or session.sim.state_hash() != hash_before):
		message = "the simulation changed: hull %f to %f" % [hull, session.sim.ships[0].hull]
	elif message == "" and _shots(session) != shots:
		message = "shots in flight moved"
	elif message == "" and str(panel.texts().get(StatusPanel.MELTDOWN_NAME, "")) != countdown:
		message = "the panel's countdown changed to %s" % panel.texts().get(StatusPanel.MELTDOWN_NAME, "")
	# Back on: the runtime passes through visible to focus.
	main.call("on_session_visible")
	main.call("on_session_focussed")
	main.call("advance_frame", AWAY_SECONDS)
	if message == "" and session.sim.tick - tick > 1:
		message = "the frame back ran %d ticks" % (session.sim.tick - tick)
	elif message == "" and session.sim.outcome() != ExitRule.Outcome.RUNNING:
		message = "the run ended while the headset was off: %s" % session.sim.outcome()
	_frames(main, 72, FRAME)
	if message == "" and session.sim.reactor.meltdown_ticks_left >= left:
		message = "the countdown did not run again after the headset came back"
	main.free()
	return message


## Between the call that pauses and the next frame no tick can run: the
## window in which fire, debris or robots could still take the hull is only
## what the runtime takes to report the headset off, never a frame of ours.
func test_no_tick_runs_after_the_pausing_call() -> String:
	var main: Node = _main_in_meltdown()
	var session: LocalSession = main.get("session")
	for handler: String in ["on_session_visible", "on_session_loss_pending", "on_session_stopping"]:
		main.call("on_session_focussed")
		_frames(main, 3, FRAME)
		var tick: int = session.sim.tick
		main.call(handler)
		main.call("advance_frame", 1.0)
		if session.sim.tick != tick:
			main.free()
			return "%s let the next frame run %d ticks" % [handler, session.sim.tick - tick]
	main.free()
	return ""

