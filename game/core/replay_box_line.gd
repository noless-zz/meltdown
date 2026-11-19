class_name ReplayBoxLine
extends RefCounted

## Writes and reads a replay's box lines (version 3, one per box of the level
## from version 12) and turns the corners a replay holds into walls. Split out
## of `Replay` and `ReplayLines`, which were at their size limit (#328); the
## format is documented in `Replay`.

## First format version that may carry a box line.
const VERSION: int = 3
## First format version that may carry several box lines, one per box.
const MULTI_BOX_VERSION: int = 12


## `box <min x y z> <max x y z>`, in whole millimetres.
static func text(min_mm: Vector3i, max_mm: Vector3i) -> String:
	return "box %d %d %d %d %d %d" % [min_mm.x, min_mm.y, min_mm.z, max_mm.x, max_mm.y, max_mm.z]


## `words` is the whole line split on spaces, starting with "box". Returns ""
## with the box added to `replay`, or a problem without the line number, which
## `Replay.from_text` adds.
static func parse(replay: Replay, words: PackedStringArray,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a box line needs format version %d or later" % VERSION
	if seen.has("box") and version < MULTI_BOX_VERSION:
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
	replay.add_box(min_mm, max_mm)
	return ""


## One box in metres from its corners in millimetres.
static func box(min_mm: Vector3i, max_mm: Vector3i) -> BoxBounds:
	return BoxBounds.new(Vector3(min_mm) / float(Replay.BOX_SCALE),
		Vector3(max_mm) / float(Replay.BOX_SCALE))


## Every box, in order, as one union; null when there are none.
static func union(mins_mm: Array[Vector3i], maxs_mm: Array[Vector3i]) -> BoxUnion:
	if mins_mm.is_empty():
		return null
	var list: Array[BoxBounds] = []
	for index: int in mins_mm.size():
		list.append(box(mins_mm[index], maxs_mm[index]))
	return BoxUnion.new(list)
