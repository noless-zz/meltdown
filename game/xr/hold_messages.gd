class_name HoldMessages
extends RefCounted

## Tells, from two frames of a ship's hold and primary slots, what just
## happened to the hold, so the status panel can say it for a moment (#605):
## a pickup ("Picked up: <part>") or a slotting ("Slotted <part>, dropped
## <old>"). Derived from session copies of the ship only: nothing in `core/`
## changes and nothing is written back (MP-2).

const PICKED_UP: String = "Picked up: %s"
const SLOTTED: String = "Slotted %s"
const SLOTTED_DROPPED: String = "Slotted %s, dropped %s"

var _primed: bool = false
var _hold: Array[String] = []
var _primary_ids: Array[String] = []


## Takes this frame's hold and primary slot ids and returns the message for
## what changed since the last call, or "" when nothing worth saying did. The
## first call only remembers, so a level that starts with a full hold says
## nothing. Copies are kept: session copies may share arrays with the sim.
func update(hold: Array[String], primary_ids: Array[String]) -> String:
	var message: String = ""
	if _primed:
		message = _slotted_message(hold, primary_ids)
		if message == "" and _hold.is_empty() and not hold.is_empty():
			message = PICKED_UP % hold[0]
	_primed = true
	_hold = hold.duplicate()
	_primary_ids = primary_ids.duplicate()
	return message


## The slotting message when the held part left the hold and took a primary
## slot this frame, else "".
func _slotted_message(hold: Array[String], primary_ids: Array[String]) -> String:
	if _hold.is_empty() or (not hold.is_empty() and hold[0] == _hold[0]):
		return ""
	var part: String = _hold[0]
	for slot: int in primary_ids.size():
		var old: String = _primary_ids[slot] if slot < _primary_ids.size() else ""
		if primary_ids[slot] == part and old != part:
			return SLOTTED % part if old == "" else SLOTTED_DROPPED % [part, old]
	return ""
