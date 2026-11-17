extends RefCounted

## The main scene's reactor, meltdown countdown and outcome row (#359, RUN-2,
## RUN-5, MP-2): G2's reactor is drawn where the level puts it, the countdown
## shows only once the reactor is destroyed and drops a second per 60 ticks,
## the outcome row follows the run, and the test tunnel shows none of it.

const TICK: float = 1.0 / 60.0


## The wiring with its frame work switched off, for the run without it.
class NoWiring:
	extends MeltdownWiring

	func update(_session: LocalSession, _panel: StatusPanel) -> void:
		pass


## The main scene with its rig built and `_ready` run, as in play; with
## `level_name`, that level is switched in first, as `--level` does.
func _main(level_name: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if level_name != "":
		main.call("use_level", LevelSwitch.path_for(level_name))
	main.call("_ready")
	return main


## Runs `ticks` frames of exactly one tick each.
func _ticks(main: Node, ticks: int) -> void:
	for i: int in ticks:
		main.call("advance_frame", TICK)


## Destroys the reactor through the simulation, as a killing shot would.
func _destroy_reactor(main: Node) -> void:
	var session: LocalSession = main.get("session")
	session.sim.reactor.apply_damage(session.sim.reactor.hull)


func _reactor_views(main: Node) -> Array[ReactorView]:
	var views: Array[ReactorView] = []
	for child: Node in main.get_children():
		if child is ReactorView:
			views.append(child as ReactorView)
	return views


func _panel(main: Node) -> StatusPanel:
	return main.get("status_panel") as StatusPanel


func _meltdown_text(main: Node) -> String:
	return str(_panel(main).texts().get(StatusPanel.MELTDOWN_NAME, ""))


## What the panel's meltdown row reads with `ticks` left.
func _countdown_text(ticks: int) -> String:
	var whole: int = floori(ticks / 60.0)
	return "Meltdown %d:%02d" % [floori(whole / 60.0), whole % 60]


func test_reactor_snapshot_is_a_copy_and_null_for_null() -> String:
	if SessionSnapshots.reactor(null) != null:
		return "a null reactor gave a copy"
	var source: ReactorState = ReactorState.parse(
		{"position": [1, 2, 3], "radius": 2.5, "hull": 400, "meltdown_seconds": 90})
	source.apply_damage(400.0)
	var copy: ReactorState = SessionSnapshots.reactor(source)
	if copy == source:
		return "the snapshot is the simulation's own reactor"
	if copy.state_hash() != source.state_hash() or copy.position_mm != source.position_mm \
			or copy.radius_mm != source.radius_mm or copy.max_hull != source.max_hull:
		return "the copy differs from its source"
	copy.meltdown_ticks_left = 1
	copy.hull = 99.0
	if source.meltdown_ticks_left != 90 * 60 or source.hull != 0.0:
		return "writing to the copy changed the source"
	return ""


func test_g2_has_one_reactor_view_at_the_level_reactor() -> String:
	var main: Node = _main("g2")
	main.call("advance_frame", 0.0)
	var session: LocalSession = main.get("session")
	var views: Array[ReactorView] = _reactor_views(main)
	var want: Vector3 = session.sim.reactor.position()
	var radius: float = session.sim.reactor.radius()
	var problem: String = ""
	if views.size() != 1:
		problem = "the main scene has %d reactor views" % views.size()
	elif not views[0].position.is_equal_approx(want):
		problem = "the reactor view is at %s, the level's reactor at %s" % [views[0].position, want]
	elif not views[0].visible or not is_equal_approx(views[0].core_radius(), radius):
		problem = "the reactor view is not shown at radius %.2f" % radius
	elif (main.get("meltdown") as MeltdownWiring).reactor_view != views[0]:
		problem = "the wiring does not hold the view in the level"
	main.free()
	return problem


func test_g2_countdown_shows_only_after_the_reactor_dies() -> String:
	var main: Node = _main("g2")
	_ticks(main, 30)
	var hidden_before: bool = not _panel(main).meltdown_visible()
	var outcome_before: bool = _panel(main).outcome_visible()
	_destroy_reactor(main)
	_ticks(main, 1)
	var session: LocalSession = main.get("session")
	var ticks: int = session.sim.reactor.meltdown_ticks_left
	var texts: Array[String] = [_meltdown_text(main)]
	var shown: bool = _panel(main).meltdown_visible()
	for step: int in 2:
		_ticks(main, 60)
		texts.append(_meltdown_text(main))
	var want: Array[String] = []
	for step: int in 3:
		want.append(_countdown_text(ticks - 60 * step))
	var view: ReactorView = (main.get("meltdown") as MeltdownWiring).reactor_view
	var flickers: bool = view != null and view.pulse_period() <= float(view.look()["flicker_period_slow"])
	main.free()
	if not hidden_before:
		return "the meltdown row shows while the reactor lives"
	if outcome_before:
		return "the outcome row shows while the run is running"
	if not shown:
		return "the meltdown row is hidden after the reactor died"
	if ticks <= 120:
		return "the meltdown has only %d ticks" % ticks
	if texts != want:
		return "the countdown read %s, expected %s" % [texts, want]
	if not flickers:
		return "the reactor view does not flicker after the reactor died"
	return ""


func test_escaping_in_g2_shows_escaped() -> String:
	var main: Node = _main("g2")
	_ticks(main, 1)
	# The ship is still at its start, inside the exit: the next tick escapes.
	_destroy_reactor(main)
	_ticks(main, 2)
	var session: LocalSession = main.get("session")
	var outcome: int = session.sim.outcome()
	var visible: bool = _panel(main).outcome_visible()
	var text: String = str(_panel(main).texts().get(StatusPanel.OUTCOME_NAME, ""))
	main.free()
	if outcome != ExitRule.Outcome.ESCAPED:
		return "the run's outcome is %d, not escaped" % outcome
	if not visible or text != StatusPanel.ESCAPED_TEXT:
		return "the outcome row shows '%s' (visible %s)" % [text, visible]
	return ""


func test_a_ship_lost_in_g2_shows_ship_lost() -> String:
	var main: Node = _main("g2")
	var session: LocalSession = main.get("session")
	_ticks(main, 1)
	# Away from the exit, so the countdown runs out with the ship in the level.
	session.sim.ships[0].position += Vector3(0.0, 0.0, -20.0)
	_destroy_reactor(main)
	session.sim.reactor.meltdown_ticks_left = 2
	_ticks(main, 4)
	var outcome: int = session.sim.outcome()
	var text: String = str(_panel(main).texts().get(StatusPanel.OUTCOME_NAME, ""))
	var visible: bool = _panel(main).outcome_visible()
	main.free()
	if outcome != ExitRule.Outcome.LOST:
		return "the run's outcome is %d, not lost" % outcome
	if not visible or text != StatusPanel.LOST_TEXT:
		return "the outcome row shows '%s' (visible %s)" % [text, visible]
	return ""


func test_the_test_tunnel_has_no_reactor_and_hides_both_rows() -> String:
	var main: Node = _main()
	_ticks(main, 120)
	var views: int = _reactor_views(main).size()
	var held: ReactorView = (main.get("meltdown") as MeltdownWiring).reactor_view
	var meltdown_shown: bool = _panel(main).meltdown_visible()
	var outcome_shown: bool = _panel(main).outcome_visible()
	main.free()
	if views != 0 or held != null:
		return "the test tunnel has %d reactor views" % views
	if meltdown_shown or outcome_shown:
		return "the test tunnel shows the meltdown row %s, the outcome row %s" % [
			meltdown_shown, outcome_shown]
	return ""


func test_the_state_hash_is_the_same_without_the_wiring() -> String:
	var hashes: Array[int] = []
	for with_wiring: bool in [true, false]:
		var main: Node = _main("g2")
		if not with_wiring:
			main.set("meltdown", NoWiring.new())
		(main.get("input_source") as LatestInputSource).set_input(
			ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE)))
		_ticks(main, 60)
		_destroy_reactor(main)
		_ticks(main, 180)
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the wiring and %d without" % [hashes[0], hashes[1]]
	return ""
