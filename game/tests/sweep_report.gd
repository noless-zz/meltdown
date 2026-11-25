extends RefCounted

## How a seed sweep's result is printed (#317, #513): the timing line and the
## summary line `SeedSweep.timing` and `SeedSweep.summary` hand on to. Moved out
## of `seed_sweep.gd` for the 300-line guide (#1287); the lines are unchanged.

const DebrisKinds := preload("res://tests/sweep_debris_kinds.gd")
const ReactorDistance := preload("res://tests/sweep_reactor_distance.gd")


## One line for a log, with each of `STAGES` and its milliseconds, as the
## 1,000-seed test prints it: "sweep time: generate 4300 ms, build 2100 ms, ...".
static func timing(result: Dictionary) -> String:
	var parts: Array[String] = []
	var stage_ms: Dictionary = result.get("stage_ms", {})
	for stage: String in stage_ms:
		parts.append("%s %d ms" % [stage, stage_ms[stage]])
	return "sweep time: " + ", ".join(parts)


## One line for a log: "level validator: 1000 seeds, 1000 passed, 0 failed,
## 0 stopped short, 812 ms, debris 3500, debris_held 1200, rocks 2900,
## rocks_held 1100, doors 400, doors_held 100, fires 200, fires_held 0,
## escape_m_min 61.2, ..., reactor_near_start 0; failing seeds by check: level
## 0, piece 0, ...". The debris counts, those by kind (#887), the reactor's
## distance (#924) and the by-check part are each left out when the result has none.
static func summary(result: Dictionary) -> String:
	var line: String = "level validator: %d seeds, %d passed, %d failed, %d stopped short, %d ms" % [
			result["seeds"], result["passed"], result["failed"], result["short"], result["ms"]]
	if result.has("debris"):
		line += ", debris %d, debris_held %d" % [result["debris"], result["debris_held"]]
	if result.has("debris_by_kind"):
		line += DebrisKinds.summary_part(result["debris_by_kind"])
	if result.has("reactor_distance"):
		line += ReactorDistance.summary_part(result["reactor_distance"])
	if not result.has("by_check"):
		return line
	var counts: Array[String] = []
	for check: String in result["by_check"]:
		counts.append("%s %d" % [check, result["by_check"][check]])
	return line + "; failing seeds by check: " + ", ".join(counts)
