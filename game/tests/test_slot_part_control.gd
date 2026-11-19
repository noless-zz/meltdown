extends RefCounted

## The remappable "slot part" control (#312, SLV-1, PLT-5, CMB-1): the bound
## control sets `ShipInput.slot_held`, the binding lives in the layout files,
## left-handed mode swaps it, the flat build has a key for it, and the labels
## name it. Ends with a scripted flight that picks up a part and slots it.

const WEAPONS: String = "res://data/weapons/%s.json"
const Z: Vector2 = Vector2.ZERO


func _press(mapping: ThumbstickMapping, buttons: Dictionary) -> ShipInput:
	return mapping.map_controls(Z, Z, 0.0, 0.0, 0.0, 0.0, buttons)


func test_right_stick_click_sets_slot_held_and_release_clears_it() -> String:
	for path: String in [ThumbstickMapping.DEFAULT_LAYOUT_FILE, ThumbstickMapping.PAIRED_LAYOUT_FILE]:
		var m: ThumbstickMapping = ThumbstickMapping.from_file(path)
		if m.error != "":
			return "%s rejected: %s" % [path, m.error]
		if not _press(m, {"right_stick_click": true}).slot_held:
			return "%s: right stick click does not set slot_held" % path
		if _press(m, {"right_stick_click": false}).slot_held or _press(m, {}).slot_held:
			return "%s: slot_held stays set after release" % path
		# The other stick click is the label toggle, read outside the mapping.
		if _press(m, {"left_stick_click": true}).slot_held:
			return "%s: left stick click sets slot_held right-handed" % path
	return ""


func test_slot_part_touches_nothing_else() -> String:
	var input: ShipInput = _press(ThumbstickMapping.new(), {"right_stick_click": true})
	if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO \
			or input.afterburner or input.fire_primary or input.reset_to_start:
		return "slotting also moved, boosted or fired: thrust %s turn %s" % [input.thrust_q, input.turn_q]
	return ""


func test_remapping_in_a_layout_file_moves_it() -> String:
	var text: String = FileAccess.get_file_as_string(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	text = text.replace('"slot_part": {"right_stick_click": 1.0}', '"slot_part": {"left_button_upper": 1.0}')
	var m: ThumbstickMapping = ThumbstickMapping.from_json(text)
	if m.error != "":
		return "remapped file rejected: " + m.error
	if m.layout["slot_part"] != {"left_button_upper": 1.0}:
		return "the edit did not reach the layout: %s" % m.layout
	if not _press(m, {"left_button_upper": true}).slot_held:
		return "the remapped control does not slot"
	if _press(m, {"right_stick_click": true}).slot_held:
		return "the old control still slots after the remap"
	return ""


func test_an_unbound_slot_part_never_slots() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout.erase("slot_part")
	var m: ThumbstickMapping = ThumbstickMapping.new(layout)
	for button: String in ThumbstickMapping.BUTTONS:
		if _press(m, {button: true}).slot_held:
			return "%s slots with no slot_part binding" % button
	return ""


func test_left_handed_swaps_it_to_the_left_stick_click() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.new()
	m.left_handed = true
	if not _press(m, {"left_stick_click": true}).slot_held:
		return "left-handed: left stick click does not slot"
	if _press(m, {"right_stick_click": true}).slot_held:
		return "left-handed: right stick click still slots"
	return ""


func test_the_keyboard_key_slots() -> String:
	var keyboard: KeyboardSampler = KeyboardSampler.new()
	var m: ThumbstickMapping = ThumbstickMapping.new()
	if not keyboard.used_keys().has(KeyboardSampler.SLOT_PART_KEY):
		return "the slot key is not among the keys checked each frame"
	var pressed: Array[int] = [KeyboardSampler.SLOT_PART_KEY]
	if not ControllerSampler.map_values(m, keyboard.sample(pressed)).slot_held:
		return "the slot key does not set slot_held"
	var none: Array[int] = []
	if ControllerSampler.map_values(m, keyboard.sample(none)).slot_held:
		return "slot_held set with no key held"
	var fly: Array[int] = [KEY_W, KEY_SPACE, KEY_SHIFT]
	if ControllerSampler.map_values(m, keyboard.sample(fly)).slot_held:
		return "flying and firing keys set slot_held"
	return ""


func test_the_labels_name_it_on_the_bound_control() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.new()
	var right: Dictionary = ControlLabels.for_mapping(m)
	if right.get("right_stick_click", "") != "slot part":
		return "right stick click labelled '%s'" % right.get("right_stick_click", "<none>")
	m.left_handed = true
	var left: Dictionary = ControlLabels.for_mapping(m)
	if left.get("left_stick_click", "") != "slot part" \
			or left.get("right_stick_click", "") != "map (hold)":
		return "left-handed labels: %s" % left
	return ""


## A sim of one ship with the pulse cannon in primary slot 0, the needle gun
## in the part catalogue and a needle gun floating 10 m ahead.
func _sim() -> Sim:
	var sim: Sim = Sim.new(5, 1)
	var cannon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS % "pulse_cannon"))
	var needle: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS % "needle_gun"))
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon", cannon)
	sim.equip(loadout)
	sim.set_parts({"needle_gun": needle})
	sim.salvage.append(SalvageItem.new("needle_gun", Vector3(0.0, 0.0, -10.0), Vector3.ZERO))
	return sim


func _tick(sim: Sim, mapping: ThumbstickMapping, values: Dictionary) -> void:
	var inputs: Array[ShipInput] = [ControllerSampler.map_values(mapping, values)]
	sim.step(inputs)


func test_a_scripted_flight_picks_up_a_part_and_slots_it() -> String:
	var sim: Sim = _sim()
	var ship: ShipState = sim.ships[0]
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	var forward: Dictionary = ControllerSampler.idle_values()
	forward["left_stick"] = Vector2(0.0, 1.0)
	for i: int in 600:
		_tick(sim, mapping, forward)
		if not ship.hold.is_empty():
			break
	if ship.hold.size() != 1 or ship.hold[0] != "needle_gun":
		return "flying through the part left the hold %s" % [ship.hold]
	# Coast a tick with nothing pressed: holding a part must not slot it.
	_tick(sim, mapping, ControllerSampler.idle_values())
	if ship.hold.is_empty():
		return "the part slotted without the control"
	var click: Dictionary = ControllerSampler.idle_values()
	click["buttons"] = {"right_stick_click": true}
	_tick(sim, mapping, click)
	if not ship.hold.is_empty():
		return "hold still %s after the click" % [ship.hold]
	if ship.primary_ids[1] != "needle_gun" or ship.primary_slots[1] != sim.part("needle_gun"):
		return "primary slots %s after the click" % [ship.primary_ids]
	if ship.primary_ids[0] != "pulse_cannon":
		return "the cannon left slot 0: %s" % [ship.primary_ids]
	return ""
