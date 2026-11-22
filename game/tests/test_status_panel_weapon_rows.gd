extends RefCounted

## The panel's weapon rows after the owner's playtest (#1210, SLV-1, CMB-1,
## PLT-2): one row per primary slot with a readable name from the weapon's
## file, the slot that fires marked, a slotted part shown on the frame it is
## slotted, and pickup and slot messages that last the look's time.

const PULSE: String = "res://data/weapons/pulse_cannon.json"
const NEEDLE: String = "res://data/weapons/needle_gun.json"


static func _weapon(path: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(path))


static func _text(panel: StatusPanel, slot: int) -> String:
	return (panel.get_node(StatusPanelWeaponRows.node_name(slot)) as Label3D).text


static func _y(panel: StatusPanel, node_name: String) -> float:
	return (panel.get_node(node_name) as Node3D).position.y


func test_an_empty_second_slot_filled_shows_on_row_two_with_the_mark_on_row_one() -> String:
	var ship: ShipState = ShipState.new()
	ship.primary_slots[0] = _weapon(PULSE)
	ship.primary_ids[0] = "pulse_cannon"
	var panel: StatusPanel = StatusPanel.new()
	panel.show_weapons(CombatWiring.weapon_names(ship), ship.selected_primary)
	var before: String = _text(panel, 1)
	# What `PartSlotting.slot_held` does with a free slot: the part takes it.
	ship.primary_slots[1] = _weapon(NEEDLE)
	ship.primary_ids[1] = "needle_gun"
	panel.show_weapons(CombatWiring.weapon_names(ship), ship.selected_primary)
	var first: String = _text(panel, 0)
	var second: String = _text(panel, 1)
	var first_color: Color = (panel.get_node(StatusPanelWeaponRows.node_name(0)) as Label3D).modulate
	var second_color: Color = (panel.get_node(StatusPanelWeaponRows.node_name(1)) as Label3D).modulate
	panel.free()
	if before != StatusPanelWeaponRows.row_text(1, "", false):
		return "an empty second slot reads %s" % before
	if first != "> 1 Pulse Cannon":
		return "row 1 reads %s, not the marked pulse cannon" % first
	if second != StatusPanelWeaponRows.IDLE_MARK + "2 Needle Gun":
		return "row 2 reads %s right after slotting" % second
	if first_color == second_color:
		return "the slot that fires is not brighter than the other"
	return ""


func test_the_mark_follows_the_selected_slot() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_weapons(["Pulse Cannon", "Needle Gun"] as Array[String], 1)
	var first: String = _text(panel, 0)
	var second: String = _text(panel, 1)
	panel.free()
	if first.begins_with(StatusPanelWeaponRows.FIRE_MARK) or not second.begins_with(StatusPanelWeaponRows.FIRE_MARK):
		return "with slot 2 selected the rows read %s / %s" % [first, second]
	return ""


func test_the_row_count_follows_the_ships_slots_and_the_hold_moves_under_them() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var rows_new: int = panel.weapon_rows.shown_count()
	var hold_two: float = _y(panel, StatusPanel.HOLD_NAME)
	var level_two: float = _y(panel, StatusPanel.LEVEL_NAME)
	panel.show_weapons(["Pulse Cannon", "", "Arc Lance"] as Array[String], 0)
	var rows_three: int = panel.weapon_rows.shown_count()
	var third_y: float = _y(panel, "Weapon3")
	var hold_three: float = _y(panel, StatusPanel.HOLD_NAME)
	var third: String = _text(panel, 2)
	panel.show_weapons(["Pulse Cannon", ""] as Array[String], 0)
	var rows_back: int = panel.weapon_rows.shown_count()
	var hold_back: float = _y(panel, StatusPanel.HOLD_NAME)
	var level_back: float = _y(panel, StatusPanel.LEVEL_NAME)
	panel.free()
	if rows_new != ShipState.new().primary_slots.size():
		return "a new panel has %d weapon rows, not the ship's %d slots" % [rows_new, ShipState.new().primary_slots.size()]
	if rows_three != 3 or third != StatusPanelWeaponRows.IDLE_MARK + "3 Arc Lance":
		return "three slots give %d rows, the third reading %s" % [rows_three, third]
	if not is_equal_approx(hold_three, third_y - StatusPanel.ROW_PITCH):
		return "with three slots the hold is at %.3f, not one row under the third at %.3f" % [hold_three, third_y]
	if rows_back != 2 or not is_equal_approx(hold_back, hold_two) or not is_equal_approx(level_back, level_two):
		return "back to two slots: %d rows, hold %.3f (was %.3f)" % [rows_back, hold_back, hold_two]
	return ""


