extends RefCounted

## Meltdown debris and the paused reactor in the main scene (#422, RUN-4,
## CMF-8, PLT-7, MP-2): the debris view gets plain copies, shows nothing solid
## before the reactor dies, shows an entry solid at its place once it has
## fallen and a held entry as held; a level without debris gets no view; a
## paused session freezes the reactor view; and the state hash is the same with
## or without the wiring.

const TICK: float = 1.0 / 60.0
## Two entries in G2's side room (box 3), off the escape route: the first falls
## half a second into the meltdown, the second a second in.
const TWO_DEBRIS: Array = [
	{"position": [20.0, -32.0, -72.0], "radius": 1.0, "after_seconds": 0.5},
	{"position": [23.0, -32.0, -72.0], "radius": 1.0, "after_seconds": 1.0},
]


## The wiring with its frame work switched off, for the run without it.
class NoWiring:
	extends MeltdownWiring

	func update(_session: LocalSession, _panel: StatusPanel) -> void:
		pass


func _main(level_name: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if level_name != "":
		main.call("use_level", LevelSwitch.path_for(level_name))
	main.call("_ready")
	return main


## G2 with `TWO_DEBRIS` given before the first tick, as a level with debris.
func _g2_with_debris() -> Node:
	var main: Node = _main("g2")
	(main.get("session") as LocalSession).sim.set_debris(MeltdownDebris.parse(TWO_DEBRIS))
	return main


func _ticks(main: Node, ticks: int) -> void:
	for i: int in ticks:
		main.call("advance_frame", TICK)


func _session(main: Node) -> LocalSession:
	return main.get("session") as LocalSession


func _wiring(main: Node) -> MeltdownWiring:
	return main.get("meltdown") as MeltdownWiring


func _destroy_reactor(main: Node) -> void:
	var session: LocalSession = _session(main)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)


func _debris_views(main: Node) -> Array[DebrisView]:
	var views: Array[DebrisView] = []
	for child: Node in main.get_children():
		if child is DebrisView:
			views.append(child as DebrisView)
	return views


func test_debris_snapshot_is_plain_arrays_and_empty_for_null() -> String:
	var empty: Dictionary = SessionSnapshots.debris(null)
	for key: String in [SessionSnapshots.DEBRIS_POSITIONS, SessionSnapshots.DEBRIS_RADII,
			SessionSnapshots.DEBRIS_SOLID, SessionSnapshots.DEBRIS_HELD, SessionSnapshots.DEBRIS_SECONDS]:
		if not empty.has(key) or not (empty[key] as Array).is_empty():
			return "the snapshot of no debris has a non-empty or missing %s" % key
	var source: MeltdownDebris = MeltdownDebris.parse(TWO_DEBRIS)
	var copy: Dictionary = SessionSnapshots.debris(source)
	var positions: Array[Vector3] = copy[SessionSnapshots.DEBRIS_POSITIONS]
	var radii: Array[float] = copy[SessionSnapshots.DEBRIS_RADII]
	var seconds: Array[float] = copy[SessionSnapshots.DEBRIS_SECONDS]
	if positions.size() != 2 or not positions[1].is_equal_approx(Vector3(23.0, -32.0, -72.0)):
		return "the snapshot's positions are %s" % [positions]
	if not is_equal_approx(radii[0], 1.0):
		return "the snapshot's first radius is %.3f" % radii[0]
	if not is_inf(seconds[0]):
		return "with the reactor alive the first entry falls in %.3f s" % seconds[0]
	(copy[SessionSnapshots.DEBRIS_SOLID] as Array).fill(true)
	(copy[SessionSnapshots.DEBRIS_HELD] as Array).fill(true)
	positions[0] = Vector3.ZERO
	if source.is_solid(0) or source.is_skipped(0) or source.position(0) == Vector3.ZERO:
		return "writing to the snapshot changed the simulation's debris"
	return ""


func test_seconds_until_solid_count_down_from_the_reactor_death() -> String:
	var source: MeltdownDebris = MeltdownDebris.parse(TWO_DEBRIS)
	source.elapsed_ticks = 10
	var seconds: Array[float] = SessionSnapshots.debris(source)[SessionSnapshots.DEBRIS_SECONDS]
	if not is_equal_approx(seconds[0], 20.0 / 60.0) or not is_equal_approx(seconds[1], 50.0 / 60.0):
		return "10 ticks in, the entries fall in %s s" % [seconds]
	source.elapsed_ticks = 30
	seconds = SessionSnapshots.debris(source)[SessionSnapshots.DEBRIS_SECONDS]
	if seconds[0] != 0.0:
		return "a fallen entry still falls in %.3f s" % seconds[0]
	source.skipped[1] = true
	seconds = SessionSnapshots.debris(source)[SessionSnapshots.DEBRIS_SECONDS]
	if not is_inf(seconds[1]):
		return "a held entry falls in %.3f s" % seconds[1]
	return ""


