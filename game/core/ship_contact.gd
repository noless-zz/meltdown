class_name ShipContact
extends RefCounted

## Keeps one ship out of solid debris and inside the walls at the end of its
## move (FLT-3, RUN-4), then lets burning debris burn it where it ends up
## (`MeltdownFire`). Kept out of `Sim` so its tick stays short.


## Pushes ship `index` of `sim` out of solid debris, then keeps it inside the
## walls, and reports each hit as a WALL_IMPACT event in `events`. Debris goes
## first so the walls have the last word: a push out of debris never leaves the
## level, and a ship it presses into a wall is pushed out again next tick.
static func apply(sim: Sim, index: int, events: Array[SimEvent]) -> void:
	var ship: ShipState = sim.ships[index]
	if sim.debris != null:
		_report(sim.debris.contain_impact(ship), index, events)
	if sim.walls != null:
		_report(sim.walls.contain_impact(ship), index, events)
	if sim.debris != null:
		MeltdownFire.burn(sim.debris, ship)


static func _report(impact: Vector3, index: int, events: Array[SimEvent]) -> void:
	if impact != Vector3.ZERO:
		events.append(SimEvent.new(
			SimEvent.Kind.WALL_IMPACT, index, impact.length(), -impact.normalized()))
