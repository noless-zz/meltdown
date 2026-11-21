extends RefCounted

## How far each level's reactor is from the entrance, over a seed sweep (#924,
## GEN-3, RUN-3, RUN-5), so every sweep and the nightly 10,000-seed line show it,
## and a later generator change cannot quietly bring the reactor back next to
## the exit (#912's playtest). `seed_sweep.gd` hands each built level to `add`;
## this file keeps the numbers and prints them.
##
## The escape path is the core's `EscapePath` from the reactor to the start, the
## path the countdown is scaled by, and the countdown is the reactor's own
## `meltdown_ticks_for_path` for it: the numbers a run would start with. Nothing
## is stored in `core/` or `gen/`, so no level or hash moves.

## The stats' keys: escape paths in whole millimetres and countdowns in ticks,
## one per level with a reactor, and the levels whose reactor is in the start's
## module or a module joined to it (`ReactorFar.NEAR_HOPS`), which must be none.
const PATHS: String = "paths_mm"
const COUNTDOWNS: String = "countdown_ticks"
const NEAR: String = "near_start"


## Stats with no level in them.
static func empty() -> Dictionary:
	return {PATHS: [] as Array[int], COUNTDOWNS: [] as Array[int], NEAR: 0}


## Adds one built level. A level without a reactor, or whose reactor has no way
## out, adds nothing: the validator's `reactor` and `escape` checks fail it.
static func add(stats: Dictionary, level: LevelDef) -> void:
	if level.reactor == null:
		return
	if is_near_start(level):
		stats[NEAR] += 1
	var path_mm: int = EscapePath.length_mm(level.union, level.reactor.position(), level.start_position())
	if path_mm == EscapePath.UNREACHABLE:
		return
	stats[PATHS].append(path_mm)
	stats[COUNTDOWNS].append(level.reactor.meltdown_ticks_for_path(path_mm))


## Whether `level`'s reactor is in the start's module or one joined to it, by
## `ReactorFar`'s modules and joins. A level without modules (read from a file)
## has none to tell apart, so it is never near.
static func is_near_start(level: LevelDef) -> bool:
	if level.box_modules.is_empty() or level.reactor == null:
		return false
	var start: int = ReactorFar.module_at(level, level.start_position_mm)
	var reactor: int = ReactorFar.module_at(level, level.reactor.position_mm)
	if start < 0 or reactor < 0:
		return false
	if start == reactor:
		return true
	return ReactorFar.module_links(level)[start].has(reactor)


## The value at fraction `share` of `values` sorted, by nearest rank: the
## smallest value with at least that share of the values at or below it, so the
## median of an even count is the lower middle one and every figure is a value a
## level really had. 0 with no values.
static func rank(values: Array[int], share: float) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var index: int = clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[index]


## The summary line's part, as ", escape_m_min 61.2, escape_m_p10 80.4,
## escape_m_median 120.0, escape_m_max 300.5, countdown_s_min 70.6, ...,
## reactor_near_start 0": two words a field, as the fields before it, so the
## nightly job and anything splitting the line on ", " read it the same way.
static func summary_part(stats: Dictionary) -> String:
	var part: String = _four(stats.get(PATHS, [] as Array[int]), "escape_m", float(RobotSpawn.SCALE))
	part += _four(stats.get(COUNTDOWNS, [] as Array[int]), "countdown_s", float(ReactorState.TICKS_PER_SECOND))
	return part + ", reactor_near_start %d" % stats.get(NEAR, 0)


static func _four(values: Array[int], name: String, unit: float) -> String:
	var part: String = ""
	var shares: Dictionary[String, float] = {"min": 0.0, "p10": 0.1, "median": 0.5, "max": 1.0}
	for label: String in shares:
		part += ", %s_%s %.1f" % [name, label, rank(values, shares[label]) / unit]
	return part
