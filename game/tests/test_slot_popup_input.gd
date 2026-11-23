extends RefCounted

## The slot popup's input step (#1263, decision record 0011; SLV-1, PLT-5,
## ARC-3): scripted controller states through the mapping give the right
## `slot_choice` and no pitch or yaw while it is open, a click cancels, each
## auto-close case sends nothing, an empty slot slots at once, and left-handed
## mode moves it to the left stick.

const CLICK: Dictionary = {"right_stick_click": true}
const LEFT_CLICK: Dictionary = {"left_stick_click": true}
const RIGHT: Vector2 = Vector2(1.0, 0.0)
const LEFT: Vector2 = Vector2(-1.0, 0.0)
const DOWN: Vector2 = Vector2(0.0, -1.0)
const UP: Vector2 = Vector2(0.0, 1.0)


## A ship copy with both primary slots full and a part in the hold.
static func _full_ship() -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.primary_slots = [WeaponDef.new(), WeaponDef.new()] as Array[WeaponDef]
	ship.primary_ids = ["pulse_cannon", "needle_gun"] as Array[String]
	ship.hold.append("arc_lance")
	return ship


## One frame: the choosing hand's stick at `stick`, `grips` as left and right grip
## (roll), `buttons` pressed, mapped and through `step`.
static func _frame(step: SlotPopupInput, mapping: ThumbstickMapping, ship: ShipState,
		stick: Vector2, buttons: Dictionary = {}, tick: int = 0, held: bool = false,
		ended: bool = false, grips: Vector2 = Vector2.ZERO) -> ShipInput:
	var left_stick: Vector2 = stick if mapping.left_handed else Vector2.ZERO
	var right_stick: Vector2 = Vector2.ZERO if mapping.left_handed else stick
	var input: ShipInput = mapping.map_controls(left_stick, right_stick, 0.0, 0.0, grips.x, grips.y, buttons)
	return step.filter(input, stick, ship, tick, held, ended)


## Opens the popup: a click with the stick at rest, then the click released.
static func _open(step: SlotPopupInput, mapping: ThumbstickMapping, ship: ShipState,
		click: Dictionary = CLICK) -> void:
	_frame(step, mapping, ship, Vector2.ZERO, click)
	_frame(step, mapping, ship, Vector2.ZERO)


func test_a_click_with_both_full_opens_and_the_stick_does_not_turn() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_frame(step, mapping, ship, Vector2.ZERO, CLICK)
	if not step.is_open:
		return "the click did not open the popup"
	# Inside the flick threshold: no choice, and no turn either.
	var input: ShipInput = _frame(step, mapping, ship, Vector2(0.4, 0.4), {}, 0, false, false, Vector2(0.0, 1.0))
	if input.turn_q.x != 0 or input.turn_q.y != 0:
		return "the stick turned the ship while choosing: %s" % input.turn_q
	if input.turn_q.z == 0:
		return "roll on the grip should still fly"
	if input.slot_choice != ShipInput.SLOT_CHOICE_NONE or not step.is_open:
		return "a half push chose %d" % input.slot_choice
	return ""


func test_each_flick_sends_its_choice_and_closes() -> String:
	var cases: Dictionary = {
		RIGHT: ShipInput.SLOT_CHOICE_SLOT_1,
		LEFT: ShipInput.SLOT_CHOICE_SLOT_2,
		DOWN: ShipInput.SLOT_CHOICE_DUMP,
	}
	for stick: Vector2 in cases:
		var step: SlotPopupInput = SlotPopupInput.new()
		var mapping: ThumbstickMapping = ThumbstickMapping.new()
		var ship: ShipState = _full_ship()
		_open(step, mapping, ship)
		var input: ShipInput = _frame(step, mapping, ship, stick, {}, 7)
		if input.slot_choice != int(cases[stick]):
			return "stick %s sent %d, not %d" % [stick, input.slot_choice, cases[stick]]
		if step.is_open or step.closed_reason != SlotPopupInput.CLOSED_CHOSEN:
			return "stick %s: the popup did not close as chosen" % stick
		if input.turn_q.x != 0 or input.turn_q.y != 0:
			return "stick %s turned the ship on the choosing frame" % stick
	return ""


func test_up_chooses_nothing() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_open(step, mapping, ship)
	var input: ShipInput = _frame(step, mapping, ship, UP)
	if input.slot_choice != ShipInput.SLOT_CHOICE_NONE or not step.is_open:
		return "up chose %d or closed the popup" % input.slot_choice
	return ""


func test_a_choice_is_sent_until_a_tick_flies_it_then_none() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_open(step, mapping, ship)
	_frame(step, mapping, ship, RIGHT, {}, 10)
	# A fast frame ran no tick: the choice must still be there.
	var again: ShipInput = _frame(step, mapping, ship, RIGHT, {}, 10)
	if again.slot_choice != ShipInput.SLOT_CHOICE_SLOT_1:
		return "a frame with no tick flown lost the choice"
	var after: ShipInput = _frame(step, mapping, ship, RIGHT, {}, 11)
	if after.slot_choice != ShipInput.SLOT_CHOICE_NONE:
		return "the choice was still sent after a tick flew it"
	return ""


func test_the_stick_turns_again_only_after_it_rests() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_open(step, mapping, ship)
	_frame(step, mapping, ship, RIGHT, {}, 1)
	var held_over: ShipInput = _frame(step, mapping, ship, RIGHT, {}, 2)
	if held_over.turn_q.y != 0:
		return "the stick that chose turned the ship before resting"
	_frame(step, mapping, ship, Vector2.ZERO, {}, 3)
	var turning: ShipInput = _frame(step, mapping, ship, RIGHT, {}, 4)
	if turning.turn_q.y == 0:
		return "the stick did not turn the ship after resting"
	return ""


