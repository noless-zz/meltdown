class_name LocalSession
extends RefCounted

## Runs one `Sim` at a fixed 60 Hz from variable frame times, for a single
## local ship (MP-3). The headset build, the desktop build and later the host
## all drive the simulation through this, so they fly the same code.
##
## Time arrives only through `advance`; nothing here reads the clock, nodes or
## input devices (ARC-1). The view reads `previous_ship()`, `current_ship()`,
## `current_projectiles()`, `previous_robots()`, `current_robots()`,
## `previous_salvage()`, `current_salvage()` and `interpolation_fraction` and
## never writes simulation state (MP-2).

## A long hitch (a loading stall, the headset taken off) would otherwise make
## the next frame run hundreds of ticks, take longer than a frame, and fall
## further behind each frame. Beyond this many ticks the time is dropped.
const MAX_TICKS_PER_ADVANCE: int = 5
## Frame times summed in floating point land a hair short of a whole tick
## (90 frames of 1/90 s), which would lose one tick per second. Time within this
## margin of a whole tick counts as the whole tick.
const TICK_EPSILON: float = 1.0e-6
## Forwards to `SpawnLoader`, which reads the data files (#296).
const WEAPON_DIR: String = SpawnLoader.WEAPON_DIR
const ROBOT_DIR: String = SpawnLoader.ROBOT_DIR
const ROBOT_WEAPON_DIR: String = SpawnLoader.ROBOT_WEAPON_DIR

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
## The headset lost focus (PLT-7); `paused` sets and clears this reason.
const PAUSE_FOCUS: String = "focus"
## The dev menu is open in solo play (#1245, `DevMenuPause.hold`).
const PAUSE_MENU: String = "menu"

## Solo pause (PLT-7). True while any pause reason holds. While true, `advance`
## runs nothing and throws the frame time away, so the view holds the last
## pose. When the last reason clears, a one-frame limit is armed, so the frame
## that spans the pause cannot run catch-up ticks. Setting it sets the focus
## reason only, which is what the focus callbacks always meant (#1245).
var paused: bool:
	get:
		return not _pause_reasons.is_empty()
	set(value):
		set_paused(PAUSE_FOCUS, value)

## The reasons holding the pause, each kept separately so that clearing one
## leaves the others in force: the headset put back on while the menu is
## still open stays paused until the menu closes, and the other way round.
var _pause_reasons: Dictionary[String, bool] = {}

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
## Copies of `sim.robots` after the tick before the latest one and after it.
var _previous_robots: Array[RobotState] = []
var _current_robots: Array[RobotState] = []
## Copies of `sim.salvage` after the tick before the latest one and after it.
var _previous_salvage: Array[SalvageItem] = []
var _current_salvage: Array[SalvageItem] = []


## Builds the replay and sim from data; see `SessionLoader.build` for what
## each argument does (CMB-1, CMB-3, SLV-1, DEV-6, ARC-2).
func _init(run_seed: int = 0, input_source: ShipInputSource = null, bounds: BoxBounds = null,
		tuning: ShipTuning = null, robots: Array[RobotSpawn] = [], loadout: ShipLoadout = null,
		parts: Dictionary[String, WeaponDef] = {}) -> void:
	SessionLoader.build(self, run_seed, bounds, tuning, robots, loadout, parts)
	_input_source = input_source if input_source != null else ShipInputSource.new()
	reset_ship_snapshots()
	_current_robots = SessionSnapshots.robots(sim.robots)
	_previous_robots = _current_robots
	_current_salvage = SessionSnapshots.salvage(sim.salvage)
	_previous_salvage = _current_salvage


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


## Holds the pause for `reason` or lets it go. Only the last reason to go
## resumes, and only then is the next frame limited to one tick.
func set_paused(reason: String, held: bool) -> void:
	var was_paused: bool = paused
	if held:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	if was_paused and not paused:
		_resuming = true


## Whether `reason` is one of the reasons holding the pause now.
func paused_by(reason: String) -> bool:
	return _pause_reasons.has(reason)


