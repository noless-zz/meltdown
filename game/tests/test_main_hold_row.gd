extends RefCounted

## The status panel's hold row is fed from the session (#316, SLV-1, MP-2):
## empty at the start, the part's id once the ship has flown through it, and
## empty again once the ship has slotted it, from the part catalogue the main
## scene's session carries (#320). For two seconds after each it says what
## happened instead (#605), for the look's message time (#1210).

## Frames at 90 Hz that outlast the look's message time.
static func _past_message_frames() -> int:
	return ceili(float(StatusPanelLook.load_file()["message_seconds"]) * 90.0) + 20


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
	_fly(main, _past_message_frames(), ShipInput.new())
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
	_fly(main, _past_message_frames(), ShipInput.new())
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


func test_the_weapon_rows_name_every_primary_slot() -> String:
	var main: Node = _main()
	_fly(main, 2, ShipInput.new())
	var panel: StatusPanel = main.get("status_panel")
	var session: LocalSession = main.get("session")
	var ship: ShipState = session.current_ship()
	var names: Array[String] = CombatWiring.weapon_names(ship)
	var shown: Array[String] = []
	for slot: int in names.size():
		shown.append(String(panel.texts()[StatusPanelWeaponRows.node_name(slot)]))
	main.free()
	for slot: int in names.size():
		var want: String = StatusPanelWeaponRows.row_text(slot, names[slot], names[slot] != "")
		if shown[slot] != want:
			return "slot %d reads %s, not %s" % [slot + 1, shown[slot], want]
	return ""


## #1210: the owner's needle gun went into the empty second slot and showed
## nowhere. On the very frame the slot fills, its row names it and carries
## the mark, as every filled slot fires (#1261).
func test_a_slotted_part_shows_on_its_row_on_the_frame_it_is_slotted() -> String:
	var main: Node = _main()
	var id: String = _take_first_part(main)
	var session: LocalSession = main.get("session")
	var panel: StatusPanel = main.get("status_panel")
	var slot: ShipInput = ShipInput.new()
	slot.slot_held = true
	var frame_ids: Array[String] = []
	var rows: Array[String] = []
	for frame: int in 6:
		_fly(main, 1, slot)
		frame_ids = session.current_ship().primary_ids.duplicate()
		if frame_ids.has(id):
			rows = [String(panel.texts()[StatusPanelWeaponRows.node_name(0)]),
				String(panel.texts()[StatusPanelWeaponRows.node_name(1)])]
			break
	var ship: ShipState = session.current_ship()
	var names: Array[String] = CombatWiring.weapon_names(ship)
	main.free()
	if id == "" or rows.is_empty():
		return "part %s was not slotted within 6 frames (%s)" % [id, frame_ids]
	var at: int = frame_ids.find(id)
	if rows[at] != StatusPanelWeaponRows.row_text(at, names[at], true):
		return "on the slotting frame row %d reads %s" % [at + 1, rows[at]]
	if not rows[at].begins_with(StatusPanelWeaponRows.FIRE_MARK):
		return "the fire mark is not on row %d: %s" % [at + 1, rows]
	return ""
