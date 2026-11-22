extends RefCounted

## Opening the dev menu pauses solo play (#1245, PLT-7, CMF-8, RUN-2, MP-2):
## no tick runs while it is open, closing it resumes with one tick at most,
## the menu and the headset's focus are separate pause reasons that hold in
## either order, a restart keeps only the focus reason, and the m1 suite's
## `menu_pause` step is listed and parsed.

const FRAME: float = 1.0 / 72.0
const SUITE_PATH: String = "res://acceptance/suites/m1.json"


static func _flying_session() -> LocalSession:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000), Vector3i(200, 0, 0)))
	var session: LocalSession = LocalSession.new(7, source)
	for i: int in 50:
		session.advance(1.0 / 90.0)
	return session


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


## A wiring whose open menu pauses `holder[0]`, the session flying now.
static func _wired(holder: Array[LocalSession], hub_open: Callable = Callable()) -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new()
	var session_of: Callable = func() -> LocalSession: return holder[0]
	wiring.attach(null, null, LevelStart.new(), func() -> void: pass, null, null,
		DevMenu.new(DevMenuSpec.load_file(), []), hub_open, session_of)
	return wiring


static func _tap(wiring: DevMenuWiring, at: float) -> void:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)


## A main scene with its rig built, flown for a second so things move.
static func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var thrust: Dictionary = _values()
	thrust["left_stick"] = Vector2(0.0, 1.0)
	for i: int in 72:
		main.call("apply_controls", thrust)
		main.call("advance_frame", FRAME)
	return main


static func _main_tap(main: Node) -> void:
	main.call("apply_controls", _values({ControllerSampler.MENU_BUTTON: true}))
	main.call("advance_frame", FRAME)
	main.call("apply_controls", _values())
	main.call("advance_frame", FRAME)


func test_the_menu_reason_holds_every_tick_and_resumes_with_one() -> String:
	var session: LocalSession = _flying_session()
	var tick: int = session.sim.tick
	var state_hash: int = session.sim.state_hash()
	DevMenuPause.hold(session, true)
	if not session.paused or not session.paused_by(LocalSession.PAUSE_MENU):
		return "holding the menu reason did not pause the session"
	if session.paused_by(LocalSession.PAUSE_FOCUS):
		return "the menu reason also set the focus reason"
	var ran: int = 0
	for i: int in 600:
		ran += session.advance(1.0 / 90.0)
	ran += session.advance(30.0)
	if ran != 0 or session.sim.tick != tick or session.sim.state_hash() != state_hash:
		return "the open menu ran %d ticks to tick %d" % [ran, session.sim.tick]
	DevMenuPause.hold(session, false)
	var first: int = session.advance(30.0)
	if session.paused or first != 1:
		return "closing ran %d ticks on a 30 s frame (paused %s); wanted one" % [first, session.paused]
	return ""


## Headset off with the menu open, back on, then the menu closes.
func test_focus_back_with_the_menu_open_stays_paused_until_it_closes() -> String:
	var session: LocalSession = _flying_session()
	DevMenuPause.hold(session, true)
	session.paused = true
	session.paused = false
	var tick: int = session.sim.tick
	if not session.paused or session.advance(1.0) != 0 or session.sim.tick != tick:
		return "focus returning resumed a session the menu still holds"
	DevMenuPause.hold(session, false)
	if session.paused or session.advance(1.0) != 1:
		return "closing the menu after focus returned did not resume with one tick"
	return ""


## Menu open, headset off, the menu closes, then the headset goes back on.
func test_closing_the_menu_without_focus_stays_paused_until_focus_returns() -> String:
	var session: LocalSession = _flying_session()
	DevMenuPause.hold(session, true)
	session.paused = true
	DevMenuPause.hold(session, false)
	var tick: int = session.sim.tick
	if not session.paused or session.advance(1.0) != 0 or session.sim.tick != tick:
		return "closing the menu resumed a session without focus"
	session.paused = false
	if session.paused or session.advance(1.0) != 1:
		return "focus returning after the menu closed did not resume with one tick"
	return ""


func test_the_wiring_pauses_while_the_menu_is_open_and_the_hub_closes_it() -> String:
	var holder: Array[LocalSession] = [_flying_session()]
	var hub: Array[bool] = [false]
	var wiring: DevMenuWiring = _wired(holder, func() -> bool: return hub[0])
	var result: String = ""
	_tap(wiring, 1.0)
	if not wiring.is_open() or not holder[0].paused_by(LocalSession.PAUSE_MENU):
		result = "opening the menu did not pause (open %s)" % wiring.is_open()
	if result == "":
		_tap(wiring, 2.0)
		if wiring.is_open() or holder[0].paused:
			result = "closing the menu left the session paused"
	if result == "":
		_tap(wiring, 3.0)
		hub[0] = true
		wiring.read(_values(), 3.5)
		if wiring.is_open() or holder[0].paused:
			result = "the hub closed the menu but the session stayed paused"
	wiring.menu.free()
	return result


func test_a_new_session_is_paused_on_the_next_frame_while_the_menu_stays_open() -> String:
	var holder: Array[LocalSession] = [_flying_session()]
	var wiring: DevMenuWiring = _wired(holder)
	_tap(wiring, 1.0)
	holder[0] = _flying_session()
	wiring.read(_values(), 1.5)
	var paused: bool = holder[0].paused_by(LocalSession.PAUSE_MENU)
	wiring.menu.free()
	return "" if paused else "the open menu did not pause the session that replaced the old one"


