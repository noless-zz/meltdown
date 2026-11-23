class_name SlotPopupInput
extends RefCounted

## The slot popup's input step (#1263, decision record 0011, SLV-1): with a
## part in the hold and both primary slots full, the slot click opens the
## popup, and while it is open the stick on that hand chooses instead of
## turning. Left replaces slot 2 (the left gun), right replaces slot 1 (the
## right gun), down dumps the part; a second click cancels.
##
## It takes the mapped `ShipInput` and returns it changed in two ways only:
## pitch and yaw are zeroed while the stick chooses, and `slot_choice` carries
## the answer. The choice reaches the core only that way (ARC-3, MP-2); this
## reads a copy of the ship and writes no simulation state. Roll, thrust,
## fire and the click itself pass through: the mine keeps running and the
## core ignores the click with both slots full (#1262).
##
## A frame's input flies every tick until the next frame, and a fast frame
## may fly none, so a choice is sent until a tick has flown it (the sim's tick
## has moved on) and then dropped. `PartSlotting` acts on it once.

## Stick direction -> the choice it makes. Up makes none.
const CHOICE_LEFT: int = ShipInput.SLOT_CHOICE_SLOT_2
const CHOICE_RIGHT: int = ShipInput.SLOT_CHOICE_SLOT_1
const CHOICE_DOWN: int = ShipInput.SLOT_CHOICE_DUMP
## Why the popup last closed, for the log and tests.
const CLOSED_CHOSEN: String = "chosen"
const CLOSED_CANCELLED: String = "cancelled"
const CLOSED_GONE: String = "gone"

var flick_threshold: float = SlotPopupLook.FALLBACK["flick_threshold"]
var rest_threshold: float = SlotPopupLook.FALLBACK["rest_threshold"]
## True while the popup shows and the stick chooses.
var is_open: bool = false
## Why it last closed: one of the CLOSED_ values, or "" before it ever did.
var closed_reason: String = ""

var _click_was: bool = false
## The stick has rested since the popup opened, so a flick may choose.
var _armed: bool = false
## The stick has not rested since the popup closed; it may not turn yet.
var _wait_rest: bool = false
var _pending: int = ShipInput.SLOT_CHOICE_NONE
var _pending_tick: int = -1


## The thresholds from a look parsed by `SlotPopupLook`.
static func from_look(look: Dictionary) -> SlotPopupInput:
	var step: SlotPopupInput = SlotPopupInput.new()
	step.flick_threshold = float(look.get("flick_threshold", step.flick_threshold))
	step.rest_threshold = float(look.get("rest_threshold", step.rest_threshold))
	return step


## Which hand's stick chooses: the hand whose stick click slots a part, after
## left-handed mode has moved it (PLT-5). A layout that slots from a button
## uses the turning stick: right, or left when left-handed.
static func stick_hand(mapping: ThumbstickMapping) -> String:
	for control: String in mapping.physical_controls("slot_part"):
		if control.ends_with("_stick_click"):
			return control.get_slice("_", 0)
	return "left" if mapping.left_handed else "right"


## The choice a stick at `stick` makes, or none inside the flick threshold or
## pushed up. The larger axis wins, so a diagonal picks one side.
func choice_for(stick: Vector2) -> int:
	if stick.length() < flick_threshold:
		return ShipInput.SLOT_CHOICE_NONE
	if absf(stick.x) >= absf(stick.y):
		return CHOICE_LEFT if stick.x < 0.0 else CHOICE_RIGHT
	return CHOICE_DOWN if stick.y < 0.0 else ShipInput.SLOT_CHOICE_NONE


## Whether `ship` (a copy) is where the popup applies: alive, in the level,
## a part in the hold and no primary slot empty.
static func can_choose(ship: ShipState) -> bool:
	return ship.hull > 0.0 and not ship.escaped and not ship.hold.is_empty() \
		and not ship.primary_slots.has(null)


## One frame: `input` as mapped, `stick` the choosing hand's raw stick,
## `ship` a copy of the local ship, `tick` the sim's tick before this frame's
## advance, `held` whether the ship is held (menu, flight test, pause, lost
## ship; `ShipHold`) and `ended` whether the level has ended. Returns `input`.
func filter(input: ShipInput, stick: Vector2, ship: ShipState, tick: int, held: bool,
		ended: bool) -> ShipInput:
	var clicked: bool = input.slot_held and not _click_was
	_click_was = input.slot_held
	var allowed: bool = not held and not ended and can_choose(ship)
	_send_pending(input, tick, held or ended)
	if is_open:
		if not allowed:
			_close(CLOSED_GONE)
		elif clicked:
			_close(CLOSED_CANCELLED)
		elif not _armed:
			_armed = stick.length() < rest_threshold
		else:
			var choice: int = choice_for(stick)
			if choice != ShipInput.SLOT_CHOICE_NONE:
				_pending = choice
				_pending_tick = tick
				input.slot_choice = choice
				_close(CLOSED_CHOSEN)
	elif clicked and allowed and _pending == ShipInput.SLOT_CHOICE_NONE:
		is_open = true
		_armed = stick.length() < rest_threshold
	if _wait_rest and stick.length() < rest_threshold:
		_wait_rest = false
	if is_open or _wait_rest:
		input.turn_q = Vector3i(0, 0, input.turn_q.z)
	return input


## Puts a choice not yet flown on `input`; drops it once a tick has flown it,
## or when the ship is held, the level ended or a new session began.
func _send_pending(input: ShipInput, tick: int, stop: bool) -> void:
	if _pending == ShipInput.SLOT_CHOICE_NONE:
		return
	if stop or tick != _pending_tick:
		_pending = ShipInput.SLOT_CHOICE_NONE
		_pending_tick = -1
		return
	input.slot_choice = _pending


func _close(reason: String) -> void:
	is_open = false
	_armed = false
	_wait_rest = true
	closed_reason = reason