func test_a_stick_pushed_when_it_opens_must_rest_before_it_chooses() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_frame(step, mapping, ship, RIGHT, CLICK)
	var pushed: ShipInput = _frame(step, mapping, ship, RIGHT)
	if pushed.slot_choice != ShipInput.SLOT_CHOICE_NONE or not step.is_open:
		return "a stick already pushed when the popup opened chose %d" % pushed.slot_choice
	_frame(step, mapping, ship, Vector2.ZERO)
	if _frame(step, mapping, ship, LEFT).slot_choice != ShipInput.SLOT_CHOICE_SLOT_2:
		return "a flick after resting did not choose"
	return ""


func test_a_second_click_cancels_and_sends_nothing() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_open(step, mapping, ship)
	var cancel: ShipInput = _frame(step, mapping, ship, Vector2.ZERO, CLICK)
	if step.is_open or step.closed_reason != SlotPopupInput.CLOSED_CANCELLED:
		return "the second click did not cancel"
	var after: ShipInput = _frame(step, mapping, ship, RIGHT)
	if cancel.slot_choice != ShipInput.SLOT_CHOICE_NONE or after.slot_choice != ShipInput.SLOT_CHOICE_NONE:
		return "a cancel sent a choice"
	if step.is_open:
		return "releasing the cancel click reopened the popup"
	return ""


func test_it_closes_by_itself_and_sends_nothing() -> String:
	var cases: Array[String] = ["part gone", "slot empty", "destroyed", "escaped", "menu", "level ended"]
	for name: String in cases:
		var step: SlotPopupInput = SlotPopupInput.new()
		var mapping: ThumbstickMapping = ThumbstickMapping.new()
		var ship: ShipState = _full_ship()
		_open(step, mapping, ship)
		var held: bool = name == "menu"
		var ended: bool = name == "level ended"
		match name:
			"part gone": ship.hold.clear()
			"slot empty": ship.primary_slots[1] = null
			"destroyed": ship.hull = 0.0
			"escaped": ship.escaped = true
		var closing: ShipInput = _frame(step, mapping, ship, RIGHT, {}, 0, held, ended)
		if step.is_open or step.closed_reason != SlotPopupInput.CLOSED_GONE:
			return "%s: the popup stayed open" % name
		if closing.slot_choice != ShipInput.SLOT_CHOICE_NONE:
			return "%s: a closing popup sent %d" % [name, closing.slot_choice]
	return ""


func test_a_pending_choice_is_dropped_when_the_menu_opens() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	_open(step, mapping, ship)
	_frame(step, mapping, ship, DOWN, {}, 5)
	var held: ShipInput = _frame(step, mapping, ship, DOWN, {}, 5, true)
	if held.slot_choice != ShipInput.SLOT_CHOICE_NONE:
		return "a choice not yet flown was sent with the menu open"
	return ""


func test_with_an_empty_slot_the_click_slots_and_no_popup() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = _full_ship()
	ship.primary_slots[1] = null
	var input: ShipInput = _frame(step, mapping, ship, RIGHT, CLICK)
	if step.is_open:
		return "the popup opened with a slot empty"
	if not input.slot_held:
		return "the click no longer reaches the core"
	if input.turn_q.y == 0:
		return "the stick stopped turning with no popup"
	return ""


func test_no_part_no_popup() -> String:
	var step: SlotPopupInput = SlotPopupInput.new()
	var ship: ShipState = _full_ship()
	ship.hold.clear()
	_frame(step, ThumbstickMapping.new(), ship, Vector2.ZERO, CLICK)
	return "the popup opened with an empty hold" if step.is_open else ""


func test_left_handed_mode_mirrors_it_onto_the_left_stick() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.left_handed = true
	if SlotPopupInput.stick_hand(mapping) != "left":
		return "left-handed mode chooses with the %s stick" % SlotPopupInput.stick_hand(mapping)
	if SlotPopupInput.stick_hand(ThumbstickMapping.new()) != "right":
		return "right-handed mode should choose with the right stick"
	var step: SlotPopupInput = SlotPopupInput.new()
	var ship: ShipState = _full_ship()
	_frame(step, mapping, ship, Vector2.ZERO, CLICK)
	if step.is_open:
		return "the right stick click opened the popup in left-handed mode"
	_frame(step, mapping, ship, Vector2.ZERO)
	_open(step, mapping, ship, LEFT_CLICK)
	if not step.is_open:
		return "the left stick click did not open it in left-handed mode"
	var input: ShipInput = _frame(step, mapping, ship, Vector2(0.5, 0.0))
	if input.turn_q.y != 0:
		return "the left stick turned the ship while choosing"
	if _frame(step, mapping, ship, LEFT).slot_choice != ShipInput.SLOT_CHOICE_SLOT_2:
		return "left on the left stick did not replace the left gun"
	return ""


func test_the_thresholds_come_from_the_look() -> String:
	var look: Dictionary = SlotPopupLook.FALLBACK.duplicate()
	look["flick_threshold"] = 0.9
	look["rest_threshold"] = 0.1
	var step: SlotPopupInput = SlotPopupInput.from_look(look)
	if step.choice_for(Vector2(0.85, 0.0)) != ShipInput.SLOT_CHOICE_NONE:
		return "0.85 flicked past a 0.9 threshold"
	if step.choice_for(Vector2(0.95, 0.0)) != ShipInput.SLOT_CHOICE_SLOT_1:
		return "0.95 did not flick past a 0.9 threshold"
	return ""
