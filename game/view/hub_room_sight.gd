class_name HubRoomSight
extends RefCounted

## Whether a piece of the home base room stands between the seat and a
## station (#1397, CRW-2, CMF-11): the pilot reads each screen from the seat
## and points at it from beside the seat, so no prop or detail may cross the
## line from the eye point (the room's origin) to a station's screen centre.
## The line is widened by `CLEARANCE_M`, which covers half a screen's width and
## a hand held beside the seat. A piece is judged as its box (size, position,
## rotation in degrees); a round piece's box is larger than the piece, which
## only errs towards keeping the line clear.

const CLEARANCE_M: float = 0.15


## True when `piece` ({"size", "position", "rotation"}) crosses the widened
## line from the eye point to `target`.
static func blocks(piece: Dictionary, target: Vector3, clearance: float = CLEARANCE_M) -> bool:
	var to_piece: Transform3D = HubRoomDetails.placed(piece).affine_inverse()
	var half: Vector3 = (piece["size"] as Vector3) * 0.5 + Vector3.ONE * clearance
	return segment_hits_box(to_piece * Vector3.ZERO, to_piece * target, half)


## True when the segment from `from` to `to` passes through the box of
## half-size `half` centred on the origin (a slab test).
static func segment_hits_box(from: Vector3, to: Vector3, half: Vector3) -> bool:
	var enter: float = 0.0
	var leave: float = 1.0
	var along: Vector3 = to - from
	for axis: int in 3:
		if absf(along[axis]) < 0.000001:
			if absf(from[axis]) > half[axis]:
				return false
			continue
		var t_low: float = (-half[axis] - from[axis]) / along[axis]
		var t_high: float = (half[axis] - from[axis]) / along[axis]
		enter = maxf(enter, minf(t_low, t_high))
		leave = minf(leave, maxf(t_low, t_high))
		if enter > leave:
			return false
	return true


## "" when no piece in `pieces` (named `field` in the file) blocks a station
## in `stations`; otherwise which piece blocks which station.
static func problem(field: String, pieces: Array[Dictionary], stations: Array[Dictionary]) -> String:
	for i: int in pieces.size():
		for station: Dictionary in stations:
			if blocks(pieces[i], station["position"]):
				return "%s[%d] (%s) stands between the seat and the %s station" % [field, i, pieces[i]["id"],
					station["id"]]
	return ""
