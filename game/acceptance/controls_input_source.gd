class_name ControlsInputSource
extends ReplayInputSource

## Flies a scripted list of raw controller values through the game's own
## `ThumbstickMapping`, one frame of values per tick (PLT-5, #818). A replay of
## `ShipInput` never passes the mapping, so it cannot show that left-handed mode
## swaps the hands; this source can.
##
## The replay given to the base class only supplies the level the flight
## starts in (seed, walls, start, tuning); its recorded inputs are not flown.
## The mapping is the scene's: `ControllerSampler.map_values` turns each frame
## into input exactly as the controllers' values are turned each frame in play.
##
## While the flight runs the mapping's hand setting is the step's and pitch is
## not inverted, so a player's saved choice cannot change the hash; `finish`
## puts both back as they were.

var _frames: Array[Dictionary] = []
var _mapping: ThumbstickMapping = null
var _was_left_handed: bool = false
var _was_inverted: bool = false
var _finished: bool = false


func _init(replay: Replay, frames: Array[Dictionary], mapping: ThumbstickMapping, left_handed: bool) -> void:
	super(replay, false)
	_frames = frames
	_mapping = mapping
	_was_left_handed = mapping.left_handed
	_was_inverted = mapping.invert_pitch
	mapping.left_handed = left_handed
	mapping.invert_pitch = false


func tick_count() -> int:
	return _frames.size()


func next_input(tick: int) -> ShipInput:
	if tick < 0 or tick >= _frames.size():
		overrun_ticks += 1
		return ShipInput.new()
	return ControllerSampler.map_values(_mapping, _frames[tick])


## Gives the mapping back its hand and pitch settings from before the step.
func finish() -> void:
	if _finished:
		return
	_finished = true
	_mapping.left_handed = _was_left_handed
	_mapping.invert_pitch = _was_inverted
