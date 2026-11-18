extends RefCounted

## Fire among the meltdown debris in the main scene (#499, RUN-4, ARC-3, MP-2,
## CMF-8): a level file with one solid and one fire entry draws a rock node and
## a burning fire node at the entries' places once they fall, neither burning
## before, the fire's flicker follows the session tick and freezes while paused,
## and a level without fire draws no fire node.

const TICK: float = 1.0 / 60.0
## G2 with its debris replaced: a solid sphere falling 0.5 s into the meltdown
## and a fire sphere of radius 1.5 m catching 1 s in, both in the side room off
## the escape route.
const FIXTURE: String = "res://tests/fixtures/fire_debris_level.json"
const SOLID: int = 0
const FIRE: int = 1
const FIRE_RADIUS: float = 1.5
## Ticks after the reactor's death until each entry falls.
const SOLID_FALL_TICKS: int = 30
const FIRE_FALL_TICKS: int = 60


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


## The fixture's main scene, one tick in, with the reactor just destroyed.
func _melting() -> Node:
	var main: Node = _main(FIXTURE)
	if main == null:
		return null
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	return main


## The flicker energy the fire material shows, or -1 when entry `FIRE` has none.
func _fire_energy(view: DebrisView) -> float:
	var material: StandardMaterial3D = view.entry(FIRE).material_override as StandardMaterial3D
	return -1.0 if material == null else material.emission_energy_multiplier


func test_the_fixture_holds_one_solid_and_one_fire() -> String:
	var main: Node = _main(FIXTURE)
	if main == null:
		return "the fixture level was rejected"
	var debris: MeltdownDebris = _session(main).sim.debris
	var problem: String = ""
	if debris == null or debris.size() != 2:
		problem = "the fixture's session has %s debris" % ("no" if debris == null else str(debris.size()))
	elif debris.is_fire(SOLID) or not debris.is_fire(FIRE):
		problem = "the fixture's entries are not a solid then a fire"
	main.free()
	return problem


func test_neither_burns_before_the_fall_ticks() -> String:
	var main: Node = _main(FIXTURE)
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, 120)
	var problem: String = ""
	var view: DebrisView = _view(main)
	if view == null or view.entry_count() != 2:
		problem = "the debris view is missing or has the wrong entry count before the reactor died"
	elif view.entry_state(SOLID) != DebrisView.EntryState.HIDDEN or view.entry_state(FIRE) != DebrisView.EntryState.HIDDEN:
		problem = "with the reactor alive the states are %d and %d" % [view.entry_state(SOLID), view.entry_state(FIRE)]
	if problem == "":
		var session: LocalSession = _session(main)
		session.sim.reactor.apply_damage(session.sim.reactor.hull)
		_ticks(main, FIRE_FALL_TICKS - 2)
		if view.entry_state(FIRE) == DebrisView.EntryState.BURNING:
			problem = "the fire burns before its fall tick"
		elif view.entry_state(SOLID) == DebrisView.EntryState.BURNING:
			problem = "the solid entry is drawn burning"
	main.free()
	return problem


func test_a_rock_node_and_a_fire_node_after_both_fall() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, FIRE_FALL_TICKS + 1)
	var view: DebrisView = _view(main)
	var debris: MeltdownDebris = _session(main).sim.debris
	var problem: String = ""
	if view == null:
		problem = "no debris view after the reactor died"
	elif view.entry_is_fire(SOLID) or not view.entry_is_fire(FIRE):
		problem = "the view does not draw a rock then a fire"
	elif view.entry_state(SOLID) != DebrisView.EntryState.SOLID \
			or view.entry_state(FIRE) != DebrisView.EntryState.BURNING:
		problem = "after both falls the states are %d and %d" % [view.entry_state(SOLID), view.entry_state(FIRE)]
	elif not view.entry(SOLID).visible or not view.entry(FIRE).visible:
		problem = "an entry is hidden after both falls"
	elif not view.entry(SOLID).position.is_equal_approx(debris.position(SOLID)) \
			or not view.entry(FIRE).position.is_equal_approx(debris.position(FIRE)):
		problem = "the entries are drawn at %s and %s" % [view.entry(SOLID).position, view.entry(FIRE).position]
	elif not is_equal_approx(view.entry_radius(FIRE), FIRE_RADIUS):
		problem = "the fire is drawn with radius %.3f" % view.entry_radius(FIRE)
	main.free()
	return problem


func test_the_fire_flicker_follows_the_session_tick() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, FIRE_FALL_TICKS + 1)
	var view: DebrisView = _view(main)
	var session: LocalSession = _session(main)
	var problem: String = ""
	var seen: Dictionary = {}
	for step: int in 20:
		_ticks(main, 3)
		var want: float = DebrisLook.fire_energy_at(view.look(), session.sim.tick)
		var got: float = _fire_energy(view)
		if not is_equal_approx(got, want):
			problem = "at tick %d the fire energy is %.4f, expected %.4f" % [session.sim.tick, got, want]
			break
		seen[snappedf(got, 0.0001)] = true
	if problem == "" and seen.size() < 2:
		problem = "the fire did not flicker over 60 ticks"
	main.free()
	return problem


func test_pausing_freezes_the_fire() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, FIRE_FALL_TICKS + 1)
	var view: DebrisView = _view(main)
	var session: LocalSession = _session(main)
	var problem: String = ""
	var state: int = view.entry_state(FIRE)
	var energy: float = _fire_energy(view)
	var position: Vector3 = view.entry(FIRE).position
	var tick: int = session.sim.tick
	session.paused = true
	for step: int in 30:
		_ticks(main, 3)
		if view.entry_state(FIRE) != state or _fire_energy(view) != energy \
				or view.entry(FIRE).position != position or session.sim.tick != tick:
			problem = "while paused the fire changed (state %d, energy %.4f, tick %d)" \
				% [view.entry_state(FIRE), _fire_energy(view), session.sim.tick]
			break
	if problem == "":
		session.paused = false
		_ticks(main, 3)
		if session.sim.tick == tick or view.entry_state(FIRE) != DebrisView.EntryState.BURNING:
			problem = "after unpausing the fire did not burn on"
	main.free()
	return problem


func test_a_level_without_fire_draws_no_fire() -> String:
	var main: Node = _main(LevelSwitch.path_for("g2"))
	if main == null:
		return "G2 was rejected"
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	_ticks(main, 120)
	var view: DebrisView = _view(main)
	var problem: String = ""
	if view == null or view.entry_count() == 0:
		problem = "G2 has no debris view"
	else:
		for index: int in view.entry_count():
			if view.entry_is_fire(index) or view.entry_state(index) == DebrisView.EntryState.BURNING:
				problem = "G2's entry %d is drawn as fire" % index
	main.free()
	return problem
