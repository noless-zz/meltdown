class_name Replay
extends RefCounted

## A recorded run: seed plus the inputs of every ship for every tick.
##
## Text format, one item per line:
##
##     meltdown-replay 4        format name and version
##     seed 20261114            run seed
##     ships 1                  number of ships
##     hash 1234567890          optional: expected Sim.state_hash() at the end
##     box -5000 -5000 -40000 5000 5000 5000
##                              optional (version 3): walls the ships fly
##                              inside, min then max corner in millimetres
##     inputs                   end of header
##     0 0 -1000 0 250 0 1 0    one line per tick: thrust x y z, turn x y z,
##                              afterburner, reset to start (0 off, 1 on)
##     0 0 -1000 0 0 0 0 0 | ...
##                              further ships follow after " | "
##
## Version 1 has no afterburner column: six numbers per ship, read with the
## afterburner off. Versions 1 to 3 have no reset column and are read with it
## off. Versions 1 and 2 have no box line. Files are always written as the
## current version.
##
## Numbers are the integers of `ShipInput`, so saving and loading is exact.
## Blank lines and lines starting with `#` are ignored.

const FORMAT_NAME: String = "meltdown-replay"
const FORMAT_VERSION: int = 4
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
## Whether the run has walls; if so, their corners in millimetres.
var has_box: bool = false
var box_min_mm: Vector3i = Vector3i.ZERO
var box_max_mm: Vector3i = Vector3i.ZERO
## One entry per tick; each entry is an Array[ShipInput] with one input per ship.
var frames: Array[Array] = []
## Set by `from_text` and `load_file` when the text could not be parsed.
var error: String = ""
## Set by `run` when a frame was rejected; empty after a complete run.
var run_error: String = ""
## Version of the text being parsed; decides how many numbers a ship has.
var _parse_version: int = FORMAT_VERSION


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
## Returns null, with `run_error` set, if any frame does not hold exactly one
## input per ship: a `Sim` that skipped a tick would still give a hash, for a
## simulation that never ran, and nothing downstream could tell.
func run() -> Sim:
	run_error = ""
	var sim: Sim = Sim.new(run_seed, ship_count, bounds())
	for index: int in frames.size():
		var inputs: Array[ShipInput] = []
		inputs.assign(frames[index])
		if not sim.step(inputs):
			run_error = "tick %d: expected inputs for %d ships, found %d" % [
				index, ship_count, inputs.size()]
			return null
	return sim


## Gives the run walls, from corners in millimetres.
func set_box(min_mm: Vector3i, max_mm: Vector3i) -> void:
	has_box = true
	box_min_mm = min_mm
	box_max_mm = max_mm


## The walls of this run as a `BoxBounds`, or null without a box line.
func bounds() -> BoxBounds:
	if not has_box:
		return null
	return BoxBounds.new(Vector3(box_min_mm) / float(BOX_SCALE), Vector3(box_max_mm) / float(BOX_SCALE))


func to_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s %d" % [FORMAT_NAME, FORMAT_VERSION])
	lines.append("seed %d" % run_seed)
	lines.append("ships %d" % ship_count)
	if expected_hash != NO_HASH:
		lines.append("hash %d" % expected_hash)
	if has_box:
		lines.append("box %d %d %d %d %d %d" % [
			box_min_mm.x, box_min_mm.y, box_min_mm.z, box_max_mm.x, box_max_mm.y, box_max_mm.z])
	lines.append("inputs")
	for frame: Array in frames:
		var parts: PackedStringArray = PackedStringArray()
		for input: ShipInput in frame:
			var t: Vector3i = input.thrust_q
			var r: Vector3i = input.turn_q
			parts.append("%d %d %d %d %d %d %d %d" % [
				t.x, t.y, t.z, r.x, r.y, r.z,
				1 if input.afterburner else 0, 1 if input.reset_to_start else 0])
		lines.append(SHIP_SEPARATOR.join(parts))
	return "\n".join(lines) + "\n"


