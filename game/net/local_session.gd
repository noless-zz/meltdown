class_name LocalSession
extends RefCounted

## Runs one `Sim` at a fixed 60 Hz from variable frame times, for a single
## local ship (MP-3). The headset build, the desktop build and later the host
## all drive the simulation through this, so they fly the same code.
##
## Time arrives only through `advance`; nothing here reads the clock, nodes or
## input devices (ARC-1). The view reads `previous_ship()`, `current_ship()`
## and `interpolation_fraction` and never writes simulation state (MP-2).

## A long hitch (a loading stall, the headset taken off) would otherwise make
## the next frame run hundreds of ticks, take longer than a frame, and fall
## further behind each frame. Beyond this many ticks the time is dropped.
const MAX_TICKS_PER_ADVANCE: int = 5
## Frame times summed in floating point land a hair short of a whole tick
## (90 frames of 1/90 s), which would lose one tick per second. Time within this
## margin of a whole tick counts as the whole tick.
const TICK_EPSILON: float = 1.0e-6

var sim: Sim
## Every input fed to `sim`, in order; running it reproduces `sim` (ARC-2).
var replay: Replay
## Where the current position lies between the previous and current tick,
## 0..1. The view blends the poses of `previous_ship()` and `current_ship()`
## by this amount.
var interpolation_fraction: float = 0.0
## Total frame time thrown away by the tick cap, in seconds.
var dropped_seconds: float = 0.0
## Ticks run by the most recent `advance` call.
var ticks_last_advance: int = 0
## Solo pause (PLT-7). While true, `advance` runs nothing and throws the frame
## time away, so the view holds the last pose. Clearing it arms a one-frame
## limit, so the frame that spans the pause cannot run catch-up ticks.
var paused: bool = false:
	set(value):
		if paused and not value:
			_resuming = true
		paused = value

var _input_source: ShipInputSource
var _accumulator: float = 0.0
var _resuming: bool = false
var _previous_ship: ShipState
var _current_ship: ShipState


## `bounds` are the walls the ship flies inside, or null for open space.
func _init(run_seed: int = 0, input_source: ShipInputSource = null, bounds: BoxBounds = null) -> void:
	replay = Replay.new(run_seed, 1)
	if bounds != null:
		replay.set_box(_to_mm(bounds.min_corner), _to_mm(bounds.max_corner))
	# The walls are taken back from the replay, rounded to its whole
	# millimetres, so that running the replay meets exactly the same walls.
	sim = Sim.new(run_seed, 1, replay.bounds())
	_input_source = input_source if input_source != null else ShipInputSource.new()
	_current_ship = _snapshot(sim.ships[0])
	_previous_ship = _snapshot(sim.ships[0])


## Adds `delta_seconds` of frame time and runs every whole tick that fits, up to
## `MAX_TICKS_PER_ADVANCE`. Returns the number of ticks run.
func advance(delta_seconds: float) -> int:
	ticks_last_advance = 0
	# Paused time is not owed to the simulation; keeping it would replay the
	# pause as a burst of ticks on resume. The fraction stays put so the rig
	# shows the same pose every paused frame (CMF-8).
	if paused:
		return 0
	# A negative or non-finite frame time can only come from a broken clock;
	# feeding it in would run time backwards or poison the accumulator.
	if is_finite(delta_seconds) and delta_seconds > 0.0:
		var frame_time: float = delta_seconds
		# The first frame after a pause can report the whole time the headset
		# was off; only one tick of it may count.
		if _resuming:
			frame_time = minf(frame_time, ShipState.TICK_DT)
		_accumulator += frame_time
	_resuming = false
	while _accumulator >= ShipState.TICK_DT - TICK_EPSILON:
		if ticks_last_advance >= MAX_TICKS_PER_ADVANCE:
			_drop_whole_ticks()
			break
		_run_tick()
		ticks_last_advance += 1
	interpolation_fraction = clampf(_accumulator / ShipState.TICK_DT, 0.0, 1.0)
	return ticks_last_advance


## Ship state after the tick before the latest one. A copy: writing to it
## changes nothing in the simulation.
func previous_ship() -> ShipState:
	return _previous_ship


## Ship state after the latest tick. A copy, like `previous_ship()`.
func current_ship() -> ShipState:
	return _current_ship


func _run_tick() -> void:
	var inputs: Array[ShipInput] = [_input_source.next_input(sim.tick)]
	sim.step(inputs)
	replay.add_tick(inputs)
	_accumulator -= ShipState.TICK_DT
	_previous_ship = _current_ship
	_current_ship = _snapshot(sim.ships[0])


## Drops the whole ticks left in the accumulator and keeps the fraction, so the
## interpolation stays smooth across the hitch.
func _drop_whole_ticks() -> void:
	var whole_ticks: float = floorf((_accumulator + TICK_EPSILON) / ShipState.TICK_DT)
	var dropped: float = whole_ticks * ShipState.TICK_DT
	dropped_seconds += dropped
	_accumulator = maxf(_accumulator - dropped, 0.0)


## Copies every script variable, so fields added to `ShipState` later are
## carried along without changing this file.
static func _snapshot(ship: ShipState) -> ShipState:
	var copy: ShipState = ShipState.new()
	for property: Dictionary in ship.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var prop_name: String = property["name"]
			copy.set(prop_name, ship.get(prop_name))
	return copy


static func _to_mm(metres: Vector3) -> Vector3i:
	return Vector3i((metres * float(Replay.BOX_SCALE)).round())
