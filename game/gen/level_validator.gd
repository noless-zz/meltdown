class_name LevelValidator
extends RefCounted

## Automatic checks every generated level must pass before it is flown (GEN-3,
## GEN-5): one connected piece, every opening wide enough, every box reachable
## from the start, the start held inside a box, a reactor with room around it in
## a reachable box, an escape from the reactor to the exit that fits the
## meltdown countdown (`EscapeChecks`) and still fits it once the meltdown debris
## the route guard lets fall is down (`DebrisEscape`, #493), a generated level's
## reactor far from the start (`ReactorFar`, #912), and robots with room around them in
## reachable boxes outside the start module (`RobotChecks`, #399), and trapped
## miners in reachable boxes (`MinerChecks`, #938). `validate` returns one message per failure, each starting
## with the check's name (`CHECKS`) and naming the box or boxes; an empty list
## means the level passes.
##
## Its settings are data (ARC-4), read from `data/gen/validator.json`:
##
##     {"min_passage_ship_diameters": 2.5, "escape_speed_mps": 10, "escape_margin": 0.8}
##
## The narrowest opening allowed is that many ship collision diameters. The
## escape is flown at `escape_speed_mps` along `EscapePath` from the reactor to
## the exit, which is the start (RUN-3), and must take no more than
## `escape_margin` of the countdown the level would start for that path (RUN-5:
## `ReactorState.meltdown_ticks_for_path`, so `meltdown_seconds` when the level
## does not scale the timer). The margin leaves time for the fight on the way
## out and for a pilot slower than the assumed speed. The caller hands over the
## file's text and the ship's radius, because `gen/` never opens files.
##
## Two boxes that share volume meet at an opening: the region they share. A
## ship crosses it along an axis where the boxes lie on opposite sides (one
## reaches further below, the other further above); the region's sides across
## that axis are the opening's width "in both directions", and both must reach
## the minimum. With several such axes the one where the region is thinnest is
## taken; with none (one box wraps the other on every axis) the region's
## thinnest side. A ship can cross from one box to the other only where they are
## also `LevelDef.joined`, so reachability follows only openings that are both
## joined and wide enough. Boxes are visited in index order, so the same level
## always gives the same messages in the same order (ARC-2).

const KEYS: Array[String] = ["min_passage_ship_diameters", "escape_speed_mps", "escape_margin"]
## Accepted range of each key, inclusive, as [lowest, highest]. Plain floats,
## not a Vector2, whose single precision would move 0.1.
const RANGES: Dictionary[String, Array] = {
	"min_passage_ship_diameters": [1.0, 20.0],
	"escape_speed_mps": [1.0, 100.0],
	"escape_margin": [0.1, 1.0],
}
## Every check's name, in the order `validate` reports them.
const CHECKS: Array[String] = ["piece", "passage", "start", "reachable", "reactor", "escape",
		"debris_escape", ReactorFar.CHECK, "robots", MinerChecks.CHECK]

