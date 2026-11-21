class_name Replay
extends RefCounted

## A recorded run: seed plus the inputs of every ship for every tick.
##
## Text format, one item per line:
##
##     meltdown-replay 17       format name and version
##     seed 20261114            run seed
##     ships 1                  number of ships
##     hash 1234567890          optional: expected Sim.state_hash() at the end
##     box -5000 -5000 -40000 5000 5000 5000
##                              optional (version 3): walls the ships fly
##                              inside, min then max corner in millimetres;
##                              from version 12 one line per box of the level,
##                              in order, read as one `BoxUnion`
##     reactor {"position":[0,-39,-114],...}
##                              optional (version 13): the level's reactor
##                              before the first tick (`ReactorState`)
##     debris [{"position":[0,-15,-45],...}]
##                              optional (version 15): `ReplayDebrisLine`
##     start 0 3000 -2000 10000 1000 0 0
##                              optional (version 14), at most one per ship:
##                              ship index, start position in millimetres and
##                              facing as a unit vector in thousandths; without
##                              it the ship starts at the origin facing -z
##                              (`ReplayStartLine`)
##     tuning {"max_speed":20.0,...}
##                              optional (version 5): every ship's feel values,
##                              as a one-line ship data file (`ShipTuning`)
##     weapon primary 1 pulse_cannon {"fire_interval_ticks":10,...}
##                              optional (version 7), one per filled slot:
##                              kind, slot 1 or 2, weapon id and the weapon's
##                              data file on one line; every ship starts with
##                              these weapons (`ShipLoadout`)
##     robot 0 500 -16000 0 0 1000 {"robot":{"id":"drone",...},"weapon":{...}}
##                              optional (version 8), one per robot in spawn
##                              order: position and facing in millimetres, then
##                              the robot's data file under "robot" and its
##                              resolved weapon's values under "weapon" (null
##                              when unarmed); every run starts with these
##                              robots (`RobotSpawn`)
##     part pulse_cannon {"fire_interval_ticks":10,...}
##                              optional (version 10), one per part of the
##                              catalogue, sorted by id: part id and the
##                              weapon's data file on one line (`Sim.set_parts`)
##     salvage {"pickup_reach":2.5,...}
##                              optional (version 16): `ReplaySalvageLine`
##     aim {"cone_degrees":35.0,...}
##                              optional (version 17): `ReplayAimLine`
##     inputs                   end of header
##     0 0 -1000 0 250 0 1 0 1 0
##                              one line per tick: thrust x y z, turn x y z,
##                              afterburner, reset to start, fire primary,
##                              slot held part (0 off, 1 on); from version 17
##                              then aim x y z only when it is off the nose
##     0 0 -1000 0 0 0 0 0 0 0 | ...
##                              further ships follow after " | "
##
## Older versions lack some columns and lines; `ReplayHeader` lists which.
## Files are always written as the current version.
##
## Numbers are the integers of `ShipInput`, so saving and loading is exact.
## Blank lines and lines starting with `#` are ignored.

const FORMAT_NAME: String = "meltdown-replay"
const FORMAT_VERSION: int = 17
## Oldest version `from_text` still reads.
const OLDEST_VERSION: int = 1
const NO_HASH: int = -1
const SHIP_SEPARATOR: String = " | "
## Millimetres per metre in the box line. Whole millimetres keep the text exact.
const BOX_SCALE: int = 1000

var run_seed: int = 0
var ship_count: int = 1
## Final state hash this replay is expected to produce, or NO_HASH.
var expected_hash: int = NO_HASH
## Whether the run has walls; if so, the first box's corners in millimetres.
var has_box: bool = false
var box_min_mm: Vector3i = Vector3i.ZERO
var box_max_mm: Vector3i = Vector3i.ZERO
## Corners of every box in order, in millimetres. Change them with `set_box`,
## `add_box` or `set_boxes`.
var box_mins_mm: Array[Vector3i] = []
var box_maxs_mm: Array[Vector3i] = []
## Start pose of each ship with a start line, by ship index: position in
## millimetres and facing in thousandths. Change them with `set_start_pose`.
var start_positions_mm: Dictionary[int, Vector3i] = {}
var start_facings_mm: Dictionary[int, Vector3i] = {}
## The level's reactor before the first tick, or null. Each run gets a copy.
var reactor: ReactorState = null
## The level's falling debris (RUN-4), or null. Each run gets a copy.
var debris: MeltdownDebris = null
## Feel values of every ship from the first tick, or null for the defaults.
var tuning: ShipTuning = null
## Weapons every ship starts with, already resolved, or null for none.
var loadout: ShipLoadout = null
## Robots placed before the first tick, in spawn order, each resolved.
var robots: Array[RobotSpawn] = []
## The part catalogue the run starts with: part id to resolved weapon.
var parts: Dictionary[String, WeaponDef] = {}
## How parts are picked up, pulled and dropped, or null for the defaults.
var salvage_rules: SalvageRules = null
## Look-aim cone and gimbal rate (CMB-6), or null for the defaults.
var look_aim: LookAim = null
## One entry per tick; each entry is an Array[ShipInput] with one input per ship.
var frames: Array[Array] = []
## Set by `from_text` and `load_file` when the text could not be parsed.
var error: String = ""
## Set by `run` when a frame was rejected; empty after a complete run.
var run_error: String = ""
## Version of the text being parsed; decides how many numbers a ship has and
## which lines may appear. Set by the format line.
var parse_version: int = FORMAT_VERSION


func _init(p_run_seed: int = 0, p_ship_count: int = 1) -> void:
	run_seed = p_run_seed
	ship_count = p_ship_count