## The data loaders below forward to `SpawnLoader` and `SessionLoader`, which
## build sessions without the local tick (#1156); callers keep these names.
static func load_tuning(path: String, weapon_dir: String = WEAPON_DIR) -> ShipTuning:
	return SpawnLoader.load_tuning(path, weapon_dir)


static func load_parts(weapon_dir: String = WEAPON_DIR) -> Dictionary[String, WeaponDef]:
	return SpawnLoader.load_parts(weapon_dir)


static func load_spawns(path: String, robot_dir: String = ROBOT_DIR,
		weapon_dir: String = ROBOT_WEAPON_DIR) -> Array[RobotSpawn]:
	return SpawnLoader.load_spawns(path, robot_dir, weapon_dir)


static func for_level(level: LevelDef, run_seed: int = 0, input_source: ShipInputSource = null,
		tuning: ShipTuning = null, robot_dir: String = ROBOT_DIR,
		weapon_dir: String = WEAPON_DIR, robot_weapon_dir: String = ROBOT_WEAPON_DIR) -> LocalSession:
	return SessionLoader.for_level(level, run_seed, input_source, tuning, robot_dir, weapon_dir,
		robot_weapon_dir)


## Gives the run `rules` for picking up, pulling and dropping parts and records
## them in the replay (#600). Before the first tick only; null keeps the
## defaults. Sessions in a level get the shipped file from `for_level`.
## Returns this session, so a field can be built and given rules in one line.
func use_salvage_rules(rules: SalvageRules) -> LocalSession:
	if rules != null and sim.set_salvage_rules(rules) == "":
		replay.salvage_rules = rules
	return self


## Takes the ship's snapshots again from the sim. Call it after moving the ship
## before the first tick (a start pose), so the view does not draw it gliding
## from where it was built.
func reset_ship_snapshots() -> void:
	_current_ship = SessionSnapshots.ship(sim.ships[0])
	_previous_ship = SessionSnapshots.ship(sim.ships[0])


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


## Every robot after the tick before the latest one, in the simulation's
## order. A new array of copies: changing it leaves the simulation as it was.
func previous_robots() -> Array[RobotState]:
	return _previous_robots.duplicate()


## Every robot after the latest tick, like `previous_robots()`.
func current_robots() -> Array[RobotState]:
	return _current_robots.duplicate()


## Every floating part after the tick before the latest one, in the
## simulation's order. A new array of copies, like `previous_robots()`.
func previous_salvage() -> Array[SalvageItem]:
	return _previous_salvage.duplicate()


## Every floating part after the latest tick, like `previous_salvage()`.
func current_salvage() -> Array[SalvageItem]:
	return _current_salvage.duplicate()


func _run_tick() -> void:
	var inputs: Array[ShipInput] = [_input_source.next_input(sim.tick)]
	sim.step(inputs)
	_frame_events.append_array(sim.last_events)
	replay.add_tick(inputs)
	_accumulator -= ShipState.TICK_DT
	_previous_ship = _current_ship
	_current_ship = SessionSnapshots.ship(sim.ships[0])
	_snapshot_projectiles()
	_previous_robots = _current_robots
	_current_robots = SessionSnapshots.robots(sim.robots)
	_previous_salvage = _current_salvage
	_current_salvage = SessionSnapshots.salvage(sim.salvage)


## Drops the whole ticks left in the accumulator and keeps the fraction, so the
## interpolation stays smooth across the hitch.
func _drop_whole_ticks() -> void:
	var whole_ticks: float = floorf((_accumulator + TICK_EPSILON) / ShipState.TICK_DT)
	var dropped: float = whole_ticks * ShipState.TICK_DT
	dropped_seconds += dropped
	_accumulator = maxf(_accumulator - dropped, 0.0)


## Refreshes `_current_projectiles` from `sim.projectiles`, keeping each
## projectile's copy from tick to tick.
func _snapshot_projectiles() -> void:
	_projectile_copies = SessionSnapshots.projectiles(sim.projectiles, _projectile_copies)
	var listed: Array[Projectile] = []
	listed.assign(_projectile_copies.values())
	_current_projectiles = listed
