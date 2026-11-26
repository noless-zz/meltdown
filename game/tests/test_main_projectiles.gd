extends RefCounted

## The main scene starts armed from the shipped loadout and draws the
## simulation's projectiles (#189, CMB-1, MP-2, LGT-1). A separate file because
## `test_main_scene.gd` would pass about 300 lines.

const SHIP_FILE: String = "res://data/ships/default_ship.json"
## 0.4 s of frames at 90 Hz runs 24 ticks. At 4 shots/s (#603) every bolt the
## main scene fired had hit the wall by tick 30, so the check stops while the
## latest is still in flight.
const TICKS_OF_FIRE: int = 24
const FRAMES_OF_FIRE: int = 36


## The real main scene, readied as at start-up, with the right trigger held.
## Outside the tree no `_ready` runs by itself; call them in tree order.
func _main_firing() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var fire: ShipInput = ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, true)
	(main.get("input_source") as LatestInputSource).set_input(fire)
	return main


func _fly(main: Node, frames: int) -> void:
	for i: int in frames:
		main.call("advance_frame", 1.0 / 90.0)


func _visible_bolts(view: ProjectileView) -> int:
	var shown: int = 0
	for index: int in view.bolt_count():
		if view.bolt(index).visible:
			shown += 1
	return shown


func test_main_scene_starts_with_the_shipped_loadout() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var session: LocalSession = main.get("session")
	var ship: ShipState = session.sim.ships[0]
	var weapon: WeaponDef = ship.primary_slots[0]
	var recorded: ShipLoadout = session.replay.loadout
	main.free()
	if weapon == null:
		return "primary slot 1 is empty in the main scene"
	if ship.primary_slots[1] != null or ship.secondary_slots[0] != null or ship.secondary_slots[1] != null:
		return "a slot other than primary 1 holds a weapon"
	if recorded == null or recorded.primary_ids[0] != "pulse_cannon":
		return "the replay does not record the pulse cannon"
	return ""


func test_holding_fire_shows_one_bolt_per_projectile() -> String:
	var main: Node = _main_firing()
	_fly(main, FRAMES_OF_FIRE)
	var session: LocalSession = main.get("session")
	var view: ProjectileView = main.get_node_or_null(ProjectileView.NODE_NAME) as ProjectileView
	var ticks: int = session.sim.tick
	var in_flight: int = session.sim.projectiles.size()
	var found: bool = view != null and view.get_parent() == main
	var shown: int = _visible_bolts(view) if found else -1
	main.free()  # Frees the view too, so it compares equal to null from here.
	if not found:
		return "no ProjectileView directly under the main scene"
	if ticks != TICKS_OF_FIRE:
		return "%d frames ran %d ticks" % [FRAMES_OF_FIRE, ticks]
	if in_flight == 0:
		return "%d ticks of fire left no projectile in flight" % TICKS_OF_FIRE
	if shown != in_flight:
		return "%d bolts shown for %d projectiles" % [shown, in_flight]
	return ""


func test_energy_readout_drops_while_firing() -> String:
	var main: Node = _main_firing()
	var panel: StatusPanel = main.get("status_panel")
	main.call("update_status_panel", 0.0)
	var before: float = panel.energy_bar_scale()
	_fly(main, FRAMES_OF_FIRE)
	var after: float = panel.energy_bar_scale()
	main.free()
	if after >= before:
		return "energy bar went from %s to %s while firing" % [before, after]
	return ""


func test_showing_projectiles_leaves_the_simulation_alone() -> String:
	var main: Node = _main_firing()
	_fly(main, FRAMES_OF_FIRE)
	var session: LocalSession = main.get("session")
	var hash_before: int = session.sim.state_hash()
	main.call("advance_frame", 0.0)
	var hash_after: int = session.sim.state_hash()
	main.free()
	if hash_before != hash_after:
		return "drawing the projectiles changed the simulation"
	return ""


func test_session_projectiles_are_copies() -> String:
	var session: LocalSession = LocalSession.new(0, _firing_source(), null, LocalSession.load_tuning(SHIP_FILE))
	session.advance(3.0 / 60.0)
	var copies: Array[Projectile] = session.current_projectiles()
	if copies.is_empty() or session.sim.projectiles.is_empty():
		return "no projectile after 3 ticks of fire"
	if is_same(copies, session.sim.projectiles):
		return "current_projectiles() is the simulation's array"
	if is_same(copies[0], session.sim.projectiles[0]):
		return "current_projectiles() holds the simulation's projectile"
	if copies[0].position != session.sim.projectiles[0].position:
		return "the copy is at %s, the projectile at %s" % [copies[0].position, session.sim.projectiles[0].position]
	var hash_before: int = session.sim.state_hash()
	copies[0].position += Vector3(5.0, 0.0, 0.0)
	copies.clear()
	if session.sim.state_hash() != hash_before or session.current_projectiles().size() != 1:
		return "changing the copies changed the session"
	var first: Projectile = session.current_projectiles()[0]
	session.advance(1.0 / 60.0)
	var next: Projectile = session.current_projectiles()[0]
	if not is_same(first, next):
		return "a projectile in flight got a new copy on the next tick"
	if next.position != session.sim.projectiles[0].position:
		return "the copy did not follow the projectile"
	return ""


func test_armed_session_replays_to_the_same_hash() -> String:
	var session: LocalSession = LocalSession.new(7, _firing_source(), TestTunnel.interior_box(),
			LocalSession.load_tuning(SHIP_FILE))
	for frame: int in 30:
		session.advance(1.0 / 60.0)
	var replayed: Sim = Replay.from_text(session.replay.to_text()).run()
	if session.sim.projectiles.is_empty():
		return "30 ticks of fire left no projectile in flight"
	if replayed == null or replayed.state_hash() != session.sim.state_hash():
		return "the saved replay does not reproduce the armed run"
	return ""


func test_unreadable_weapon_flies_unarmed_with_the_file_values() -> String:
	var tuning: ShipTuning = LocalSession.load_tuning(SHIP_FILE, "res://no_such_weapons/")
	if tuning == null:
		return "a missing weapon file threw away the whole ship file"
	if tuning.loadout.is_armed():
		return "the loadout is armed without its weapon file"
	var session: LocalSession = LocalSession.new(0, _firing_source(), null, tuning)
	session.advance(0.5)
	if session.replay.loadout != null or not session.sim.projectiles.is_empty():
		return "an unresolved loadout still armed the ship"
	return ""


func test_point_in_matches_global_positions_outside_the_tree() -> String:
	var root: Node3D = Node3D.new()
	var space: Node3D = Node3D.new()
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	root.add_child(space)
	root.add_child(rig)
	rig.add_child(camera)
	root.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 2.0, 3.0))
	space.transform = Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0.0, -1.0, 0.0))
	rig.transform = Transform3D(Basis(Vector3.UP, 1.1), Vector3(0.0, 0.0, -4.0))
	camera.position = Vector3(0.1, 1.6, 0.0)
	var expected: Vector3 = (root.transform * space.transform).affine_inverse() \
			* (root.transform * rig.transform * camera.transform).origin
	var point: Vector3 = NodePoints.point_in(space, camera)
	root.free()
	if not point.is_equal_approx(expected):
		return "camera at %s, expected %s" % [point, expected]
	return ""


static func _firing_source() -> LatestInputSource:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, true))
	return source
