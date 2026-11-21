class_name ReactorFar
extends RefCounted

## Where a generated level's reactor may go, and the validator's `reactor_far`
## check (#912, GEN-1, GEN-3, RUN-3, RUN-5). The ship starts, and escapes to,
## the oldest open connector, which can be on any module, so the reactor is
## placed by its escape path from the start, not by joins from the first module.
##
## A level's modules come from `LevelDef.box_modules`. Two modules are joined
## when a doorway or loop bridge links them: a box of one is `LevelDef.joined`
## to a chain of doorway and bridge boxes (module -1) that is joined to a box of
## the other. Joins from the start's module are counted breadth-first over that.
##
## A candidate is a module at least `min_hops` joins from the start's module
## (never fewer than `NEAR_HOPS`, so never the start's module or one joined to
## it) whose largest box (ties to the lower box) holds the reactor at its centre
## with a ship's diameter clear on every side. Its escape path is `EscapePath`'s
## length from that centre to the start, the path the countdown is scaled by.
## The generator takes the candidate with the longest path, ties to the lowest
## placement, so the same seed gives the same reactor (GEN-2, ARC-2).
##
## The check fails a level whose reactor is in the start's module or one joined
## to it, or whose escape path is below `min_escape_fraction` of the longest a
## candidate gives on that level.

## The check's name, as `LevelValidator.CHECKS` lists it.
const CHECK: String = "reactor_far"
## Joins from the start's module a reactor's module needs at the least: two
## keeps it out of the start's module and every module joined to it.
const NEAR_HOPS: int = 2

## The module the start is in, or -1.
var start_module: int = -1
## Joins from the start's module to each module, -1 where none links them.
var hops: Array[int] = []
## The candidates' modules, lowest first, their reactor centres in whole
## millimetres, and their escape paths in millimetres.
var modules: Array[int] = []
var centres: Array[Vector3i] = []
var paths_mm: Array[int] = []
## Modules far enough away whose largest box was too small for the reactor.
var too_small: int = 0


## Surveys `level`'s modules for a reactor of `reactor_radius_mm` and a ship of
## `ship_radius`. A level without `box_modules` has no candidates.
static func survey(level: LevelDef, reactor_radius_mm: int, ship_radius: float,
		min_hops: int) -> ReactorFar:
	var found: ReactorFar = ReactorFar.new()
	found.start_module = module_at(level, level.start_position_mm)
	if found.start_module < 0:
		return found
	found.hops = hops_from(level, found.start_module)
	var needed: int = maxi(min_hops, NEAR_HOPS)
	var clear_mm: int = reactor_radius_mm + roundi(2.0 * ship_radius * RobotSpawn.SCALE)
	for module: int in found.hops.size():
		if found.hops[module] < needed:
			continue
		var box: int = largest_box(level, module)
		if box < 0:
			continue
		var low: Vector3i = EscapePath.to_mm(level.union.boxes[box].min_corner)
		var high: Vector3i = EscapePath.to_mm(level.union.boxes[box].max_corner)
		var centre: Vector3i = (low + high) / 2
		var fits: bool = true
		for axis: int in 3:
			fits = fits and centre[axis] - clear_mm >= low[axis] and centre[axis] + clear_mm <= high[axis]
		if not fits:
			found.too_small += 1
			continue
		found.modules.append(module)
		found.centres.append(centre)
	found.paths_mm = EscapePath.lengths_mm(level.union, level.start_position(), found.centres)
	return found


## Index into the candidates of the longest escape path, ties to the lowest
## module; -1 when no candidate has a path.
func best() -> int:
	var chosen: int = -1
	for index: int in paths_mm.size():
		if paths_mm[index] != EscapePath.UNREACHABLE \
				and (chosen < 0 or paths_mm[index] > paths_mm[chosen]):
			chosen = index
	return chosen


## The longest candidate escape path, millimetres, or 0 with none.
func longest_mm() -> int:
	var chosen: int = best()
	return 0 if chosen < 0 else paths_mm[chosen]


## The most joins any module is from the start's module.
func furthest_hops() -> int:
	var most: int = 0
	for value: int in hops:
		most = maxi(most, value)
	return most


