class_name BreakReminder
extends RefCounted

## When to show the "take a break" prompt (CMF-10). Showing it is the scene's
## job; this only counts time and says when the prompt is due.
##
## The caller passes in the seconds that passed and whether the player was
## flying, so the reminder reads no clock, no node and nothing in `core/`, and
## nothing it does can change the simulation (CMF-6, ARC-3).

## Counted time may fall this far short of the interval and still be due, so a
## run of 1/60 s steps reaches exactly 30 minutes despite rounding.
const EPSILON_S: float = 1e-6

## Seconds of flying per reminder; 0 when the preset turns reminders off.
var _interval_s: float = 0.0
var _enabled: bool = true
## Seconds flown since the last prompt was acknowledged, or since the start.
var _flown_s: float = 0.0
var _due: bool = false


func _init(preset: ComfortPreset) -> void:
	set_preset(preset)


## Takes the interval from `preset`. Time already flown is kept, so changing
## preset mid-session does not restart the count; a preset with 0 minutes
## stops reminders and clears a pending one.
func set_preset(preset: ComfortPreset) -> void:
	_interval_s = maxf(preset.break_reminder_minutes, 0.0) * 60.0
	_update_due()


## Counts `seconds` only when `flying`; a paused session does not count.
func advance(seconds: float, flying: bool) -> void:
	if not flying or seconds <= 0.0:
		return
	_flown_s += seconds
	_update_due()


## True once the counted time has reached the preset's interval and the prompt
## has not been acknowledged.
func due() -> bool:
	return _due


## The player saw the prompt: clear it and start the next interval from zero.
func acknowledge() -> void:
	_due = false
	_flown_s = 0.0


## The player's switch. Turning it off clears a pending prompt; turning it back
## on starts a fresh interval, so the prompt does not appear at once for time
## flown while it was off.
func set_enabled(enabled: bool) -> void:
	if enabled and not _enabled:
		_flown_s = 0.0
	_enabled = enabled
	_update_due()


func is_enabled() -> bool:
	return _enabled


## Seconds flown towards the next prompt.
func flown_seconds() -> float:
	return _flown_s


func _update_due() -> void:
	if not _enabled or _interval_s <= 0.0:
		_due = false
	elif _flown_s >= _interval_s - EPSILON_S:
		_due = true
