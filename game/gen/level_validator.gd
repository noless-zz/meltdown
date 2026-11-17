class_name LevelValidator
extends RefCounted

## Automatic checks every generated level must pass before it is flown (GEN-3,
## GEN-5): one connected piece, every opening wide enough, every box reachable
## from the start, and the start held inside a box. `validate` returns one
## message per failure, each starting with the check's name and naming the box
## or boxes; an empty list means the level passes. Reactor and escape-time
## checks follow once the generator places a reactor.
##
## Its setting is data (ARC-4), read from `data/gen/validator.json`:
##
##     {"min_passage_ship_diameters": 2.5}
##
## The narrowest opening allowed is that many ship collision diameters. The
## caller hands over the file's text and the ship's radius, because `gen/`
## never opens files.
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

const KEYS: Array[String] = ["min_passage_ship_diameters"]
## Accepted range for `min_passage_ship_diameters`.
const MIN_DIAMETERS: float = 1.0
const MAX_DIAMETERS: float = 20.0

## Narrowest opening allowed, in ship collision diameters.
var min_passage_ship_diameters: float = 2.5
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
	validator.error = LevelDef._check_keys(data, KEYS)
	if validator.error != "":
		return validator
	var value: Variant = data["min_passage_ship_diameters"]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		validator.error = "key \"min_passage_ship_diameters\" must be a number"
	elif float(value) < MIN_DIAMETERS or float(value) > MAX_DIAMETERS:
		validator.error = "key \"min_passage_ship_diameters\" must be %s..%s" % [MIN_DIAMETERS, MAX_DIAMETERS]
	else:
		validator.min_passage_ship_diameters = float(value)
	return validator


## Narrowest opening allowed for a ship of `ship_radius`, metres.
func min_passage(ship_radius: float) -> float:
	return min_passage_ship_diameters * 2.0 * ship_radius


## The level's failures for a ship of `ship_radius`; empty when it passes.
func validate(level: LevelDef, ship_radius: float) -> Array[String]:
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
	var start_box: int = -1
	for index: int in boxes.size():
		if boxes[index].holds(level.start_position(), ship_radius):
			start_box = index
			break
	if start_box < 0:
		failures.append("start: position %s is not held by any box with %s m to spare"
				% [level.start_position(), ship_radius])
		return failures
	for index: int in LevelValidator._unreached(start_box, passable):
		failures.append("reachable: box %d cannot be reached from start box %d" % [index, start_box])
	return failures


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
