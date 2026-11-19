extends RefCounted

## The status panel's hold row is fed from the session (#316, SLV-1, MP-2):
## empty at the start, the part's id once the ship has flown through it, and
## empty again once the ship has slotted it, from the part catalogue the main
## scene's session carries (#320). For two seconds after each it says what
## happened instead (#605).

## Frames at 90 Hz that outlast the look's message time.
const PAST_MESSAGE_FRAMES: int = 200


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, frames: int, input: ShipInput) -> void:
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", 1.0 / 90.0)


func _hold_text(main: Node) -> String:
	var panel: StatusPanel = main.get("status_panel")
	return (panel.get_node(StatusPanel.HOLD_NAME) as Label3D).text


## Destroys the first robot, then flies the ship through the part it drops.
## Returns the part's id, or "" if no part was dropped.
func _take_first_part(main: Node) -> String:
	var session: LocalSession = main.get("session")
	session.sim.robots[0].hull = 0.0
	_fly(main, 3, ShipInput.new())
	if session.current_salvage().is_empty():
		return ""
	var item: SalvageItem = session.current_salvage()[0]
	var ship: ShipState = session.sim.ships[0]
	ship.position = item.position + Vector3(0.0, 0.0, 4.0)
	ship.velocity = Vector3.ZERO
	_fly(main, 90, ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE)))
	return item.part_id


func test_the_hold_row_reads_empty_at_the_start() -> String:
	var main: Node = _main()
	_fly(main, 2, ShipInput.new())
	var shown: String = _hold_text(main)
	main.free()
	if shown != StatusPanel.HOLD_EMPTY:
		return "the hold row reads %s at the start" % shown
	return ""


func test_the_hold_row_names_a_part_flown_through() -> String:
	var main: Node = _main()
	var id: String = _take_first_part(main)
	var session: LocalSession = main.get("session")
	var hold: Array[String] = session.current_ship().hold.duplicate()
	var message: String = _hold_text(main)
	_fly(main, PAST_MESSAGE_FRAMES, ShipInput.new())
	var shown: String = _hold_text(main)
	main.free()
	if id == "":
		return "the destroyed robot dropped no part"
	if hold != [id]:
		return "the hold is %s after flying through %s" % [hold, id]
	if message != HoldMessages.PICKED_UP % id:
		return "just after the pickup the hold row reads %s" % message
	if shown != "Hold %s" % id:
		return "the hold row reads %s with %s in the hold" % [shown, id]
	return ""


func test_slotting_through_the_input_source_empties_the_hold_row() -> String:
	var main: Node = _main()
	var id: String = _take_first_part(main)
	var held: String = _hold_text(main)
	var slot: ShipInput = ShipInput.new()
	slot.slot_held = true
	_fly(main, 2, slot)
	var session: LocalSession = main.get("session")
	var hold: Array[String] = session.current_ship().hold.duplicate()
	var ids: Array[String] = session.current_ship().primary_ids.duplicate()
	var message: String = _hold_text(main)
	_fly(main, PAST_MESSAGE_FRAMES, ShipInput.new())
	var shown: String = _hold_text(main)
	main.free()
	if not held.contains(id) or id == "":
		return "before slotting the hold row reads %s, not part %s" % [held, id]
	if not message.begins_with(HoldMessages.SLOTTED % id):
		return "just after slotting the hold row reads %s" % message
	if not hold.is_empty():
		return "the hold is %s after slotting" % [hold]
	if not ids.has(id):
		return "%s is not in a primary slot after slotting (%s)" % [id, ids]
	if shown != StatusPanel.HOLD_EMPTY:
		return "the hold row reads %s after slotting" % shown
	return ""


func test_feeding_the_hold_row_leaves_the_simulation_alone() -> String:
	var main: Node = _main()
	_take_first_part(main)
	var session: LocalSession = main.get("session")
	var hash_before: int = session.sim.state_hash()
	var combat: CombatWiring = main.get("combat")
	for i: int in 5:
		combat.update(session, null, main.get("status_panel"))
	var hash_after: int = session.sim.state_hash()
	main.free()
	if hash_before != hash_after:
		return "feeding the hold row changed the simulation"
	return ""


func test_held_part_is_the_first_id_or_empty() -> String:
	var ship: ShipState = ShipState.new()
	var empty: String = CombatWiring.held_part(ship)
	ship.hold.append("needle_gun")
	ship.hold.append("arc_lance")
	var first: String = CombatWiring.held_part(ship)
	if empty != "":
		return "an empty hold gives %s" % empty
	if first != "needle_gun":
		return "a hold of two gives %s, not the first" % first
	return ""


func test_the_weapon_row_names_the_active_primary() -> String:
	var main: Node = _main()
	_fly(main, 2, ShipInput.new())
	var panel: StatusPanel = main.get("status_panel")
	var session: LocalSession = main.get("session")
	var expected: String = CombatWiring.active_weapon(session.current_ship())
	var shown: String = String(panel.texts()[StatusPanel.WEAPON_NAME])
	main.free()
	var want: String = StatusPanel.WEAPON_NONE if expected == "" else "Weapon %s" % expected
	if shown != want:
		return "the weapon row reads %s, not %s" % [shown, want]
	return ""
