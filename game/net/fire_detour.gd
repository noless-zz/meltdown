class_name FireDetour
extends RefCounted

## The bot's way round meltdown fire (#498, RUN-4, CMB-2, DEV-6). Given the
## waypoints `LevelRoute` would fly, it checks whether any leg crosses a fire
## that burns, or will burn by the time the ship reaches the end of that leg at
## the planning speed. If one does, it looks for the shortest route whose legs
## cross no such fire, and returns it when it is at most `detour_factor` times
## the length of the route it replaces. Otherwise the ship flies through.
##
## A route is a chain of opening centres between joined boxes, as in
## `LevelRoute`; legs run inside one box, so they are clear of the walls.
## Openings that debris closed stay closed. Fire holding the start or the end
## is ignored, since no route avoids it. The test is on the ship's centre, the
## point `MeltdownFire.burn` uses.
##
## Bot only: the map route (`KnownRoute`) and `DebrisRouteGuard` never call it,
## so fire stays passable for them. Only reads the level and the debris; no
## randomness, and openings are visited in a fixed order with ties going to the
## first found, so the same inputs give the same route (ARC-1, ARC-2).

const TICKS_PER_SECOND: float = 60.0


## The waypoints to fly instead of `planned`, or an empty list to keep it.
## `planned` ends with `to`. `closed` answers whether the opening between two
## boxes is shut.
static func reroute(union: BoxUnion, neighbours: Array, closed: Callable, debris: MeltdownDebris,
		from: Vector3, to: Vector3, starts: Array[int], goals: Array[int],
		planned: Array[Vector3], speed: float, detour_factor: float) -> Array[Vector3]:
	var fires: Array[int] = _fires(debris, from, to)
	if fires.is_empty() or speed <= 0.0:
		return []
	var planned_length: float = 0.0
	var point: Vector3 = from
	var crosses: bool = false
	for next: Vector3 in planned:
		planned_length += point.distance_to(next)
		crosses = crosses or _leg_burns(debris, fires, point, next, planned_length, speed)
		point = next
	if not crosses:
		return []
	var free: Array[Vector3] = _shortest_without_fire(union, neighbours, closed, debris, fires,
		from, to, starts, goals, speed, planned_length * detour_factor)
	return free


## Fire entries that are not held back and hold neither end.
static func _fires(debris: MeltdownDebris, from: Vector3, to: Vector3) -> Array[int]:
	var found: Array[int] = []
	if debris == null:
		return found
	for index: int in debris.size():
		if debris.is_fire(index) and not debris.is_skipped(index) \
				and not MeltdownFire.contains(debris, index, from) \
				and not MeltdownFire.contains(debris, index, to):
			found.append(index)
	return found


## Whether the leg `from`..`to`, ending `travelled` metres along the route,
## passes through a fire that burns by the time the ship gets to its end.
static func _leg_burns(debris: MeltdownDebris, fires: Array[int], from: Vector3, to: Vector3,
		travelled: float, speed: float) -> bool:
	var arrival: int = debris.elapsed_ticks + ceili(travelled / speed * TICKS_PER_SECOND)
	for index: int in fires:
		if debris.after_ticks[index] > arrival:
			continue
		var entry: float = DebrisShapes.box_entry(from, to, debris.position(index),
			debris.box_size(index) * 0.5) if debris.is_box(index) \
			else Projectile.segment_entry(from, to, debris.position(index), debris.radius(index))
		if entry >= 0.0:
			return true
	return false


## Dijkstra over the openings: the shortest fire-free route from `from` to `to`
## no longer than `limit` metres, as opening centres then `to`; empty if none.
## Node 0 is the start, node 1 the goal, then one node per open opening.
static func _shortest_without_fire(union: BoxUnion, neighbours: Array, closed: Callable,
		debris: MeltdownDebris, fires: Array[int], from: Vector3, to: Vector3,
		starts: Array[int], goals: Array[int], speed: float, limit: float) -> Array[Vector3]:
	var points: Array[Vector3] = [from, to]
	## Per node: the boxes it lies in, so the legs out of it.
	var boxes_of: Array = [starts, []]
	var node_of: Dictionary[int, int] = {}
	var count: int = union.boxes.size()
	for i: int in count:
		for j: int in neighbours[i]:
			if j > i and not closed.call(i, j):
				node_of[i * count + j] = points.size()
				points.append(LevelRoute.opening_centre(union.boxes[i], union.boxes[j]))
				boxes_of.append([i, j])
	var best: Array[float] = []
	best.resize(points.size())
	best.fill(INF)
	var previous: Array[int] = []
	previous.resize(points.size())
	previous.fill(-1)
	var done: Array[bool] = []
	done.resize(points.size())
	done.fill(false)
	best[0] = 0.0
	while true:
		var node: int = -1
		for candidate: int in points.size():
			if not done[candidate] and best[candidate] < INF \
					and (node < 0 or best[candidate] < best[node]):
				node = candidate
		if node < 0 or node == 1 or best[node] > limit:
			break
		done[node] = true
		for box: int in boxes_of[node]:
			var targets: Array[int] = []
			if goals.has(box):
				targets.append(1)
			for other: int in neighbours[box]:
				var key: int = mini(box, other) * count + maxi(box, other)
				if node_of.has(key):
					targets.append(node_of[key])
			for target: int in targets:
				if done[target]:
					continue
				var length: float = best[node] + points[node].distance_to(points[target])
				if length < best[target] and length <= limit and not _leg_burns(debris, fires,
						points[node], points[target], length, speed):
					best[target] = length
					previous[target] = node
	var route: Array[Vector3] = []
	if best[1] > limit:
		return route
	var at: int = 1
	while at > 0:
		route.push_front(points[at])
		at = previous[at]
	return route
