extends RefCounted

## The main scene draws the parts destroyed robots drop, from session copies
## (#287, SLV-1, LGT-1, MP-2).


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, frames: int, input: ShipInput) -> void:
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", 1.0 / 90.0)


## Destroys the session's first robot the way a killing shot would leave it,
## then flies frames until the tick that removes it has run.
func _destroy_first_robot(main: Node) -> void:
	var session: LocalSession = main.get("session")
	session.sim.robots[0].hull = 0.0
	_fly(main, 3, ShipInput.new())


## The salvage nodes shown, in pool order.
func _shown(view: SalvageView) -> Array[MeshInstance3D]:
	var shown: Array[MeshInstance3D] = []
	for index: int in view.node_count():
		if view.node(index).visible:
			shown.append(view.node(index))
	return shown


func test_a_destroyed_robot_shows_one_salvage_node_where_its_part_is() -> String:
	var main: Node = _main()
	_fly(main, 2, ShipInput.new())
	var view: SalvageView = main.get_node_or_null(SalvageView.NODE_NAME) as SalvageView
	if view == null or view.get_parent() != main:
		main.free()
		return "no SalvageView directly under the main scene"
	var before: int = _shown(view).size()
	_destroy_first_robot(main)
	# A frame that leaves part of a tick over, so the blend is not trivial.
	main.call("advance_frame", 1.0 / 90.0)
	var session: LocalSession = main.get("session")
	var previous: Array[SalvageItem] = session.previous_salvage()
	var current: Array[SalvageItem] = session.current_salvage()
	var fraction: float = session.interpolation_fraction
	var shown: Array[MeshInstance3D] = _shown(view)
	var drawn_at: Vector3 = shown[0].position if shown.size() == 1 else Vector3.INF
	main.free()
	if before != 0:
		return "%d salvage nodes shown before any robot was destroyed" % before
	if current.size() != 1:
		return "the session holds %d salvage items, expected 1" % current.size()
	if shown.size() != 1:
		return "%d salvage nodes shown, expected 1" % shown.size()
	var start: SalvageItem = current[0]
	if not previous.is_empty() and SalvageView.is_same_item(previous[0], current[0]):
		start = previous[0]
	var expected: Vector3 = start.position.lerp(current[0].position, fraction)
	if drawn_at.distance_to(expected) > 1e-4:
		return "the part is drawn at %s, its blended position is %s" % [drawn_at, expected]
	return ""


func test_flying_through_the_part_hides_it() -> String:
	var main: Node = _main()
	_destroy_first_robot(main)
	var session: LocalSession = main.get("session")
	var item: Vector3 = session.current_salvage()[0].position
	# Line the ship up 4 m behind the part, nose towards it, and fly on through.
	var ship: ShipState = session.sim.ships[0]
	ship.position = item + Vector3(0.0, 0.0, 4.0)
	ship.velocity = Vector3.ZERO
	_fly(main, 90, ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE)))
	var view: SalvageView = main.get_node(SalvageView.NODE_NAME) as SalvageView
	var shown: int = _shown(view).size()
	var left: int = session.current_salvage().size()
	var hold: Array[String] = session.current_ship().hold.duplicate()
	main.free()
	if left != 0:
		return "the part is still floating after the ship flew through it"
	if hold.size() != 1:
		return "the ship's hold is %s after flying through one part" % [hold]
	if shown != 0:
		return "%d salvage nodes still shown after the part was taken" % shown
	return ""


func test_changing_a_salvage_copy_leaves_the_simulation_alone() -> String:
	var main: Node = _main()
	_destroy_first_robot(main)
	var session: LocalSession = main.get("session")
	var hash_before: int = session.sim.state_hash()
	var copies: Array[SalvageItem] = session.current_salvage()
	var previous: Array[SalvageItem] = session.previous_salvage()
	copies[0].position += Vector3(2.0, 0.0, 0.0)
	copies[0].part_id = "changed"
	if not previous.is_empty():
		previous[0].velocity = Vector3(5.0, 0.0, 0.0)
	copies.clear()
	main.call("advance_frame", 0.0)
	var hash_after: int = session.sim.state_hash()
	var same: bool = is_same(session.current_salvage()[0], session.sim.salvage[0])
	var kept_id: String = session.sim.salvage[0].part_id
	main.free()
	if same:
		return "current_salvage() holds the simulation's item"
	if kept_id == "changed":
		return "changing a copy renamed the simulation's part"
	if hash_before != hash_after:
		return "changing a copy or drawing the salvage changed the simulation"
	return ""


func test_a_fresh_session_has_no_salvage() -> String:
	var session: LocalSession = LocalSession.new()
	if not session.previous_salvage().is_empty() or not session.current_salvage().is_empty():
		return "a session with no robots reports salvage"
	return ""


## The owner could not pick up a part (#600): destroy a robot, stop the ship
## 3.3 m from its part, beyond the old 2.5 m reach, and the shipped salvage
## file has it pulled in and taken, with the hold row naming it.
func test_a_part_three_metres_off_is_taken_and_the_hold_row_names_it() -> String:
	var main: Node = _main()
	_destroy_first_robot(main)
	var session: LocalSession = main.get("session")
	var part: SalvageItem = session.current_salvage()[0]
	var ship: ShipState = session.sim.ships[0]
	ship.position = part.position + Vector3(0.0, 0.0, 3.3)
	ship.velocity = Vector3.ZERO
	_fly(main, 30, ShipInput.new())
	var hold: Array[String] = session.current_ship().hold.duplicate()
	var panel: StatusPanel = main.get("status_panel")
	var row: String = (panel.get_node(StatusPanel.HOLD_NAME) as Label3D).text if panel != null else ""
	main.free()
	if hold != [part.part_id]:
		return "the hold is %s, expected [%s]" % [hold, part.part_id]
	if not row.contains(part.part_id):
		return "the hold row reads '%s'" % row
	return ""