func test_every_weapon_row_draws_only_with_the_weapon_row() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_weapons(["Pulse Cannon", "", "Arc Lance"] as Array[String], 0)
	var drawn: bool = true
	for label: Label3D in panel.weapon_rows.labels:
		drawn = drawn and label.layers == StatusPanelRowList.DRAWN_LAYERS
	panel.show_rows(["hull"] as Array[String])
	var hidden: bool = true
	for label: Label3D in panel.weapon_rows.labels:
		hidden = hidden and label.layers == 0
	panel.free()
	if not drawn or not hidden:
		return "weapon rows drawn %s with the weapon row, hidden %s without it" % [drawn, hidden]
	return ""


func test_names_come_from_the_weapon_files() -> String:
	var ship: ShipState = ShipState.new()
	ship.primary_slots[0] = _weapon(NEEDLE)
	ship.primary_ids[0] = "needle_gun"
	# A weapon whose file names none: its id made readable, never the raw id.
	ship.primary_slots[1] = WeaponDef.new()
	ship.primary_ids[1] = "slug_thrower"
	var names: Array[String] = CombatWiring.weapon_names(ship)
	ship.primary_slots[1] = null
	var emptied: Array[String] = CombatWiring.weapon_names(ship)
	if names != (["Needle Gun", "Slug Thrower"] as Array[String]):
		return "the slots are named %s" % [names]
	if emptied[1] != "":
		return "an empty slot is named %s" % emptied[1]
	return ""


func test_messages_last_the_look_time_and_a_newer_one_replaces_at_once() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	if not is_equal_approx(float(look["message_seconds"]), 3.0) \
			or not is_equal_approx(float(StatusPanelLook.FALLBACK["message_seconds"]), 3.0):
		return "the message time is %s s, built-in %s s, not 3" % [look["message_seconds"],
			StatusPanelLook.FALLBACK["message_seconds"]]
	var panel: StatusPanel = StatusPanel.new()
	panel.show_hold("needle_gun")
	panel.show_hold_message(HoldMessages.PICKED_UP % "needle_gun")
	panel.advance(2.5)
	var late: String = String(panel.texts()[StatusPanel.HOLD_NAME])
	panel.show_hold_message(HoldMessages.SLOTTED % "needle_gun")
	var replaced: String = String(panel.texts()[StatusPanel.HOLD_NAME])
	var restarted: float = panel.hold_message_seconds_left()
	panel.advance(3.1)
	var after: String = String(panel.texts()[StatusPanel.HOLD_NAME])
	panel.free()
	if late != "Picked up: needle_gun":
		return "2.5 s after a pickup the row reads %s" % late
	if replaced != "Slotted needle_gun" or not is_equal_approx(restarted, 3.0):
		return "a newer message reads %s with %.2f s left" % [replaced, restarted]
	if after != "Hold needle_gun":
		return "after the message time the row reads %s" % after
	return ""


func test_the_panel_never_changes_the_ship() -> String:
	var ship: ShipState = ShipState.new()
	ship.primary_slots[0] = _weapon(PULSE)
	ship.primary_ids[0] = "pulse_cannon"
	var before: int = ship.state_hash()
	var panel: StatusPanel = StatusPanel.new()
	for frame: int in 10:
		panel.show_weapons(CombatWiring.weapon_names(ship), ship.selected_primary)
	panel.free()
	if ship.state_hash() != before:
		return "showing the weapon rows changed the ship"
	return ""
