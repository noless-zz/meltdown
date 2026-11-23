class_name SoundCueEvents
extends RefCounted

## Turns what the simulation reported into the sound cues due to play, and
## where (#1290, AUD-1). Pure view: it reads the events, bolts and ships it is
## given and keeps only its own copies, so the simulation runs the same with
## sound on or off (ARC-1, MP-2).
##
## Most cues come straight from `SimEvent`s. Two are read from the bolts,
## because the core reports neither as an event: a bolt seen for the first
## time is a shot (`SHOT_FIRED:<weapon id>` from the slot that fired it), and a
## bolt gone with range left ended on something. That end places the hit on
## the robot or ship whose ROBOT_HIT or SHIP_HIT it matches; an end matching
## no hit struck a wall, debris or the reactor and plays `BOLT_IMPACT`.

## A bolt matches a hit when their directions agree this closely (cosine).
const HIT_DIRECTION_DOT: float = 0.999
## A wall knock sounds this far beyond the ship, into the wall.
const WALL_OFFSET_M: float = 1.0
## A shot that hit the ship sounds this far back along its flight, so it is
## heard from the side it came from.
const SHOT_FROM_M: float = 2.0
## A robot hit with no bolt to place it sounds this far ahead along the shot.
const ROBOT_FALLBACK_M: float = 10.0

## Kinds whose `vector` is where it happened (see `SimEvent.Kind`).
const AT_VECTOR: Array[SimEvent.Kind] = [
	SimEvent.Kind.SALVAGE_DROPPED, SimEvent.Kind.SALVAGE_COLLECTED,
	SimEvent.Kind.REACTOR_DESTROYED, SimEvent.Kind.SHIP_ESCAPED,
	SimEvent.Kind.DEBRIS_HELD, SimEvent.Kind.SHIP_DESTROYED,
	SimEvent.Kind.COMPONENT_COLLECTED, SimEvent.Kind.MINER_RESCUED,
]

## Each bolt seen on the last feed: [owner_index, position, velocity, ticks_left]
## as it was then, since the simulation may change or drop the object after.
var _seen: Dictionary[Projectile, Array] = {}


## Forgets the bolts seen, for a new level: its first bolts are all new shots.
func reset() -> void:
	_seen = {}


## The cues due after one advance: `events` are the advance's events, in order,
## `projectiles` the bolts after it and `ships` the ships after it (an index
## missing from it places that ship's cues at the origin). Shots come first,
## then the events in their order, then the bolts that struck walls.
func feed(events: Array[SimEvent], projectiles: Array[Projectile],
		ships: Array[ShipState]) -> Array[SoundCueHit]:
	var hits: Array[SoundCueHit] = []
	var current: Dictionary[Projectile, Array] = {}
	for projectile: Projectile in projectiles:
		if projectile == null:
			continue
		current[projectile] = [projectile.owner_index, projectile.position, projectile.velocity,
			projectile.ticks_left]
		if not _seen.has(projectile):
			hits.append(SoundCueHit.new(_shot_cue(projectile, ships), projectile.position))
	var ended: Array[Array] = []
	for gone: Projectile in _seen:
		var record: Array = _seen[gone]
		if not current.has(gone) and int(record[3]) > 1:
			var velocity: Vector3 = record[2]
			ended.append([int(record[0]), (record[1] as Vector3) + velocity * ShipState.TICK_DT * 0.5,
				velocity.normalized()])
	_seen = current
	var robot_hit_at: Dictionary[int, Vector3] = {}
	for event: SimEvent in events:
		var at: Vector3 = _place(event, ships, ended, robot_hit_at)
		hits.append(SoundCueHit.new(SoundCueTable.kind_cue(event.kind), at, event.magnitude))
	for end: Array in ended:
		hits.append(SoundCueHit.new(SoundCueTable.BOLT_IMPACT, end[1]))
	return hits


## Where `event` sounds. Removes the bolt end it matched from `ended`.
func _place(event: SimEvent, ships: Array[ShipState], ended: Array[Array],
		robot_hit_at: Dictionary[int, Vector3]) -> Vector3:
	var ship_at: Vector3 = ships[event.ship].position \
		if event.ship >= 0 and event.ship < ships.size() and ships[event.ship] != null else Vector3.ZERO
	if AT_VECTOR.has(event.kind):
		return event.vector
	match event.kind:
		SimEvent.Kind.WALL_IMPACT:
			return ship_at - event.vector * WALL_OFFSET_M
		SimEvent.Kind.SHIP_HIT:
			_take_end(ended, false, -1, event.vector)
			return ship_at - event.vector * SHOT_FROM_M
		SimEvent.Kind.ROBOT_HIT:
			var end: Array = _take_end(ended, true, event.ship, event.vector)
			var at: Vector3 = end[1] if not end.is_empty() else ship_at + event.vector * ROBOT_FALLBACK_M
			robot_hit_at[event.ship] = at
			return at
		SimEvent.Kind.ROBOT_DESTROYED:
			return robot_hit_at.get(event.ship, ship_at + event.vector * ROBOT_FALLBACK_M)
	return ship_at


## The first end in `ended` from a ship's bolt (`by_ship`, fired by ship
## `owner`) or a robot's, flying along `direction`; removed from `ended`.
## Empty when none matches.
static func _take_end(ended: Array[Array], by_ship: bool, owner: int, direction: Vector3) -> Array:
	for index: int in ended.size():
		var end: Array = ended[index]
		var end_owner: int = end[0]
		var owner_matches: bool = end_owner == owner if by_ship else end_owner < 0
		if owner_matches and (end[2] as Vector3).dot(direction.normalized()) >= HIT_DIRECTION_DOT:
			ended.remove_at(index)
			return end
	return []


## `SHOT_FIRED:<weapon id>` for the slot that fired `projectile`,
## `SHOT_FIRED:robot` for a robot's; plain `SHOT_FIRED` when the weapon is unknown.
static func _shot_cue(projectile: Projectile, ships: Array[ShipState]) -> String:
	if projectile.is_robot_owned():
		return SoundCueTable.shot_cue(SoundCueTable.ROBOT_WEAPON)
	var owner: int = projectile.owner_index
	if owner < ships.size() and ships[owner] != null and projectile.slot < ships[owner].primary_ids.size():
		var weapon: String = ships[owner].primary_ids[projectile.slot]
		if not weapon.is_empty():
			return SoundCueTable.shot_cue(weapon)
	return SoundCueTable.SHOT_FIRED
