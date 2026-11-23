extends RefCounted

## The slot popup in the main scene (#1263, decision record 0011; SLV-1,
## CMF-8, ARC-3, MP-2): with both guns full a click and a flick replace a gun
## through `ShipInput.slot_choice` alone, the ship does not turn while the
## stick chooses, and the mine keeps running.

const FRAME: float = 1.0 / 90.0
const WEAPONS: String = "res://data/weapons/%s.json"


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


static func _values(right_stick: Vector2 = Vector2.ZERO, buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = right_stick
	values["buttons"] = buttons
	return values


static func _frame(main: Node, values: Dictionary) -> void:
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


static func _weapon(id: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS % id))


## Arms the session's ship with two guns and puts a third part in its hold.
static func _arm(session: LocalSession) -> void:
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon", _weapon("pulse_cannon"))
	loadout.set_slot("primary", 1, "needle_gun", _weapon("needle_gun"))
	session.sim.equip(loadout)
	var parts: Dictionary = {}
	for id: String in ["pulse_cannon", "needle_gun", "arc_lance"]:
		parts[id] = _weapon(id)
	session.sim.set_parts(parts)
	session.sim.ships[0].hold.append("arc_lance")
	session.reset_ship_snapshots()


func test_a_click_and_a_flick_right_replace_the_right_gun_without_turning() -> String:
	var main: Node = _main()
	var session: LocalSession = main.get("session")
	_arm(session)
	var combat: CombatWiring = main.get("combat")
	var start_tick: int = session.sim.tick
	_frame(main, _values(Vector2.ZERO, {"right_stick_click": true}))
	_frame(main, _values())
	var problem: String = ""
	if not combat.slot_popup_input.is_open:
		problem = "the click did not open the popup"
	# A half push past the dead zone would turn the ship if the popup let it.
	for i: int in 30:
		_frame(main, _values(Vector2(0.4, 0.4)))
	var turned: float = session.current_ship().orientation.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)
	if problem == "" and not is_zero_approx(turned):
		problem = "the ship turned %.4f rad while the stick chose" % turned
	if problem == "" and session.sim.tick <= start_tick:
		problem = "the mine did not run while the popup was open"
	_frame(main, _values())
	for i: int in 6:
		_frame(main, _values(Vector2(1.0, 0.0)))
	var ship: ShipState = session.sim.ships[0]
	if problem == "" and (ship.primary_ids[0] != "arc_lance" or ship.primary_ids[1] != "needle_gun"):
		problem = "a flick right left the slots %s" % [ship.primary_ids]
	if problem == "" and not ship.hold.is_empty():
		problem = "the part stayed in the hold: %s" % [ship.hold]
	if problem == "" and combat.slot_popup_input.is_open:
		problem = "the popup stayed open after the choice"
	main.free()
	return problem


func test_a_cancelled_popup_leaves_the_slots_and_the_hold() -> String:
	var main: Node = _main()
	var session: LocalSession = main.get("session")
	_arm(session)
	_frame(main, _values(Vector2.ZERO, {"right_stick_click": true}))
	_frame(main, _values())
	_frame(main, _values(Vector2.ZERO, {"right_stick_click": true}))
	_frame(main, _values())
	for i: int in 6:
		_frame(main, _values(Vector2(0.0, -1.0)))
	var ship: ShipState = session.sim.ships[0]
	var problem: String = ""
	if ship.primary_ids[0] != "pulse_cannon" or ship.primary_ids[1] != "needle_gun" or Array(ship.hold) != ["arc_lance"]:
		problem = "a cancelled popup changed slots %s, hold %s" % [ship.primary_ids, ship.hold]
	main.free()
	return problem