## Narrowest opening allowed, in ship collision diameters.
var min_passage_ship_diameters: float = 2.5
## Speed the escape is assumed to be flown at, metres a second.
var escape_speed_mps: float = 10.0
## Share of the countdown the escape may take.
var escape_margin: float = 0.8
## Share of the longest candidate escape path a generated level's reactor
## must reach (`ReactorFar`, #912). Not in this file: it is the reactor plan's
## `min_escape_fraction`, which `SeedLevel` hands over, as it hands the debris
## plan this validator.
var min_escape_fraction: float = 0.0
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the validator's data file. On failure `error` is set and the
## defaults stay, so a caller that ignores the error still checks something.
static func parse_json(text: String) -> LevelValidator:
	var validator: LevelValidator = LevelValidator.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		validator.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return validator
	if typeof(json.data) != TYPE_DICTIONARY:
		validator.error = "top level must be a JSON object"
		return validator
	var data: Dictionary = json.data
	validator.error = LevelValidator._check_keys(data)
	if validator.error != "":
		return validator
	var read: Dictionary[String, float] = {}
	for key: String in KEYS:
		var value: Variant = data[key]
		var allowed: Array = RANGES[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT or not is_finite(float(value)):
			validator.error = "key \"%s\" must be a number" % key
			return validator
		if float(value) < float(allowed[0]) or float(value) > float(allowed[1]):
			validator.error = "key \"%s\" must be %s..%s" % [key, allowed[0], allowed[1]]
			return validator
		read[key] = float(value)
	validator.min_passage_ship_diameters = read["min_passage_ship_diameters"]
	validator.escape_speed_mps = read["escape_speed_mps"]
	validator.escape_margin = read["escape_margin"]
	return validator


## "" or the first unknown key, else every missing key, so a file from before
## a key was added names all it lacks at once.
static func _check_keys(data: Dictionary) -> String:
	for key: Variant in data:
		if not KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("missing key \"%s\"" % key)
	return ", ".join(missing)


## Narrowest opening allowed for a ship of `ship_radius`, metres.
func min_passage(ship_radius: float) -> float:
	return min_passage_ship_diameters * 2.0 * ship_radius


## The level's failures for a ship of `ship_radius`; empty when it passes.
## `check_reactor` false leaves out the `reactor`, `escape` and `debris_escape` checks, for
## hand-built test levels that have no reactor. `robot_radii_mm` gives the
## radius of unresolved robots by type id (`RobotPlan.radii_by_id`);
## `start_module` lists the boxes of the module the start is in, and when it is
## empty (a hand-built level has no modules) the box holding the start stands
## for it. `on_check`, when valid, is called with a check's name each time that
## check is done ("piece" also covers "passage", "reachable" also "start" and
## "escape" also "reactor" and "reactor_far", "robots" also "miners_reachable",
## which are worked out together), so a sweep can time
## each one (#513); the validator itself never reads a clock (ARC-1).
func validate(level: LevelDef, ship_radius: float, check_reactor: bool = true,
		robot_radii_mm: Dictionary[String, int] = {}, start_module: Array[int] = [],
		on_check: Callable = Callable()) -> Array[String]:
	var failures: Array[String] = []
	var boxes: Array[BoxBounds] = level.union.boxes
	if boxes.is_empty():
		failures.append("piece: the level has no boxes")
		return failures
	var narrowest: float = min_passage(ship_radius)
	# For each box, the boxes it shares volume with, and those a ship can enter.
	var touching: Array[Array] = []
	var passable: Array[Array] = []
	for index: int in boxes.size():
		touching.append([])
		passable.append([])
	for a: int in boxes.size():
		for b: int in range(a + 1, boxes.size()):
			var shared: Vector3 = LevelValidator.shared_size(boxes[a], boxes[b])
			if shared.x <= 0.0 or shared.y <= 0.0 or shared.z <= 0.0:
				continue
			touching[a].append(b)
			touching[b].append(a)
			var widths: Vector2 = LevelValidator.opening_widths(boxes[a], boxes[b], shared)
			if widths.x < narrowest:
				failures.append("passage: boxes %d and %d open %.2f x %.2f m, below %.2f m"
						% [a, b, widths.x, widths.y, narrowest])
			elif LevelDef.joined(boxes[a], boxes[b]):
				passable[a].append(b)
				passable[b].append(a)
	for index: int in LevelValidator._unreached(0, touching):
		failures.append("piece: box %d is not connected to box 0" % index)
	LevelValidator._done(on_check, "piece")
	var start_box: int = -1
	for index: int in boxes.size():
		if boxes[index].holds(level.start_position(), ship_radius):
			start_box = index
			break
	if start_box < 0:
		failures.append("start: position %s is not held by any box with %s m to spare"
				% [level.start_position(), ship_radius])
		return failures
	var unreached: Array[int] = LevelValidator._unreached(start_box, passable)
	for index: int in unreached:
		failures.append("reachable: box %d cannot be reached from start box %d" % [index, start_box])
	LevelValidator._done(on_check, "reachable")
	if check_reactor:
		var escape: Array[String] = EscapeChecks.failures(level, ship_radius, start_box, unreached,
				escape_speed_mps, escape_margin)
		failures.append_array(escape)
		var far: String = ReactorFar.failure(level, ship_radius, min_escape_fraction)
		if far != "":
			failures.append(far)
		LevelValidator._done(on_check, "escape")
		# Only a level whose clear escape fits is timed again with debris fallen.
		if escape.is_empty():
			var late: String = DebrisEscape.failure(level, level.debris, ship_radius,
					escape_speed_mps, escape_margin)
			if late != "":
				failures.append(late)
			LevelValidator._done(on_check, DebrisEscape.CHECK)
	var module: Array[int] = start_module.duplicate()
	if module.is_empty():
		module.append(start_box)
	failures.append_array(RobotChecks.failures(level, ship_radius, start_box, unreached,
			robot_radii_mm, module))
	# Timed with the robots: the sweep's stages predate the miners (#938).
	failures.append_array(MinerChecks.failures(level, start_box, unreached))
	LevelValidator._done(on_check, "robots")
	return failures


static func _done(on_check: Callable, check: String) -> void:
	if on_check.is_valid():
		on_check.call(check)


## Size of the region two boxes share on each axis; zero or less on an axis
## where they do not overlap.
static func shared_size(a: BoxBounds, b: BoxBounds) -> Vector3:
	var size: Vector3 = Vector3.ZERO
	for axis: int in 3:
		size[axis] = minf(a.max_corner[axis], b.max_corner[axis]) - maxf(a.min_corner[axis], b.min_corner[axis])
	return size


## The opening's two widths, narrower first: the shared region's sides other
## than the one along the crossing axis (see the class comment).
static func opening_widths(a: BoxBounds, b: BoxBounds, shared: Vector3) -> Vector2:
	var crossing: Array[int] = []
	for axis: int in 3:
		var a_lower: bool = a.min_corner[axis] < b.min_corner[axis] and a.max_corner[axis] < b.max_corner[axis]
		var b_lower: bool = b.min_corner[axis] < a.min_corner[axis] and b.max_corner[axis] < a.max_corner[axis]
		if a_lower or b_lower:
			crossing.append(axis)
	if crossing.is_empty():
		crossing = [0, 1, 2]
	var depth: int = crossing[0]
	for axis: int in crossing:
		if shared[axis] < shared[depth]:
			depth = axis
	var first: float = shared[(depth + 1) % 3]
	var second: float = shared[(depth + 2) % 3]
	return Vector2(minf(first, second), maxf(first, second))


## Boxes not reachable from `from` through `links`, lowest index first.
static func _unreached(from: int, links: Array[Array]) -> Array[int]:
	var reached: Array[bool] = []
	reached.resize(links.size())
	reached.fill(false)
	reached[from] = true
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for other: int in links[index]:
			if not reached[other]:
				reached[other] = true
				queue.append(other)
	var missing: Array[int] = []
	for index: int in reached.size():
		if not reached[index]:
			missing.append(index)
	return missing
