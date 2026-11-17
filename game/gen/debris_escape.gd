class_name DebrisEscape
extends RefCounted

## The `debris_escape` check of `LevelValidator` (#493, GEN-3, RUN-4, RUN-5),
## and the trimming `DebrisPlan.place` does so a generated level passes it.
##
## `EscapeChecks` times the escape on the level as generated. Meltdown entries
## can then close the short way: `DebrisRouteGuard` keeps *a* route open, but
## not one that still fits the countdown. This check flies the escape at
## `escape_speed_mps` from the reactor to the exit with every solid entry
## fallen that the guard would let fall, and requires it to take no more than
## `escape_margin` of the countdown the level starts, which stays the one for
## the clear path (`ReactorState.meltdown_ticks_for_path`, RUN-5): the timer is
## set when the reactor dies, before anything has fallen.
##
## Which entries the guard lets fall is found as `SeedSweep.debris_route` finds
## them: one ship at the reactor, every box explored, the entries in fall order
## (`held_by_guard`). Held entries stay up, and fire
## never closes an opening, so neither lengthens the route. Every entry is then
## counted as fallen at once, the harshest moment of the meltdown. When even
## every solid entry fallen, the guard aside, leaves the escape in time, the
## guard is not run: holding entries back only ever shortens the route.
##
## Lengths are whole millimetres from `KnownRoute`, which with no debris agrees
## with `EscapePath.length_mm`, so the result is the same on every device
## (ARC-2).

## The check's name, as `LevelValidator.CHECKS` lists it.
const CHECK: String = "debris_escape"


## The failure message, or "" when the escape with `debris` fallen fits. Also
## "" when the level has no reactor, no debris, or no clear escape in time,
## which the `reactor` and `escape` checks report.
static func failure(level: LevelDef, debris: MeltdownDebris, ship_radius: float,
		escape_speed_mps: float, escape_margin: float) -> String:
	var found: Dictionary = _evaluate(level, debris, ship_radius, escape_speed_mps, escape_margin)
	if found.is_empty():
		return ""
	var names: Array[String] = []
	for index: int in found["entries"]:
		names.append(str(index))
	if found["route_mm"] == EscapePath.UNREACHABLE:
		return "%s: debris that falls closes every route from the reactor to the exit (entries %s)" \
				% [CHECK, ", ".join(names)]
	var metres: float = found["route_mm"] / float(RobotSpawn.SCALE)
	return "%s: %.1f m from the reactor to the exit with debris fallen (%.1f m clear) takes %.1f s at %.1f m/s, over %.1f s (%d%% of the %.1f s countdown); lengthened by entries %s" \
			% [CHECK, metres, found["clear_mm"] / float(RobotSpawn.SCALE), metres / escape_speed_mps,
			escape_speed_mps, found["allowed_s"], roundi(escape_margin * 100.0), found["countdown_s"],
			", ".join(names)]


## The entries of `debris` that lengthen the escape past the margin, lowest
## first: each one whose absence alone shortens the route with the rest fallen.
## When no single entry does, every entry that falls. Empty when the escape
## fits (see `failure`).
static func lengthening(level: LevelDef, debris: MeltdownDebris, ship_radius: float,
		escape_speed_mps: float, escape_margin: float) -> Array[int]:
	var found: Dictionary = _evaluate(level, debris, ship_radius, escape_speed_mps, escape_margin)
	var entries: Array[int] = []
	if not found.is_empty():
		entries.assign(found["entries"])
	return entries


## Removes entries from `debris` until the escape fits, and returns how many.
## Each round drops the highest-numbered entry `lengthening` names: doors are
## placed after the spheres and each kind in draw order, so the last placed goes
## first. Only entries are removed, so nothing else in the level moves, and the
## same level always loses the same entries (GEN-2).
static func trim(level: LevelDef, debris: MeltdownDebris, ship_radius: float,
		escape_speed_mps: float, escape_margin: float) -> int:
	var dropped: int = 0
	var entries: Array[int] = lengthening(level, debris, ship_radius, escape_speed_mps, escape_margin)
	while not entries.is_empty():
		remove_entry(debris, entries.max())
		dropped += 1
		entries = lengthening(level, debris, ship_radius, escape_speed_mps, escape_margin)
	return dropped


## Removes entry `index` from `debris`, whose size and fire lists may be shorter
## than the rest (entries past their end are spheres and not fire).
static func remove_entry(debris: MeltdownDebris, index: int) -> void:
	debris.positions_mm.remove_at(index)
	debris.radii_mm.remove_at(index)
	debris.after_ticks.remove_at(index)
	for list: Array in [debris.sizes_mm, debris.fire_milli_dps, debris.skipped]:
		if index < list.size():
			list.remove_at(index)