func test_in_main_the_open_menu_holds_the_simulation_and_the_view() -> String:
	var main: Node = _main()
	_main_tap(main)
	var wiring: DevMenuWiring = main.get("dev_menu")
	var session: LocalSession = main.get("session")
	var result: String = ""
	if not wiring.is_open() or not session.paused:
		result = "a tap through main.gd did not open the menu and pause (open %s)" % wiring.is_open()
	var tick: int = session.sim.tick
	var state_hash: int = session.sim.state_hash()
	var pose: Transform3D = AcceptancePauseCheck.world_pose(main)
	for i: int in 120:
		if result != "":
			break
		main.call("apply_controls", _values())
		main.call("advance_frame", FRAME)
		var moved: Transform3D = AcceptancePauseCheck.world_pose(main)
		if session.sim.tick != tick or session.sim.state_hash() != state_hash:
			result = "frame %d with the menu open ran the simulation to tick %d" % [i, session.sim.tick]
		elif moved.origin.distance_to(pose.origin) > AcceptancePauseCheck.POSE_EPSILON:
			result = "frame %d with the menu open moved the view" % i
	if result == "":
		main.call("apply_controls", _values({ControllerSampler.MENU_BUTTON: true}))
		main.call("apply_controls", _values())
		main.call("advance_frame", 2.0)
		if wiring.is_open() or session.paused or session.sim.tick != tick + 1:
			result = "the frame after closing flew to tick %d from %d (open %s)" % [session.sim.tick, tick,
				wiring.is_open()]
	main.free()
	return result


func test_in_main_focus_and_menu_hold_in_either_order() -> String:
	var main: Node = _main()
	var result: String = ""
	# Headset off with the menu open and back on: paused until the menu closes.
	_main_tap(main)
	main.call("on_session_visible")
	main.call("on_session_focussed")
	var session: LocalSession = main.get("session")
	var tick: int = session.sim.tick
	main.call("apply_controls", _values())
	main.call("advance_frame", FRAME)
	if session.sim.tick != tick:
		result = "focus returning with the menu open flew the ship"
	_main_tap(main)
	if result == "" and session.paused:
		result = "closing the menu with focus back left the game paused"
	# Menu open, headset off, menu closed: paused until focus returns.
	if result == "":
		_main_tap(main)
		main.call("on_session_visible")
		_main_tap(main)
		tick = session.sim.tick
		main.call("advance_frame", FRAME)
		if session.sim.tick != tick or not session.paused:
			result = "closing the menu without focus flew the ship"
	if result == "":
		main.call("on_session_focussed")
		main.call("advance_frame", 1.0)
		if session.paused or session.sim.tick != tick + 1:
			result = "focus returning after the menu closed flew %d ticks" % (session.sim.tick - tick)
	main.free()
	return result


func test_a_restart_keeps_the_focus_pause_but_not_the_menus() -> String:
	var main: Node = _main()
	_main_tap(main)
	main.call("on_session_visible")
	main.call("restart_level")
	var session: LocalSession = main.get("session")
	var result: String = ""
	if not session.paused_by(LocalSession.PAUSE_FOCUS):
		result = "the restarted session lost the focus pause"
	elif session.paused_by(LocalSession.PAUSE_MENU):
		result = "the restart copied the menu's pause into the new session"
	main.free()
	return result


func test_the_m1_menu_pause_step_is_listed() -> String:
	var found: AcceptanceStep = null
	var focus: AcceptanceStep = null
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == "menu_pause":
			found = step
		elif step.id == "focus_pause":
			focus = step
	if found == null or focus == null:
		return "m1 lacks menu_pause or focus_pause"
	if found.pause_by != AcceptancePauseCheck.BY_MENU or focus.pause_by != AcceptancePauseCheck.BY_FOCUS:
		return "menu_pause pauses by %s, focus_pause by %s" % [found.pause_by, focus.pause_by]
	if found.pause_seconds * 60.0 != 120.0 or found.expected_hash != focus.expected_hash:
		return "menu_pause holds %s s and expects %d" % [found.pause_seconds, found.expected_hash]
	return ""


func test_a_bad_pause_by_is_refused_naming_the_field() -> String:
	var base: String = "{\"name\": \"x\", \"steps\": [{\"id\": \"p\", " \
		+ "\"replay\": \"res://acceptance/replays/basic_flight.replay\", " \
		+ "\"checks\": [\"held_while_paused\"], \"pause_at_tick\": 10, \"pause_seconds\": 1%s}]}"
	var bad: AcceptanceSuite = AcceptanceSuite.parse_json(base % ", \"pause_by\": \"hub\"")
	if bad.error.find("steps[0].pause_by") < 0:
		return "pause_by hub gave '%s'" % bad.error
	var good: AcceptanceSuite = AcceptanceSuite.parse_json(base % ", \"pause_by\": \"menu\"")
	if good.error != "" or good.steps[0].pause_by != AcceptancePauseCheck.BY_MENU:
		return "pause_by menu gave '%s'" % good.error
	return ""


## The m1 step passes in the main scene: 120 frames held with the menu's
## pause reason, flight on from the next tick, basic_flight's own hash.
func test_the_m1_menu_pause_step_passes_headless() -> String:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == "menu_pause":
			only.steps.append(step)
	if only.steps.is_empty():
		return "m1 has no step menu_pause"
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup((load("res://main.tscn") as PackedScene).instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < 3000:
		runner.process_frame()
		frames += 1
	var text: String = "\n".join(runner.messages)
	var measured: Dictionary = {}
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			measured = entry["measurements"]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var code: int = runner.exit_code
	runner.main.free()
	runner.free()
	if code != AcceptanceRunner.EXIT_PASS:
		return "exit %d: %s" % [code, text]
	if int(measured.get("paused_frames", 0)) != 120 or int(measured.get("resume_tick", -1)) != 301:
		return "measured %s" % measured
	return ""
