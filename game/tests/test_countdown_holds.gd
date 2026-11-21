extends RefCounted

## Once the run is decided the meltdown stops playing out (#750, playtest #745;
## RUN-2, RUN-3, RUN-5, RUN-7, ARC-1, ARC-2): the countdown holds the time left on
## the deciding tick, an escaped ship is never lost to it, and an escaped ship
## stays parked whatever its pilot does.

const PULSE: String = "res://data/weapons/pulse_cannon.json"
## Five seconds of meltdown (300 ticks), an 8 hull reactor and a 3 m exit.
const REACTOR_JSON: String = '{"position": [0, 0, -60], "radius": 2, "hull": 8,' \
	+ ' "meltdown_seconds": 5, "exit_radius": 3}'
## Where the ship flies while the meltdown runs: 20 m from its start and exit.
const AWAY: Vector3 = Vector3(0, 0, -20)


## One armed ship whose start (and exit) is the origin, moved 20 m out of the
## exit, with the reactor destroyed between ticks so the countdown is running.
func _melting(ship_count: int = 1) -> Sim:
	var sim: Sim = Sim.new(750, ship_count, BoxBounds.new(Vector3(-10, -10, -100), Vector3(10, 10, 10)))
	sim.set_reactor(ReactorState.parse_json(REACTOR_JSON))
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	sim.equip(loadout)
	sim.step(_idle(ship_count))
	for ship: ShipState in sim.ships:
		ship.position = AWAY
		ship.velocity = Vector3.ZERO
	sim.reactor.apply_damage(sim.reactor.hull)
	return sim


func _idle(ship_count: int = 1) -> Array[ShipInput]:
	var inputs: Array[ShipInput] = []
	for i: int in ship_count:
		inputs.append(ShipInput.new())
	return inputs


## Everything held at once: full thrust and turn on every axis, afterburner and fire.
func _everything() -> Array[ShipInput]:
	var input: ShipInput = ShipInput.new(Vector3i(1000, 1000, -1000), Vector3i(3000, 3000, 3000), true)
	input.fire_primary = true
	return [input]


## Runs `ticks` idle ticks of the meltdown, then puts the ship back in the exit so
## the next tick escapes. Returns the ticks left once it has escaped.
func _escape_after(sim: Sim, ticks: int) -> int:
	for i: int in ticks:
		sim.step(_idle())
	sim.ships[0].position = Vector3.ZERO
	sim.step(_idle())
	return sim.reactor.meltdown_ticks_left


func test_an_escape_holds_the_time_left() -> String:
	var sim: Sim = _melting()
	var left: int = _escape_after(sim, 100)
	if not sim.ships[0].escaped or sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "the ship did not escape"
	if left <= 0 or left >= sim.reactor.meltdown_ticks():
		return "escaped with %d ticks left" % left
	for i: int in 600:
		sim.step(_idle())
		if sim.reactor.meltdown_ticks_left != left:
			return "%d ticks left %d ticks after the escape, expected %d" \
				% [sim.reactor.meltdown_ticks_left, i + 1, left]
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "the outcome became %d" % sim.outcome()
	return ""


## Escapes with the whole meltdown left down to its last tick (escaping on the
## tick the clock reaches zero is a loss, as before).
func test_an_escaped_ship_is_never_lost_to_the_meltdown() -> String:
	var total: int = ReactorState.parse_json(REACTOR_JSON).meltdown_ticks()
	for before: int in [0, 1, 150, total - 3, total - 2]:
		var sim: Sim = _melting()
		_escape_after(sim, before)
		if not sim.ships[0].escaped:
			return "no escape after %d ticks" % before
		for i: int in 600:
			sim.step(_idle())
			for event: SimEvent in sim.last_events:
				if event.kind == SimEvent.Kind.SHIP_LOST_IN_MELTDOWN:
					return "lost in the meltdown %d ticks after escaping %d ticks in" % [i + 1, before]
		if sim.ships[0].is_destroyed() or sim.outcome() != ExitRule.Outcome.ESCAPED:
			return "escaping %d ticks in ended %d" % [before, sim.outcome()]
	return ""


func test_an_escaped_ship_stays_parked_whatever_its_input() -> String:
	var sim: Sim = _melting()
	_escape_after(sim, 60)
	var ship: ShipState = sim.ships[0]
	var position: Vector3 = ship.position
	var orientation: Basis = ship.orientation
	var shots: int = sim.projectiles.size()
	for i: int in 600:
		sim.step(_everything())
		if sim.projectiles.size() > shots:
			return "the escaped ship fired on tick %d after escaping" % (i + 1)
	if ship.position != position or ship.orientation != orientation or ship.velocity != Vector3.ZERO:
		return "the escaped ship moved: %s %s %s" % [ship.position, ship.orientation, ship.velocity]
	return ""


func test_a_lost_run_stops_the_countdown() -> String:
	var sim: Sim = _melting(2)
	for i: int in 50:
		sim.step(_idle(2))
	for ship: ShipState in sim.ships:
		ship.hull = 0.0
	sim.step(_idle(2))
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "the run is %d with every ship destroyed" % sim.outcome()
	var left: int = sim.reactor.meltdown_ticks_left
	if left <= 0:
		return "the countdown had already run out"
	for i: int in 600:
		sim.step(_idle(2))
	if sim.reactor.meltdown_ticks_left != left:
		return "%d ticks left, held at %d" % [sim.reactor.meltdown_ticks_left, left]
	return ""


## One ship escapes and the other flies on: the run is still running, so the
## clock runs out and the other ship is lost, which decides the run.
func test_the_countdown_runs_while_a_ship_is_still_flying() -> String:
	var sim: Sim = _melting(2)
	sim.ships[0].position = Vector3.ZERO
	sim.step(_idle(2))
	if not sim.ships[0].escaped or sim.outcome() != ExitRule.Outcome.RUNNING:
		return "one ship escaped and the run is %d" % sim.outcome()
	var left: int = sim.reactor.meltdown_ticks_left
	sim.step(_idle(2))
	if sim.reactor.meltdown_ticks_left != left - 1:
		return "the countdown held while a ship is still flying"
	for i: int in left + 10:
		sim.step(_idle(2))
	if sim.reactor.meltdown_ticks_left != 0 or not sim.ships[1].is_destroyed():
		return "the countdown stopped at %d" % sim.reactor.meltdown_ticks_left
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "the run ended %d" % sim.outcome()
	return ""


func test_the_same_escape_gives_the_same_hash() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = _melting()
		_escape_after(sim, 90)
		for i: int in 300:
			sim.step(_everything())
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "the same escape ended on %d and %d" % hashes
	return ""
