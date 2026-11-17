class_name OpeningClearance
extends RefCounted

## Whether solid meltdown debris blocks the opening between two boxes (MAP-2,
## RUN-4): an opening is blocked when the debris leaves less than a ship's
## diameter clear across it.
##
## The opening is the region the two boxes share. A ship crosses it along the
## crossing axis, chosen as `LevelValidator.opening_widths` chooses it (gen may
## not be used from core, so the rule is repeated here): an axis on which one box
## lies lower than the other at both ends, the one with the thinnest shared depth,
## else the thinnest shared axis; the lowest axis wins a tie. A ship flying
## straight across sweeps a cylinder of its radius through the whole depth, so it
## gets through when some line across the opening, its own radius in from the
## sides, passes every solid sphere by at least the ship's radius at the sphere's
## nearest point of that depth.
##
## In the plane across the opening that makes each sphere a disc the ship's line
## must stay out of, and the question is whether the opening's rectangle, shrunk by
## the ship's radius, is covered by those discs. If any of it is left, a point that
## is left lies on a corner of the rectangle, where a disc's edge meets a side, or
## where two discs' edges meet; only those few points are tested. Everything is in
## millimetres from whole-millimetre inputs, with basic arithmetic and square
## roots only, so the answer is the same on every device (ARC-1, ARC-2).
##
## An opening already narrower than a ship without any debris is not called
## blocked: debris did not close it, and `EscapePath.length_mm` still counts it.

## Slack on squared distances (mm²), so a ship that exactly fits counts as fitting
## whatever the last bit of a square root.
const SLACK_MM2: float = 0.001
## The same for a point computed to lie on the rectangle's side, in mm.
const EDGE_SLACK_MM: float = 0.000001


## True when the solid entries of `debris` block the opening where boxes `low`
## and `high` (corners in mm, shared region `low`..`high`) meet, for a ship of
## `ship_radius_mm`. `first_min`..`first_max` and `second_min`..`second_max` are
## the two boxes' corners, which decide the crossing axis.
static func blocked(first_min: Vector3i, first_max: Vector3i, second_min: Vector3i,
		second_max: Vector3i, debris: MeltdownDebris, ship_radius_mm: int) -> bool:
	if debris == null:
		return false
	var low: Vector3i = first_min.max(second_min)
	var high: Vector3i = first_max.min(second_max)
	var depth: int = crossing_axis(first_min, first_max, second_min, second_max)
	var u: int = (depth + 1) % 3
	var v: int = (depth + 2) % 3
	var r: float = float(ship_radius_mm)
	# Rectangle the ship's centre line may cross at: low u, low v, high u, high v.
	var rect: PackedFloat64Array = [low[u] + r, low[v] + r, high[u] - r, high[v] - r]
	if rect[0] > rect[2] or rect[1] > rect[3]:
		return false
	# Discs as flat triples: centre u, centre v, squared reach.
	var discs: PackedFloat64Array = []
	for index: int in debris.size():
		if not debris.is_solid(index):
			continue
		var at: Vector3i = debris.positions_mm[index]
		var gap: float = float(maxi(0, maxi(low[depth] - at[depth], at[depth] - high[depth])))
		var reach: float = float(debris.radii_mm[index]) + r
		if gap >= reach:
			continue
		discs.append_array([float(at[u]), float(at[v]), reach * reach - gap * gap])
	if discs.is_empty():
		return false
	var points: PackedFloat64Array = _candidates(rect, discs)
	for index: int in range(0, points.size(), 2):
		if _free(points[index], points[index + 1], rect, discs):
			return false
	return true


## The axis a ship crosses the shared region of two boxes along (see the class
## comment).
static func crossing_axis(first_min: Vector3i, first_max: Vector3i, second_min: Vector3i,
		second_max: Vector3i) -> int:
	var low: Vector3i = first_min.max(second_min)
	var high: Vector3i = first_max.min(second_max)
	var crossing: Array[int] = []
	for axis: int in 3:
		var first_lower: bool = first_min[axis] < second_min[axis] and first_max[axis] < second_max[axis]
		var second_lower: bool = second_min[axis] < first_min[axis] and second_max[axis] < first_max[axis]
		if first_lower or second_lower:
			crossing.append(axis)
	if crossing.is_empty():
		crossing = [0, 1, 2]
	var depth: int = crossing[0]
	for axis: int in crossing:
		if high[axis] - low[axis] < high[depth] - low[depth]:
			depth = axis
	return depth


## Candidate points as flat pairs (u, v). Godot's vectors are single precision,
## too coarse for squared millimetres, so plain 64-bit floats are used throughout.
static func _candidates(rect: PackedFloat64Array, discs: PackedFloat64Array) -> PackedFloat64Array:
	var points: PackedFloat64Array = [rect[0], rect[1], rect[2], rect[1], rect[0], rect[3],
		rect[2], rect[3]]
	for first: int in range(0, discs.size(), 3):
		var cu: float = discs[first]
		var cv: float = discs[first + 1]
		var reach_squared: float = discs[first + 2]
		for side: float in [rect[0], rect[2]]:
			var across: float = reach_squared - (side - cu) * (side - cu)
			if across >= 0.0:
				points.append_array([side, cv - sqrt(across), side, cv + sqrt(across)])
		for side: float in [rect[1], rect[3]]:
			var across: float = reach_squared - (side - cv) * (side - cv)
			if across >= 0.0:
				points.append_array([cu - sqrt(across), side, cu + sqrt(across), side])
		for second: int in range(first + 3, discs.size(), 3):
			points.append_array(_circle_meets(discs, first, second))
	return points


## Where the edges of discs `first` and `second` meet: none, or two points (the
## same point twice when they touch).
static func _circle_meets(discs: PackedFloat64Array, first: int, second: int) -> PackedFloat64Array:
	var meets: PackedFloat64Array = []
	var du: float = discs[second] - discs[first]
	var dv: float = discs[second + 1] - discs[first + 1]
	var d_squared: float = du * du + dv * dv
	if d_squared == 0.0:
		return meets
	var distance: float = sqrt(d_squared)
	# Distance from the first centre along the centre line to the common chord.
	var along: float = (d_squared + discs[first + 2] - discs[second + 2]) / (2.0 * distance)
	var half_chord_squared: float = discs[first + 2] - along * along
	if half_chord_squared < 0.0:
		return meets
	var half_chord: float = sqrt(half_chord_squared)
	var foot_u: float = discs[first] + du / distance * along
	var foot_v: float = discs[first + 1] + dv / distance * along
	var off_u: float = -dv / distance * half_chord
	var off_v: float = du / distance * half_chord
	meets.append_array([foot_u + off_u, foot_v + off_v, foot_u - off_u, foot_v - off_v])
	return meets


static func _free(pu: float, pv: float, rect: PackedFloat64Array, discs: PackedFloat64Array) -> bool:
	if pu < rect[0] - EDGE_SLACK_MM or pu > rect[2] + EDGE_SLACK_MM \
			or pv < rect[1] - EDGE_SLACK_MM or pv > rect[3] + EDGE_SLACK_MM:
		return false
	for index: int in range(0, discs.size(), 3):
		var du: float = pu - discs[index]
		var dv: float = pv - discs[index + 1]
		if du * du + dv * dv < discs[index + 2] - SLACK_MM2:
			return false
	return true