## The `reactor_far` failure for `level`, or "" when it passes. A level without
## modules or without a reactor is not this check's to judge.
static func failure(level: LevelDef, ship_radius: float, min_escape_fraction: float) -> String:
	if level.box_modules.is_empty() or level.reactor == null:
		return ""
	var found: ReactorFar = survey(level, level.reactor.radius_mm, ship_radius, NEAR_HOPS)
	if found.start_module < 0:
		return "%s: the start is in no module" % CHECK
	var module: int = module_at(level, level.reactor.position_mm)
	if module < 0:
		return "%s: the reactor is in no module" % CHECK
	if found.hops[module] < NEAR_HOPS:
		return "%s: the reactor is in module %d, %s the start's module %d" % [CHECK, module,
				"which is" if module == found.start_module else "joined to", found.start_module]
	# A reactor the generator placed sits on a candidate's centre, whose path
	# the survey has; any other is measured on its own.
	var at: int = found.centres.find(level.reactor.position_mm)
	var path: int = found.paths_mm[at] if at >= 0 \
			else EscapePath.length_mm(level.union, level.reactor.position(), level.start_position())
	var longest: int = found.longest_mm()
	if float(path) < min_escape_fraction * float(longest):
		return "%s: the reactor's escape path is %.1f m, below %d%% of the longest a module gives, %.1f m" \
				% [CHECK, path / float(RobotSpawn.SCALE), roundi(min_escape_fraction * 100.0),
				longest / float(RobotSpawn.SCALE)]
	return ""


## The module whose box holds `point_mm`, lowest box first; -1 when only
## doorways or nothing hold it.
static func module_at(level: LevelDef, point_mm: Vector3i) -> int:
	var point: Vector3 = Vector3(point_mm) / float(RobotSpawn.SCALE)
	for box: int in mini(level.box_modules.size(), level.union.boxes.size()):
		if level.box_modules[box] >= 0 and level.union.boxes[box].holds(point, 0.0):
			return level.box_modules[box]
	return -1


## The largest box of `module`, by volume; ties go to the lower box.
static func largest_box(level: LevelDef, module: int) -> int:
	var chosen: int = -1
	var most: int = -1
	for box: int in level.box_modules.size():
		if level.box_modules[box] != module:
			continue
		# Whole millimetres, so equal boxes tie exactly wherever they sit.
		var size: Vector3i = EscapePath.to_mm(level.union.boxes[box].max_corner) \
				- EscapePath.to_mm(level.union.boxes[box].min_corner)
		var volume: int = size.x * size.y * size.z
		if volume > most:
			chosen = box
			most = volume
	return chosen


## Joins from `from` to each module, -1 where nothing links them.
static func hops_from(level: LevelDef, from: int) -> Array[int]:
	var links: Array[Array] = module_links(level)
	var found: Array[int] = []
	found.resize(links.size())
	found.fill(-1)
	found[from] = 0
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var module: int = queue.pop_front()
		for other: int in links[module]:
			if found[other] < 0:
				found[other] = found[module] + 1
				queue.append(other)
	return found


## For each module, the modules joined to it, lowest first. Each group of
## doorway and bridge boxes joined to one another joins every module it meets.
static func module_links(level: LevelDef) -> Array[Array]:
	var boxes: Array[BoxBounds] = level.union.boxes
	var count: int = 0
	for module: int in level.box_modules:
		count = maxi(count, module + 1)
	var links: Array[Array] = []
	for module: int in count:
		links.append([])
	var seen: Array[bool] = []
	seen.resize(boxes.size())
	seen.fill(false)
	for first: int in level.box_modules.size():
		if level.box_modules[first] >= 0 or seen[first]:
			continue
		seen[first] = true
		var met: Array[int] = []
		var queue: Array[int] = [first]
		while not queue.is_empty():
			var at: int = queue.pop_front()
			for other: int in boxes.size():
				if other == at or not LevelDef.joined(boxes[at], boxes[other]):
					continue
				var owner: int = level.box_modules[other]
				if owner >= 0:
					if not met.has(owner):
						met.append(owner)
				elif not seen[other]:
					seen[other] = true
					queue.append(other)
		for module: int in met:
			for other: int in met:
				if other != module and not links[module].has(other):
					links[module].append(other)
	for module: int in count:
		links[module].sort()
	return links