func test_nothing_is_solid_before_the_reactor_dies() -> String:
	var main: Node = _g2_with_debris()
	_ticks(main, 120)
	var views: Array[DebrisView] = _debris_views(main)
	var problem: String = ""
	if views.size() != 1 or _wiring(main).debris_view != views[0]:
		problem = "the main scene has %d debris views" % views.size()
	elif views[0].entry_count() != 2:
		problem = "the debris view has %d entries" % views[0].entry_count()
	else:
		for index: int in 2:
			if views[0].entry_state(index) != DebrisView.EntryState.HIDDEN:
				problem = "entry %d shows before the reactor died" % index
	main.free()
	return problem


func test_the_first_entry_is_solid_at_its_place_after_it_falls() -> String:
	var main: Node = _g2_with_debris()
	_ticks(main, 1)
	_destroy_reactor(main)
	_ticks(main, 31)  # Entry 0 is solid 30 ticks after the death, entry 1 after 60.
	var view: DebrisView = _wiring(main).debris_view
	var problem: String = ""
	if view == null:
		problem = "no debris view after the reactor died"
	elif view.entry_state(0) != DebrisView.EntryState.SOLID:
		problem = "the first entry is in state %d, not solid" % view.entry_state(0)
	elif not view.entry(0).position.is_equal_approx(_session(main).sim.debris.position(0)):
		problem = "the first entry is drawn at %s" % view.entry(0).position
	elif view.entry_state(1) == DebrisView.EntryState.SOLID:
		problem = "the second entry is solid before its time"
	main.free()
	return problem


func test_a_skipped_entry_shows_held() -> String:
	var main: Node = _g2_with_debris()
	_ticks(main, 1)
	_destroy_reactor(main)
	# What `DebrisRouteGuard` does when an entry would seal the last route.
	_session(main).sim.debris.skipped[1] = true
	_ticks(main, 61)
	var view: DebrisView = _wiring(main).debris_view
	var state: int = -1 if view == null else view.entry_state(1)
	main.free()
	if state != DebrisView.EntryState.HELD:
		return "the skipped entry is in state %d, not held" % state
	return ""


func test_a_level_without_debris_gets_no_view() -> String:
	var main: Node = _main()
	_ticks(main, 60)
	var problem: String = ""
	if not _debris_views(main).is_empty() or _wiring(main).debris_view != null:
		problem = "the test tunnel, which has no debris, has a debris view"
	main.free()
	return problem


## Since #439 the session carries G2's own debris entry, so the view appears in
## play without any debris handed in by the test.
func test_g2_gets_its_own_debris_view_in_play() -> String:
	var main: Node = _main("g2")
	_ticks(main, 1)
	var problem: String = ""
	if _session(main).sim.debris == null:
		problem = "G2's session has no debris"
	elif _debris_views(main).size() != 1 or _wiring(main).debris_view == null:
		problem = "G2 with its debris has %d debris views" % _debris_views(main).size()
	main.free()
	return problem


func test_pausing_freezes_the_reactor_view_and_unpausing_resumes_it() -> String:
	var main: Node = _main("g2")
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	var view: ReactorView = _wiring(main).reactor_view
	var problem: String = ""
	if view == null or view.frozen:
		problem = "the reactor view is missing or frozen while flying"
	else:
		session.paused = true
		_ticks(main, 1)
		if not view.frozen:
			problem = "the reactor view is not frozen while paused"
		else:
			session.paused = false
			_ticks(main, 1)
			if view.frozen:
				problem = "the reactor view stays frozen after unpausing"
	main.free()
	return problem


func test_the_state_hash_is_the_same_without_the_wiring() -> String:
	var hashes: Array[int] = []
	for with_wiring: bool in [true, false]:
		var main: Node = _g2_with_debris()
		if not with_wiring:
			main.set("meltdown", NoWiring.new())
		(main.get("input_source") as LatestInputSource).set_input(
			ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE)))
		_ticks(main, 60)
		_destroy_reactor(main)
		_ticks(main, 180)
		hashes.append(_session(main).sim.state_hash())
		main.free()
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the wiring and %d without" % [hashes[0], hashes[1]]
	return ""
