extends RefCounted

## Box-shaped meltdown debris in the main scene (#479, RUN-4, ARC-3, MP-2,
## CMF-8): a level file with one sphere and one box entry draws a sphere node
## and a slab node at the entries' places and sizes once they fall, neither
## before, freezes the slab while paused, and a sphere-only level draws no slab.

const TICK: float = 1.0 / 60.0
## G2 with its debris replaced: a sphere falling 0.5 s into the meltdown and a
## 2 x 3 x 0.5 m box falling 1 s in, both in the side room off the escape route.
const FIXTURE: String = "res://tests/fixtures/box_debris_level.json"
const SPHERE: int = 0
const BOX: int = 1
const BOX_SIZE: Vector3 = Vector3(2.0, 3.0, 0.5)
## Ticks after the reactor's death until each entry is solid.
const SPHERE_FALL_TICKS: int = 30
const BOX_FALL_TICKS: int = 60


func _main(path: String) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if not main.call("use_level", path):
		main.free()
		return null
	main.call("_ready")
	return main


func _ticks(main: Node, ticks: int) -> void:
	for i: int in ticks:
		main.call("advance_frame", TICK)


func _session(main: Node) -> LocalSession:
	return main.get("session") as LocalSession


func _view(main: Node) -> DebrisView:
	return (main.get("meltdown") as MeltdownWiring).debris_view


func _destroy_reactor(main: Node) -> void:
	var session: LocalSession = _session(main)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)


## The fixture's main scene, one tick in, with the reactor just destroyed.
func _melting() -> Node:
	var main: Node = _main(FIXTURE)
	if main == null:
		return null
	_ticks(main, 1)
	_destroy_reactor(main)
	return main


func test_the_fixture_holds_one_sphere_and_one_box() -> String:
	var main: Node = _main(FIXTURE)
	if main == null:
		return "the fixture level was rejected"
	var debris: MeltdownDebris = _session(main).sim.debris
	var problem: String = ""
	if debris == null or debris.size() != 2:
		problem = "the fixture's session has %s debris" % ("no" if debris == null else str(debris.size()))
	elif debris.is_box(SPHERE) or not debris.is_box(BOX):
		problem = "the fixture's entries are not a sphere then a box"
	main.free()
	return problem


func test_neither_shows_before_the_reactor_dies() -> String:
	var main: Node = _main(FIXTURE)
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, 120)
	var view: DebrisView = _view(main)
	var problem: String = ""
	if view == null or view.entry_count() != 2:
		problem = "the debris view is missing or has the wrong entry count"
	else:
		for index: int in 2:
			if view.entry_state(index) != DebrisView.EntryState.HIDDEN or view.entry(index).visible:
				problem = "entry %d shows before the reactor died" % index
	main.free()
	return problem


func test_a_sphere_node_and_a_slab_node_after_both_fall() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, BOX_FALL_TICKS + 1)
	var view: DebrisView = _view(main)
	var debris: MeltdownDebris = _session(main).sim.debris
	var problem: String = ""
	if view == null:
		problem = "no debris view after the reactor died"
	elif view.entry_is_box(SPHERE) or not view.entry_is_box(BOX):
		problem = "the view does not draw a sphere then a slab"
	elif view.entry_state(SPHERE) != DebrisView.EntryState.SOLID \
			or view.entry_state(BOX) != DebrisView.EntryState.SOLID:
		problem = "after both falls the states are %d and %d" % [view.entry_state(SPHERE), view.entry_state(BOX)]
	elif not view.entry(SPHERE).position.is_equal_approx(debris.position(SPHERE)) \
			or not view.entry(BOX).position.is_equal_approx(debris.position(BOX)):
		problem = "the entries are drawn at %s and %s" % [view.entry(SPHERE).position, view.entry(BOX).position]
	elif not is_equal_approx(view.entry_radius(SPHERE), 1.0):
		problem = "the sphere is drawn with radius %.3f" % view.entry_radius(SPHERE)
	elif not view.entry_size(BOX).is_equal_approx(BOX_SIZE):
		problem = "the slab is drawn %s in size" % view.entry_size(BOX)
	main.free()
	return problem


func test_the_slab_is_not_solid_before_its_fall_tick() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, SPHERE_FALL_TICKS + 1)
	var view: DebrisView = _view(main)
	var problem: String = ""
	if view == null:
		problem = "no debris view after the reactor died"
	elif view.entry_state(SPHERE) != DebrisView.EntryState.SOLID:
		problem = "the sphere is in state %d after its fall" % view.entry_state(SPHERE)
	elif view.entry_state(BOX) == DebrisView.EntryState.SOLID:
		problem = "the slab is solid before its fall tick"
	main.free()
	return problem


func test_pausing_freezes_the_slab() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, SPHERE_FALL_TICKS + 1)
	var view: DebrisView = _view(main)
	var session: LocalSession = _session(main)
	var problem: String = ""
	var before: int = view.entry_state(BOX)
	var elapsed: int = session.sim.debris.elapsed_ticks
	session.paused = true
	_ticks(main, BOX_FALL_TICKS * 2)
	if view.entry_state(BOX) != before or session.sim.debris.elapsed_ticks != elapsed:
		problem = "while paused the slab went from state %d to %d" % [before, view.entry_state(BOX)]
	else:
		session.paused = false
		_ticks(main, BOX_FALL_TICKS)
		if view.entry_state(BOX) != DebrisView.EntryState.SOLID:
			problem = "after unpausing the slab is in state %d, not solid" % view.entry_state(BOX)
	main.free()
	return problem


func test_a_sphere_only_level_draws_no_slab() -> String:
	var main: Node = _main(LevelSwitch.path_for("g2"))
	if main == null:
		return "G2 was rejected"
	_ticks(main, 1)
	_destroy_reactor(main)
	_ticks(main, 60)
	var view: DebrisView = _view(main)
	var problem: String = ""
	if view == null or view.entry_count() == 0:
		problem = "G2 has no debris view"
	else:
		for index: int in view.entry_count():
			if view.entry_is_box(index):
				problem = "G2's sphere entry %d is drawn as a slab" % index
	main.free()
	return problem
