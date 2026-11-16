class_name LocalSession
extends RefCounted

## Runs one `Sim` at a fixed 60 Hz from variable frame times, for a single
## local ship (MP-3). The headset build, the desktop build and later the host
## all drive the simulation through this, so they fly the same code.
##
## Time arrives only through `advance`; nothing here reads the clock, nodes or
## input devices (ARC-1). The view reads `previous_ship()`, `current_ship()`,
## `current_projectiles()` and `interpolation_fraction` and never writes
## simulation state (MP-2).

## A long hitch (a loading stall, the headset taken off) would otherwise make
## the next frame run hundreds of ticks, take longer than a frame, and fall
## further behind each frame. Beyond this many ticks the time is dropped.
const MAX_TICKS_PER_ADVANCE: int = 5
## Frame times summed in floating point land a hair short of a whole tick
## (90 frames of 1/90 s), which would lose one tick per second. Time within this
## margin of a whole tick counts as the whole tick.
const TICK_EPSILON: float = 1.0e-6
## Where the weapons a ship file's loadout names are read from, by id (#189).
const WEAPON_DIR: String = "res://data/weapons/"

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
## Events of every tick run by the latest `advance`, in tick order.
var _frame_events: Array[SimEvent] = []
## Copies of `sim.projectiles` after the latest tick, oldest first.
var _current_projectiles: Array[Projectile] = []
## The copy of each live projectile, by the simulation's projectile. A
## projectile keeps one copy for its whole flight, so the view can tell a bolt
## it already drew from a new one and blend it between ticks.
var _projectile_copies: Dictionary[Projectile, Projectile] = {}


## `bounds` are the walls the ship flies inside, or null for open space.
## `tuning` gives every ship its feel values before the first tick; null, or a
## tuning whose `error` is set, flies the built-in defaults. A tuning whose
## loadout has been resolved (see `load_tuning`) starts the ship armed, and the
## weapons are recorded in the replay (CMB-1, ARC-2).
func _init(run_seed: int = 0, input_source: ShipInputSource = null, bounds: BoxBounds = null,
		tuning: ShipTuning = null) -> void:
	replay = Replay.new(run_seed, 1)
	if bounds != null:
		replay.set_box(_to_mm(bounds.min_corner), _to_mm(bounds.max_corner))
	if tuning != null and tuning.error == "":
		replay.tuning = tuning
	# The walls are taken back from the replay, rounded to its whole
	# millimetres, so that running the replay meets exactly the same walls.
	# The tuning goes through the replay too, so a replay flies the same ship.
	sim = Sim.new(run_seed, 1, replay.bounds())
	replay.apply_tuning(sim)
	if replay.tuning != null and replay.tuning.loadout.is_armed():
		replay.loadout = replay.tuning.loadout
		sim.equip(replay.loadout)
	_input_source = input_source if input_source != null else ShipInputSource.new()
	_current_ship = _snapshot(sim.ships[0])
	_previous_ship = _snapshot(sim.ships[0])


## Adds `delta_seconds` of frame time and runs every whole tick that fits, up to
## `MAX_TICKS_PER_ADVANCE`. Returns the number of ticks run.
func advance(delta_seconds: float) -> int:
	ticks_last_advance = 0
	_frame_events = []
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


## Reads a ship data file. Returns null, after printing why, when the file is
## missing or rejected, so the caller flies the built-in defaults.
## The weapons its loadout names are read from `weapon_dir` and resolved here,
## since core opens no files. If any of them is missing or rejected, the
## problem is printed and the ship flies unarmed with the file's other values:
## a half-armed ship would hide which weapon broke.
static func load_tuning(path: String, weapon_dir: String = WEAPON_DIR) -> ShipTuning:
	var problem: String = ""
	var tuning: ShipTuning = null
	if not FileAccess.file_exists(path):
		problem = "file not found"
	else:
		tuning = ShipTuning.parse_json(FileAccess.get_file_as_string(path))
		problem = tuning.error
	if problem != "":
		print("Meltdown: ship tuning %s rejected (%s); flying with the built-in defaults" % [path, problem])
		return null
	var texts: Dictionary = {}
	for id: String in tuning.loadout.weapon_ids():
		var weapon_path: String = weapon_dir.path_join(id + ".json")
		if FileAccess.file_exists(weapon_path):
			texts[id] = FileAccess.get_file_as_string(weapon_path)
	var weapon_problem: String = tuning.loadout.resolve(texts)
	if weapon_problem != "":
		print("Meltdown: ship loadout in %s rejected (%s); flying unarmed" % [path, weapon_problem])
	return tuning


## The `SimEvent`s of every tick run by the latest `advance`, in order; empty
## when it ran none. `Sim.last_events` holds only the last tick, so a frame
## that runs two ticks would otherwise lose the first tick's wall impact. A
## copy of the list: changing it leaves the session as it was.
func frame_events() -> Array[SimEvent]:
	return _frame_events.duplicate()


## Ship state after the tick before the latest one. A copy: writing to it
## changes nothing in the simulation.
func previous_ship() -> ShipState:
	return _previous_ship


## Ship state after the latest tick. A copy, like `previous_ship()`.
func current_ship() -> ShipState:
	return _current_ship


## Every live projectile after the latest tick, oldest first. A new array of
## copies: changing the array or a projectile in it leaves the simulation as it
## was (MP-2). The same projectile is the same copy from tick to tick.
func current_projectiles() -> Array[Projectile]:
	return _current_projectiles.duplicate()


func _run_tick() -> void:
	var inputs: Array[ShipInput] = [_input_source.next_input(sim.tick)]
	sim.step(inputs)
	_frame_events.append_array(sim.last_events)
	replay.add_tick(inputs)
	_accumulator -= ShipState.TICK_DT
	_previous_ship = _current_ship
	_current_ship = _snapshot(sim.ships[0])
	_snapshot_projectiles()


## Drops the whole ticks left in the accumulator and keeps the fraction, so the
## interpolation stays smooth across the hitch.
func _drop_whole_ticks() -> void:
	var whole_ticks: float = floorf((_accumulator + TICK_EPSILON) / ShipState.TICK_DT)
	var dropped: float = whole_ticks * ShipState.TICK_DT
	dropped_seconds += dropped
	_accumulator = maxf(_accumulator - dropped, 0.0)


static func _snapshot(ship: ShipState) -> ShipState:
	var copy: ShipState = ShipState.new()
	_copy_fields(ship, copy)
	return copy


## Refreshes `_current_projectiles` from `sim.projectiles`, reusing the copy
## each projectile already has and dropping those of removed projectiles.
func _snapshot_projectiles() -> void:
	var copies: Dictionary[Projectile, Projectile] = {}
	var listed: Array[Projectile] = []
	for projectile: Projectile in sim.projectiles:
		var copy: Projectile = _projectile_copies.get(projectile, null) as Projectile
		if copy == null:
			copy = Projectile.new()
		_copy_fields(projectile, copy)
		copies[projectile] = copy
		listed.append(copy)
	_projectile_copies = copies
	_current_projectiles = listed


## Copies every script variable, so fields added to `ShipState` or
## `Projectile` later are carried along without changing this file.
static func _copy_fields(from: Object, to: Object) -> void:
	for property: Dictionary in from.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var prop_name: String = property["name"]
			to.set(prop_name, from.get(prop_name))


static func _to_mm(metres: Vector3) -> Vector3i:
	return Vector3i((metres * float(Replay.BOX_SCALE)).round())
