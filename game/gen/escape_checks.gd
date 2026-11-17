class_name EscapeChecks
extends RefCounted

## The `reactor` and `escape` checks of `LevelValidator` (GEN-3, RUN-2, RUN-5),
## split out so the validator stays one readable file as checks are added
## (#399). The reactor must sit in one box with a ship's diameter clear around
## its sphere, so a ship can fly past it, and in a box the start reaches; only
## then is the escape timed: flown at `escape_speed_mps` along `EscapePath` to
## the exit, it must take no more than `escape_margin` of the countdown the
## level would start for that path.


## The `reactor` and `escape` failures; empty when the level passes both.
## `unreached` holds the boxes the start cannot reach, lowest first.
static func failures(level: LevelDef, ship_radius: float, start_box: int,
		unreached: Array[int], escape_speed_mps: float, escape_margin: float) -> Array[String]:
	var found: Array[String] = []
	var reactor: ReactorState = level.reactor
	if reactor == null:
		found.append("reactor: the level has no reactor")
		return found
	var boxes: Array[BoxBounds] = level.union.boxes
	var clear: float = reactor.radius() + 2.0 * ship_radius
	var holding: Array[int] = []
	for index: int in boxes.size():
		if boxes[index].holds(reactor.position(), clear):
			holding.append(index)
	if holding.is_empty():
		found.append("reactor: position %s is not held by any box with %.2f m clear (radius plus a ship's diameter)"
				% [reactor.position(), clear])
		return found
	var reached: Array[int] = []
	for index: int in holding:
		if not unreached.has(index):
			reached.append(index)
	if reached.is_empty():
		found.append("reactor: box %d holds it but cannot be reached from start box %d" % [holding[0], start_box])
		return found
	var path_mm: int = EscapePath.length_mm(level.union, reactor.position(), level.start_position())
	if path_mm == EscapePath.UNREACHABLE:
		found.append("escape: no path from the reactor in box %d to the exit" % reached[0])
		return found
	var metres: float = path_mm / float(RobotSpawn.SCALE)
	var seconds: float = metres / escape_speed_mps
	var countdown: float = reactor.meltdown_ticks_for_path(path_mm) / float(ReactorState.TICKS_PER_SECOND)
	var allowed: float = countdown * escape_margin
	# The approximate test lets an escape that takes exactly the margin pass,
	# whatever the last bit of the division.
	if seconds > allowed and not is_equal_approx(seconds, allowed):
		found.append("escape: %.1f m from the reactor in box %d to the exit takes %.1f s at %.1f m/s, over %.1f s (%d%% of the %.1f s countdown)"
				% [metres, reached[0], seconds, escape_speed_mps, allowed, roundi(escape_margin * 100.0), countdown])
	return found
