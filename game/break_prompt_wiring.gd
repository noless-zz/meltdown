class_name BreakPromptWiring
extends RefCounted

## Shows the "take a break" prompt in the game (CMF-10, #716): one
## `BreakReminder` for the whole session counts the time flown and
## `BreakPrompt` shows it when due. A tap of the menu button dismisses it,
## through the same `MenuTap` the update notice reads; while the prompt shows,
## it takes the tap and the update notice waits.
##
## It sits beside `main.gd`, like the other wirings, because deciding whether
## the pilot is flying reads the session's pause and ship and the flight test.
## It reads copies only and never pauses the session, so the simulation runs
## on while the prompt shows (CMF-6, ARC-3, MP-2); the prompt hangs at the
## cockpit's head point and nothing it does moves the view (CMF-8).

## Null until `attach` has run.
var reminder: BreakReminder = null
var prompt: BreakPrompt = null

var _comfort: ComfortWiring = null
## The preset the reminder was last given, so every change reaches it.
var _preset: ComfortPreset = null
## The prompt's place relative to the head point, from its data file.
var _local: Transform3D = Transform3D.IDENTITY


## Makes the session's reminder from `comfort`'s active preset, applies the
## data file's on/off setting, hangs the prompt under `rig` (none in some
## tests) and, given `update`, asks it to offer each menu tap here first.
## `look` is a parsed break prompt file; empty reads the shipped one.
## Calling it again adds nothing.
func attach(rig: Node3D, comfort: ComfortWiring, update: UpdateWiring = null, look: Dictionary = {}) -> void:
	if prompt != null:
		return
	_comfort = comfort
	_preset = comfort.preset
	reminder = BreakReminder.new(_preset)
	prompt = BreakPrompt.new(look)
	_local = prompt.transform
	prompt.apply_setting(reminder)
	if rig != null:
		rig.add_child(prompt)
	if update != null:
		update.tap_taker = take_tap


## Whether this frame counts as flying: a level or the tunnel is being flown,
## not paused, not during the flight test, and not from the ship's loss
## until the restarted level has faded back in.
static func is_flying(session: LocalSession, flight_test: FlightTestWiring, destroyed: DestroyedWiring) -> bool:
	return not session.paused and not flight_test.running() and destroyed.fade_alpha() <= 0.0 \
		and session.current_ship().hull > 0.0


## Once per frame: hands the reminder a changed preset, counts `delta_seconds`
## when `flying`, puts the prompt at the cockpit frame's head point and shows
## or hides it. `xr_running` picks the button its dismiss line names.
func update(delta_seconds: float, flying: bool, xr_running: bool) -> void:
	if reminder == null:
		return
	if _comfort.preset != _preset:
		_preset = _comfort.preset
		reminder.set_preset(_preset)
	reminder.advance(delta_seconds, flying)
	var frame: CockpitFrame = _comfort.cockpit_frame
	prompt.transform = (frame.transform if frame != null else Transform3D.IDENTITY) * _local
	prompt.show_if(reminder, xr_running)


## A menu tap landed. Dismisses a shown prompt, which starts the next interval,
## and returns true so nothing else acts on the tap; false while it is hidden.
func take_tap() -> bool:
	return prompt != null and prompt.acknowledge()


## True while the prompt is on screen.
func shown() -> bool:
	return prompt != null and prompt.is_shown()