## Empty when the escape fits; otherwise "route_mm", "clear_mm", "allowed_s",
## "countdown_s" and "entries" (see `lengthening`).
static func _evaluate(level: LevelDef, debris: MeltdownDebris, ship_radius: float,
		escape_speed_mps: float, escape_margin: float) -> Dictionary:
	if level.reactor == null or debris == null or debris.size() == 0:
		return {}
	var clear_mm: int = EscapePath.length_mm(level.union, level.reactor.position(),
			level.start_position())
	if clear_mm == EscapePath.UNREACHABLE:
		return {}
	var countdown: float = level.reactor.meltdown_ticks_for_path(clear_mm) \
			/ float(ReactorState.TICKS_PER_SECOND)
	var allowed: float = countdown * escape_margin
	# A clear escape that is already too slow is the `escape` check's to report,
	# and no debris dropped could help it.
	if not _fits(clear_mm, escape_speed_mps, allowed):
		return {}
	var falling: Array[int] = []
	for index: int in debris.size():
		if not debris.is_fire(index):
			falling.append(index)
	if _fits(_route_mm(level, debris, falling, -1, ship_radius), escape_speed_mps, allowed):
		return {}
	var route: Array[int] = []
	var held: Array[bool] = held_by_guard(level, debris, ship_radius, route)
	falling.clear()
	for index: int in debris.size():
		if not debris.is_fire(index) and not held[index]:
			falling.append(index)
	var route_mm: int = route[0]
	if _fits(route_mm, escape_speed_mps, allowed):
		return {}
	var entries: Array[int] = []
	for index: int in falling:
		var without: int = _route_mm(level, debris, falling, index, ship_radius)
		if without != EscapePath.UNREACHABLE \
				and (route_mm == EscapePath.UNREACHABLE or without < route_mm):
			entries.append(index)
	if entries.is_empty():
		entries = falling
	return {"route_mm": route_mm, "clear_mm": clear_mm, "allowed_s": allowed,
			"countdown_s": countdown, "entries": entries}


## For each entry of `debris`, whether `DebrisRouteGuard` would hold it back in
## a meltdown with one ship of `ship_radius` waiting at the reactor. The guard's
## rule without its `Sim`, about half the work, since this runs for every
## generated level: entries go in fall order, those due on one tick in index
## order; fire is never held; a solid entry is held when, with the ones before
## it that fell, it would leave no route from the reactor to the start. The one
## ship always keeps its route, so the guard's "has a route now" never fails.
## `test_debris_escape.gd` checks this against the guard itself. `route`, when
## given, gets the route's length with every entry that fell solid.
static func held_by_guard(level: LevelDef, debris: MeltdownDebris, ship_radius: float,
		route: Array[int] = []) -> Array[bool]:
	var held: Array[bool] = []
	held.resize(debris.size())
	held.fill(false)
	var order: Array[int] = []
	for index: int in debris.size():
		if not debris.is_fire(index):
			order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		return debris.after_ticks[a] < debris.after_ticks[b] \
				or debris.after_ticks[a] == debris.after_ticks[b] and a < b)
	var fallen: Array[int] = []
	var length: int = EscapePath.UNREACHABLE
	for index: int in order:
		fallen.append(index)
		var with_entry: int = _route_mm(level, debris, fallen, -1, ship_radius)
		if with_entry == EscapePath.UNREACHABLE:
			fallen.pop_back()
			held[index] = true
		else:
			length = with_entry
	if fallen.is_empty():
		length = _route_mm(level, debris, fallen, -1, ship_radius)
	route.append(length)
	return held


## Length of the route from the reactor to the start with the entries of
## `debris` listed in `falling` solid, `leave_out` excepted.
static func _route_mm(level: LevelDef, debris: MeltdownDebris, falling: Array[int],
		leave_out: int, ship_radius: float) -> int:
	var solid: MeltdownDebris = MeltdownDebris.new()
	for index: int in falling:
		if index == leave_out:
			continue
		solid.positions_mm.append(debris.positions_mm[index])
		solid.radii_mm.append(debris.radii_mm[index])
		solid.sizes_mm.append(debris.sizes_mm[index] if debris.is_box(index) else Vector3i.ZERO)
		solid.after_ticks.append(1)
		solid.skipped.append(false)
	solid.elapsed_ticks = 1
	var all: Array[int] = []
	for box: int in level.union.boxes.size():
		all.append(box)
	return KnownRoute.find(level.union, all, level.reactor.position(), level.start_position(),
			solid, ship_radius).length_mm


## True when `route_mm` flown at `speed` takes no more than `allowed` seconds;
## as in `EscapeChecks`, exactly the margin passes whatever the last bit.
static func _fits(route_mm: int, speed: float, allowed: float) -> bool:
	if route_mm == EscapePath.UNREACHABLE:
		return false
	var seconds: float = route_mm / float(RobotSpawn.SCALE) / speed
	return seconds <= allowed or is_equal_approx(seconds, allowed)
