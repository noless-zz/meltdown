class_name SimEvent
extends RefCounted

## Something that happened to or was done by one ship on one tick, reported by `Sim.step` in
## `Sim.last_events`.
##
## Haptics, cockpit shake and sound (PLT-6, CMF-6) react to these instead of
## comparing ship state between frames, so view and xr code never need to know
## how the simulation decides a transition (MP-2). Events are derived output:
## they are not part of `Sim.state_hash()` and are rebuilt every tick.

enum Kind {
	## The afterburner boosted on this tick and not on the one before.
	AFTERBURNER_STARTED,
	## The afterburner boosted on the tick before and not on this one.
	AFTERBURNER_STOPPED,
	## The energy pool ran dry and locked the afterburner this tick. The boost
	## still ran on this tick, so AFTERBURNER_STOPPED follows on the next.
	ENERGY_DEPLETED,
	## The ship hit a wall, or solid debris (RUN-4) as one. `magnitude` is the impact speed into the wall in
	## metres per second; `vector` is the unit wall normal, pointing back into
	## the open space. A corner hit is one event whose normal is the average.
	WALL_IMPACT,
	## A projectile hit a robot. `ship` is the ship that fired it, `magnitude`
	## the damage dealt and `vector` the projectile's unit direction of flight.
	## Reported after every ship event of the tick, in projectile order.
	ROBOT_HIT,
	## A robot's hull reached zero; it is removed from `Sim.robots` at the end
	## of the tick. Follows the ROBOT_HIT of the killing shot, and `ship` is
	## the ship that fired it.
	ROBOT_DESTROYED,
	## A robot's projectile hit a ship. `ship` is the ship hit, `magnitude` the
	## damage dealt (before the shield absorbs any) and `vector` the
	## projectile's unit direction of flight. Reported with the robot events,
	## after every ship event of the tick, in projectile order.
	SHIP_HIT,
	## A destroyed robot left a part floating (SLV-1). `ship` is the ship whose
	## shot destroyed it, `magnitude` the item's index in `Sim.salvage` and
	## `vector` where it was dropped. Reported after every other event of the
	## tick, in robot order.
	SALVAGE_DROPPED,
	## A ship flew through a floating part and took it into its hold (SLV-1).
	## `ship` is that ship, `magnitude` the item's index in `Sim.salvage` as it was
	## before this tick's pickups and `vector` where it floated. Reported after the
	## projectile hits and before any SALVAGE_DROPPED of the tick, in ship order.
	SALVAGE_COLLECTED,
	## A ship slotted the part from its hold into a primary slot (SLV-1).
	## `ship` is that ship, `magnitude` the primary slot index (0 or 1) and
	## `dropped` whether the weapon it replaced was dropped as salvage, in
	## which case `vector` is where. Reported with that ship's other events,
	## after any WALL_IMPACT and before the projectile hits.
	PART_SLOTTED,
	## A ship's shot brought the level's reactor to zero hull (RUN-2); the
	## meltdown countdown starts on the next tick. Reported once, with the
	## projectile hits. `ship` is the ship that fired it and `vector` the
	## reactor's position.
	REACTOR_DESTROYED,
	## During the meltdown a ship ended a tick inside the exit sphere at its
	## start (RUN-3) and is out of the level: from now on it takes no input, no
	## damage and does not move. `vector` is where it ended the tick. Reported
	## after every other event of the tick, in ship order (`ExitRule`).
	SHIP_ESCAPED,
	## The meltdown countdown ran out with the ship still in the level (RUN-7):
	## its hull is set to zero. Reported once, after every other event of the
	## tick, in ship order (`ExitRule`).
	SHIP_LOST_IN_MELTDOWN,
	## A debris entry fell due during the meltdown but was held back, because
	## solid it would have closed a live ship's last route to the exit (RUN-4):
	## a cave-in that "held". `ship` is the first ship, in ship order, that would
	## have lost its route, `magnitude` the entry's index in the level's debris
	## and `vector` its centre. Reported before every other event of the tick,
	## in file order (`DebrisRouteGuard`).
	DEBRIS_HELD,
	## The ship's hull reached zero this tick, whatever did it: a robot's shot,
	## a wall, fire, debris or the meltdown running out (RUN-7, #601). From now
	## on it takes no input and does not move. Reported once per ship, after
	## every other event of the tick, SHIP_LOST_IN_MELTDOWN included, in ship
	## order (`ExitRule`). `vector` is where the ship ended the tick.
	SHIP_DESTROYED,
}

var kind: Kind = Kind.AFTERBURNER_STARTED
## Index into `Sim.ships`: the ship it happened to (SHIP_HIT included), or
## for robot and salvage events the ship whose shot caused it.
var ship: int = 0
## Kind-specific size; 0.0 for kinds that have none.
var magnitude: float = 0.0
## Kind-specific direction; Vector3.ZERO for kinds that have none.
var vector: Vector3 = Vector3.ZERO
## PART_SLOTTED only: a replaced weapon was dropped. False for every other kind.
var dropped: bool = false


func _init(
		p_kind: Kind = Kind.AFTERBURNER_STARTED,
		p_ship: int = 0,
		p_magnitude: float = 0.0,
		p_vector: Vector3 = Vector3.ZERO) -> void:
	kind = p_kind
	ship = p_ship
	magnitude = p_magnitude
	vector = p_vector


## Exact comparison: two simulations fed the same inputs must agree to the bit.
func equals(other: SimEvent) -> bool:
	return (other != null and kind == other.kind and ship == other.ship
		and magnitude == other.magnitude and vector == other.vector
		and dropped == other.dropped)


func _to_string() -> String:
	return "%s(ship %d, %f, %s)" % [Kind.keys()[kind], ship, magnitude, vector]