## Appends one tick. Returns false if there is not one input per ship.
func add_tick(inputs: Array[ShipInput]) -> bool:
	if inputs.size() != ship_count:
		return false
	frames.append(inputs.duplicate())
	return true


## Simulates the whole replay from a fresh `Sim` and returns it.
## Returns null, with `run_error` set, if the part catalogue is refused or if
## any frame does not hold exactly one input per ship: a `Sim` that skipped a
## tick would still give a hash, for a simulation that never ran, and nothing
## downstream could tell.
func run() -> Sim:
	run_error = ""
	var sim: Sim = Sim.new(run_seed, ship_count, null)
	ReplayStartLine.apply(self, sim)
	# A one-box union is exactly what the constructor builds from one box.
	sim.set_walls(walls())
	sim.set_reactor(null if reactor == null else reactor.fresh_copy())
	sim.set_debris(null if debris == null else debris.fresh_copy())
	apply_tuning(sim)
	if loadout != null:
		sim.equip(loadout)
	RobotSpawn.spawn_all(sim, robots)
	var parts_problem: String = sim.set_parts(parts)
	if parts_problem != "":
		run_error = parts_problem
		return null
	if salvage_rules != null:
		sim.set_salvage_rules(salvage_rules)
	ReplayAimLine.apply(self, sim)
	for index: int in frames.size():
		var inputs: Array[ShipInput] = []
		inputs.assign(frames[index])
		if not sim.step(inputs):
			run_error = "tick %d: expected inputs for %d ships, found %d" % [
				index, ship_count, inputs.size()]
			return null
	return sim


## Gives the run walls of one box, from corners in millimetres, replacing any
## boxes it had.
func set_box(min_mm: Vector3i, max_mm: Vector3i) -> void:
	box_mins_mm.clear()
	box_maxs_mm.clear()
	add_box(min_mm, max_mm)


## Adds a box after the run's other boxes, from corners in millimetres.
func add_box(min_mm: Vector3i, max_mm: Vector3i) -> void:
	box_mins_mm.append(min_mm)
	box_maxs_mm.append(max_mm)
	has_box = true
	box_min_mm = box_mins_mm[0]
	box_max_mm = box_maxs_mm[0]


## Gives the run walls of every box in order, `mins_mm[i]` and `maxs_mm[i]`
## being the corners of box i in millimetres. Returns false, changing nothing,
## unless both lists hold the same number of boxes, at least one.
func set_boxes(mins_mm: Array[Vector3i], maxs_mm: Array[Vector3i]) -> bool:
	if mins_mm.is_empty() or mins_mm.size() != maxs_mm.size():
		return false
	box_mins_mm.clear()
	box_maxs_mm.clear()
	for index: int in mins_mm.size():
		add_box(mins_mm[index], maxs_mm[index])
	return true


## Records where ship `ship_index` starts and resets to: `position` in metres,
## kept to the millimetre, and `facing` of any non-zero length, kept as a unit
## vector in thousandths. Returns false, changing nothing, for an index
## outside the ships or a zero facing. A live run that is to replay exactly
## must be given the pose read back by `ReplayStartLine.position` and
## `ReplayStartLine.orientation`.
func set_start_pose(ship_index: int, position: Vector3, facing: Vector3) -> bool:
	if ship_index < 0 or ship_index >= ship_count or facing.is_zero_approx():
		return false
	start_positions_mm[ship_index] = ReplayStartLine.position_mm(position)
	start_facings_mm[ship_index] = ReplayStartLine.facing_mm(facing)
	return true


## Gives every ship of `sim` this run's tuning, if it has one. Call it before
## the first tick: it refills energy, hull and shield.
func apply_tuning(sim: Sim) -> void:
	if tuning == null:
		return
	for ship: ShipState in sim.ships:
		tuning.apply_to(ship)


## The first box of the walls, or null without a box line.
func bounds() -> BoxBounds:
	if not has_box:
		return null
	return ReplayBoxLine.box(box_mins_mm[0], box_maxs_mm[0])


## Every box of the walls, in order, or null without a box line.
func walls() -> BoxUnion:
	if not has_box:
		return null
	return ReplayBoxLine.union(box_mins_mm, box_maxs_mm)


func to_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s %d" % [FORMAT_NAME, FORMAT_VERSION])
	lines.append("seed %d" % run_seed)
	lines.append("ships %d" % ship_count)
	if expected_hash != NO_HASH:
		lines.append("hash %d" % expected_hash)
	for index: int in box_mins_mm.size():
		lines.append(ReplayBoxLine.text(box_mins_mm[index], box_maxs_mm[index]))
	if reactor != null:
		lines.append(ReplayReactorLine.text(reactor))
	if debris != null and debris.size() > 0:
		lines.append(ReplayDebrisLine.text(debris))
	lines.append_array(ReplayStartLine.lines(self))
	if tuning != null:
		lines.append(ReplayLines.tuning_text(tuning))
	if loadout != null:
		lines.append_array(ReplayLines.weapon_lines(loadout))
	for spawn: RobotSpawn in robots:
		lines.append(ReplayLines.robot_text(spawn))
	lines.append_array(ReplayPartLines.part_lines(parts))
	if salvage_rules != null:
		lines.append(ReplaySalvageLine.text(salvage_rules))
	lines.append_array(ReplayAimLine.lines(self))
	lines.append("inputs")
	for frame: Array in frames:
		lines.append(ReplayLines.tick_text(frame))
	return "\n".join(lines) + "\n"


## Parses replay text. On failure the returned replay has `error` set.
static func from_text(text: String) -> Replay:
	return ReplayHeader.read_text(text)


func save(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_text())
	file.close()
	return OK


static func load_file(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		var missing: Replay = Replay.new()
		missing.error = "cannot open %s" % path
		return missing
	return from_text(FileAccess.get_file_as_string(path))