## Parses replay text. On failure the returned replay has `error` set.
static func from_text(text: String) -> Replay:
	var replay: Replay = Replay.new()
	var in_header: bool = true
	var seen: Dictionary[String, bool] = {}
	var line_number: int = 0
	for raw_line: String in text.split("\n"):
		line_number += 1
		var line: String = raw_line.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var problem: String = ""
		if in_header:
			if line == "inputs":
				in_header = false
				if not (seen.has("seed") and seen.has("ships")):
					problem = "header needs both seed and ships"
			else:
				problem = replay._parse_header_line(line, seen)
		else:
			problem = replay._parse_tick_line(line)
		if problem != "":
			replay.error = "line %d: %s" % [line_number, problem]
			return replay
	if in_header:
		replay.error = "no inputs section"
	return replay


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


func _parse_header_line(line: String, seen: Dictionary[String, bool]) -> String:
	var words: PackedStringArray = line.split(" ", false)
	if words.size() > 0 and words[0] == "box":
		return _parse_box_line(words, seen)
	if words.size() != 2 or not words[1].is_valid_int():
		return "expected a name and one whole number"
	var key: String = words[0]
	var value: int = words[1].to_int()
	# The format line must come first so that a file of another kind, or of a
	# newer version whose keys mean something else, is rejected before use.
	if seen.is_empty() != (key == FORMAT_NAME):
		return "the first line must be '%s <version>'" % FORMAT_NAME
	if seen.has(key):
		return "'%s' appears twice" % key
	seen[key] = true
	match key:
		FORMAT_NAME:
			if value < OLDEST_VERSION or value > FORMAT_VERSION:
				return "unsupported format version %d" % value
			_parse_version = value
		"seed":
			run_seed = value
		"ships":
			if value < 1:
				return "ships must be at least 1"
			ship_count = value
		"hash":
			# State hashes are never negative, and NO_HASH is. Reading
			# "hash -1" as "no hash" would switch the check off silently.
			if value < 0:
				return "hash must not be negative"
			expected_hash = value
		_:
			return "unknown header line '%s'" % key
	return ""


func _parse_box_line(words: PackedStringArray, seen: Dictionary[String, bool]) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % FORMAT_NAME
	if _parse_version < 3:
		return "a box line needs format version 3 or later"
	if seen.has("box"):
		return "'box' appears twice"
	seen["box"] = true
	if words.size() != 7:
		return "box needs six whole numbers"
	var values: Array[int] = []
	for index: int in range(1, 7):
		if not words[index].is_valid_int():
			return "'%s' is not a whole number" % words[index]
		values.append(words[index].to_int())
	var min_mm: Vector3i = Vector3i(values[0], values[1], values[2])
	var max_mm: Vector3i = Vector3i(values[3], values[4], values[5])
	if min_mm.x >= max_mm.x or min_mm.y >= max_mm.y or min_mm.z >= max_mm.z:
		return "box min corner must be below its max corner on every axis"
	set_box(min_mm, max_mm)
	return ""


func _parse_tick_line(line: String) -> String:
	var groups: PackedStringArray = line.split("|")
	if groups.size() != ship_count:
		return "expected inputs for %d ships, found %d" % [ship_count, groups.size()]
	var expected: int = _numbers_per_ship(_parse_version)
	var inputs: Array[ShipInput] = []
	for group: String in groups:
		var words: PackedStringArray = group.split(" ", false)
		if words.size() != expected:
			return "each ship needs %d numbers, found %d" % [expected, words.size()]
		var values: Array[int] = []
		for word: String in words:
			if not word.is_valid_int():
				return "'%s' is not a whole number" % word
			values.append(word.to_int())
		# Only 0 and 1 are accepted, so a typo cannot be read as "on".
		var afterburner: int = values[6] if expected >= 7 else 0
		if afterburner != 0 and afterburner != 1:
			return "afterburner must be 0 or 1, found %d" % afterburner
		var reset: int = values[7] if expected >= 8 else 0
		if reset != 0 and reset != 1:
			return "reset must be 0 or 1, found %d" % reset
		inputs.append(ShipInput.new(
			Vector3i(values[0], values[1], values[2]),
			Vector3i(values[3], values[4], values[5]),
			afterburner == 1, reset == 1))
	frames.append(inputs)
	return ""


static func _numbers_per_ship(version: int) -> int:
	if version == 1:
		return 6
	if version <= 3:
		return 7
	return 8
