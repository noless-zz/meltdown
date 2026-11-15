class_name SimEvent
extends RefCounted

## Something that happened to one ship on one tick, reported by `Sim.step` in
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
	## The ship hit a wall. `magnitude` is the impact speed into the wall in
	## metres per second; `vector` is the unit wall normal, pointing back into
	## the open space. A corner hit is one event whose normal is the average.
	WALL_IMPACT,
}

var kind: Kind = Kind.AFTERBURNER_STARTED
## Index into `Sim.ships`.
var ship: int = 0
## Kind-specific size; 0.0 for kinds that have none.
var magnitude: float = 0.0
## Kind-specific direction; Vector3.ZERO for kinds that have none.
var vector: Vector3 = Vector3.ZERO


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
		and magnitude == other.magnitude and vector == other.vector)


func _to_string() -> String:
	return "%s(ship %d, %f, %s)" % [Kind.keys()[kind], ship, magnitude, vector]
