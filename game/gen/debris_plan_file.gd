class_name DebrisPlanFile
extends RefCounted

## Reads `data/gen/debris.json` into a `DebrisPlan` (#398, #462), split out of
## `DebrisPlan` so the placing there stays one readable file as it grows (#493).
## The keys, their ranges and the messages are described there.


## Fills `plan` from the file's parsed top level; returns why it was rejected,
## or "" when every key was read.
static func read(plan: DebrisPlan, data: Dictionary) -> String:
	var unknown: Array[String] = []
	for key: Variant in data:
		if not DebrisPlan.KEYS.has(key) and key != DebrisPlan.DOORS_KEY:
			unknown.append("\"%s\"" % str(key))
	if not unknown.is_empty():
		return "unknown key %s" % ", ".join(unknown)
	var missing: Array[String] = []
	for key: String in DebrisPlan.KEYS:
		if not data.has(key):
			missing.append("\"%s\"" % key)
	if not missing.is_empty():
		return "missing key %s" % ", ".join(missing)
	var counts: Array[int] = []
	var problem: String = DebrisPlan._read_range(data["count"], "count", 1.0, 0.0, 1000.0,
			"a whole number", counts)
	if problem != "":
		return problem
	var radii: Array[int] = []
	problem = DebrisPlan._read_range(data["radius"], "radius", RobotSpawn.SCALE, 0.001,
			DebrisPlan.MAX_RADIUS_M, "metres", radii)
	if problem != "":
		return problem
	var ticks: Array[int] = []
	problem = DebrisPlan._read_range(data["after_seconds"], "after_seconds", MeltdownDebris.TICKS_PER_SECOND,
		1.0 / MeltdownDebris.TICKS_PER_SECOND, DebrisPlan.MAX_AFTER_SECONDS, "seconds", ticks)
	if problem != "":
		return problem
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance", "min_robot_distance"]:
		var value: Variant = data[key]
		if not DebrisPlan._is_number(value) or float(value) < 0.0 \
				or float(value) > DebrisPlan.MAX_DISTANCE_M:
			return "%s must be a number of metres from 0 to %s" % [key, DebrisPlan.MAX_DISTANCE_M]
		distances.append(roundi(float(value) * RobotSpawn.SCALE))
	var fraction: Variant = data["latest_fall_fraction"]
	if not DebrisPlan._is_number(fraction) or float(fraction) < DebrisPlan.MIN_FALL_FRACTION \
			or float(fraction) > DebrisPlan.MAX_FALL_FRACTION:
		return "latest_fall_fraction must be a number from %s to %s" \
				% [DebrisPlan.MIN_FALL_FRACTION, DebrisPlan.MAX_FALL_FRACTION]
	plan.min_count = counts[0]
	plan.max_count = counts[1]
	plan.min_radius_mm = radii[0]
	plan.max_radius_mm = radii[1]
	plan.min_after_ticks = ticks[0]
	plan.max_after_ticks = ticks[1]
	plan.min_start_distance_mm = distances[0]
	plan.min_reactor_distance_mm = distances[1]
	plan.min_robot_distance_mm = distances[2]
	plan.latest_fall_fraction = float(fraction)
	if data.has(DebrisPlan.DOORS_KEY):
		var read_doors: Array[DebrisDoors] = []
		var problem_doors: String = DebrisDoors.read(data[DebrisPlan.DOORS_KEY], read_doors)
		if problem_doors != "":
			return problem_doors
		plan.doors = read_doors[0]
	return ""
