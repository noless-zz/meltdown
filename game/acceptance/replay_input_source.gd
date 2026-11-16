class_name ReplayInputSource
extends ShipInputSource

## Hands a one-ship replay's recorded inputs to a running session, one per
## tick, in place of the controllers (DEV-6, #165). Indexed by the tick the
## session asks for, so a dropped or doubled frame cannot shift the inputs.

var _replay: Replay
## Ticks asked for beyond the end of the replay; each flew no input.
var overrun_ticks: int = 0


func _init(replay: Replay) -> void:
	_replay = replay


func tick_count() -> int:
	return _replay.frames.size()


func next_input(tick: int) -> ShipInput:
	if tick < 0 or tick >= _replay.frames.size():
		overrun_ticks += 1
		return ShipInput.new()
	var frame: Array = _replay.frames[tick]
	var recorded: ShipInput = frame[0]
	# A copy: the session records what it flew, and must not share the replay's object.
	return LatestInputSource._copy(recorded)
