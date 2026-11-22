extends RefCounted

## A ship at zero hull is destroyed (#601, RUN-7, CMB-2, ARC-1, ARC-2): it
## takes no thrust, turn, boost, fire, pickup, slot or reset; it stops where it
## is; one SHIP_DESTROYED event reports it on the tick its hull reaches zero,
## whatever the cause; and the run is LOST once every ship is destroyed, with
## or without a reactor.

const PULSE: String = "res://data/weapons/pulse_cannon.json"
const REACTOR_JSON: String = '{"position": [0, 0, -60], "radius": 2, "hull": 8,' \
	+ ' "meltdown_seconds": 1, "exit_radius": 3}'
const FIRE_DEBRIS: String = '[{"position": [0, 0, -10], "radius": 3, "after_seconds": 0.02,' \
	+ ' "kind": "fire", "damage_per_second": 30}]'
const FAR_REACTOR_JSON: String = '{"position": [15, 15, 15], "radius": 2, "hull": 40, "meltdown_seconds": 60}'


func _pulse() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE))


func _sim(ship_count: int = 1) -> Sim:
	return Sim.new(601, ship_count, BoxBounds.new(Vector3(-20, -20, -100), Vector3(20, 20, 20)))


## Everything a pilot could ask for on one tick.
func _everything() -> ShipInput:
	var input: ShipInput = ShipInput.from_floats(Vector3(0.5, 0.5, -1.0), Vector3(1.0, 1.0, 1.0), true)
	input.fire_primary = true
	input.slot_held = true
	input.reset_to_start = true
	return input


func _inputs(sim: Sim, input: ShipInput) -> Array[ShipInput]:
	var inputs: Array[ShipInput] = []
	for i: int in sim.ships.size():
		inputs.append(input)
	return inputs


## Steps `ticks` times; returns every SHIP_DESTROYED event seen, as "tick:ship".
func _run(sim: Sim, input: ShipInput, ticks: int) -> Array[String]:
	var seen: Array[String] = []
	for i: int in ticks:
		var tick: int = sim.tick
		sim.step(_inputs(sim, input))
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_DESTROYED:
				seen.append("%d:%d" % [tick, event.ship])
	return seen


## Flies forward for half a second, then loses the hull between ticks.
func _moving_wreck() -> Sim:
	var sim: Sim = _sim()
	sim.ships[0].primary_slots[0] = _pulse()
	_run(sim, ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO), 30)
	sim.ships[0].hull = 0.0
	sim.ships[0].shield = 0.0
	return sim


func test_a_destroyed_ship_stops_and_ignores_thrust_turn_and_boost() -> String:
	var sim: Sim = _moving_wreck()
	var ship: ShipState = sim.ships[0]
	var position: Vector3 = ship.position
	var orientation: Basis = ship.orientation
	var energy: float = ship.energy
	_run(sim, _everything(), 120)
	if ship.velocity != Vector3.ZERO or ship.position != position:
		return "velocity %s, moved from %s to %s" % [ship.velocity, position, ship.position]
	if ship.orientation != orientation:
		return "the wreck turned"
	if ship.energy != energy or ship.shield != 0.0 or ship.afterburner_active:
		return "energy %s (was %s), shield %s, boosting %s" % [ship.energy, energy, ship.shield,
			ship.afterburner_active]
	return ""


func test_a_destroyed_ship_never_fires() -> String:
	var sim: Sim = _moving_wreck()
	sim.projectiles.clear()
	var cooldowns: Array[int] = sim.ships[0].fire_cooldowns.duplicate()
	_run(sim, _everything(), 120)
	if not sim.projectiles.is_empty():
		return "%d shots from a wreck" % sim.projectiles.size()
	if sim.ships[0].fire_cooldowns != cooldowns:
		return "cooldowns moved from %s to %s" % [cooldowns, sim.ships[0].fire_cooldowns]
	if not sim.ships[0].fire_primary(true).is_empty():
		return "fire_primary fired a slot"
	return ""


func test_a_destroyed_ship_neither_picks_up_nor_slots() -> String:
	var sim: Sim = _sim()
	if sim.set_parts({"pulse_cannon": _pulse()}) != "":
		return "catalogue refused"
	var ship: ShipState = sim.ships[0]
	ship.hold.append("pulse_cannon")
	ship.hull = 0.0
	sim.salvage.append(SalvageItem.new("pulse_cannon", ship.position, Vector3.ZERO))
	_run(sim, _everything(), 30)
	if ship.hold != ["pulse_cannon"] or ship.primary_slots[0] != null:
		return "hold %s, slot 0 %s" % [ship.hold, ship.primary_slots[0]]
	if sim.salvage.size() != 1:
		return "%d items left floating, expected 1" % sim.salvage.size()
	return ""


func test_a_destroyed_ship_does_not_reset_to_its_start() -> String:
	var sim: Sim = _moving_wreck()
	var position: Vector3 = sim.ships[0].position
	var reset: ShipInput = ShipInput.new()
	reset.reset_to_start = true
	_run(sim, reset, 5)
	if sim.ships[0].position != position:
		return "the wreck went from %s to %s" % [position, sim.ships[0].position]
	return ""


func test_a_robot_shot_reports_the_destruction_once() -> String:
	var sim: Sim = _sim(2)
	sim.ships[1].position = Vector3(10, 0, 0)
	var ship: ShipState = sim.ships[0]
	ship.hull = 1.0
	ship.shield = 0.0
	ship.shield_recharge = 0.0
	sim.projectiles.append(Projectile.new(Vector3(0, 0, -3), Vector3(0, 0, 120),
		Projectile.robot_owner(0), 60, 5.0))
	var seen: Array[String] = _run(sim, ShipInput.new(), 30)
	if seen != ["0:0"]:
		return "events %s, expected one on tick 0 for ship 0" % [seen]
	if sim.outcome() != ExitRule.Outcome.RUNNING:
		return "outcome %s with ship 1 flying" % sim.outcome()
	return ""


func test_a_wall_hit_reports_the_destruction() -> String:
	var sim: Sim = _sim()
	var ship: ShipState = sim.ships[0]
	ship.hull = 1.0
	ship.shield = 0.0
	ship.position = Vector3(0, 0, -98.9)
	ship.velocity = Vector3(0, 0, -20)
	var seen: Array[String] = _run(sim, ShipInput.new(), 10)
	if seen != ["0:0"]:
		return "events %s, expected one on tick 0" % [seen]
	if ship.velocity != Vector3.ZERO:
		return "the wreck still moves at %s" % ship.velocity
	return ""


func test_fire_reports_the_destruction() -> String:
	var sim: Sim = _sim()
	sim.set_reactor(ReactorState.parse_json(FAR_REACTOR_JSON))
	sim.set_debris(MeltdownDebris.parse_json(FIRE_DEBRIS))
	var ship: ShipState = sim.ships[0]
	# The start, and so the exit, is far from the fire, as in `test_meltdown_fire.gd`.
	ship.position = Vector3(-15, -15, 15)
	sim.step(_inputs(sim, ShipInput.new()))
	ship.position = Vector3(0, 0, -10)
	ship.hull = 1.0
	ship.shield = 0.0
	ship.shield_recharge = 0.0
	sim.reactor.apply_damage(40.0)
	var seen: Array[String] = _run(sim, ShipInput.new(), 30)
	if seen.size() != 1 or ship.hull != 0.0:
		return "events %s, hull %s" % [seen, ship.hull]
	return ""


func test_running_out_of_meltdown_reports_lost_then_destroyed() -> String:
	var sim: Sim = _sim()
	sim.set_reactor(ReactorState.parse_json(REACTOR_JSON))
	# The start, and so the exit, stays at the origin; the ship waits far from it.
	sim.step(_inputs(sim, ShipInput.new()))
	sim.ships[0].position = Vector3(0, 0, -30)
	sim.reactor.apply_damage(8.0)
	var order: Array[SimEvent.Kind] = []
	for i: int in 120:
		sim.step(_inputs(sim, ShipInput.new()))
		for event: SimEvent in sim.last_events:
			if event.kind in [SimEvent.Kind.SHIP_LOST_IN_MELTDOWN, SimEvent.Kind.SHIP_DESTROYED]:
				order.append(event.kind)
	if order != [SimEvent.Kind.SHIP_LOST_IN_MELTDOWN, SimEvent.Kind.SHIP_DESTROYED]:
		return "events %s" % [order]
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "outcome %s" % sim.outcome()
	return ""


func test_without_a_reactor_the_run_is_lost_once_every_ship_is_destroyed() -> String:
	var sim: Sim = _sim(2)
	if sim.outcome() != ExitRule.Outcome.RUNNING:
		return "a fresh run is %s" % sim.outcome()
	sim.ships[0].apply_damage(1000.0)
	if sim.outcome() != ExitRule.Outcome.RUNNING:
		return "one of two ships lost gave %s" % sim.outcome()
	sim.ships[1].apply_damage(1000.0)
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "both lost gave %s" % sim.outcome()
	if Sim.new(601, 0).outcome() != ExitRule.Outcome.RUNNING:
		return "a run with no ships is not running"
	return ""


func test_with_a_live_reactor_the_run_is_lost_once_every_ship_is_destroyed() -> String:
	var sim: Sim = _sim()
	sim.set_reactor(ReactorState.parse_json(REACTOR_JSON))
	sim.ships[0].apply_damage(1000.0)
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "gave %s" % sim.outcome()
	return ""


## A level without a reactor hashes no outcome, so losing the ship there moves
## the hash only through the ship's own state, and two runs agree (ARC-2).
func test_a_lost_run_is_deterministic() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = _moving_wreck()
		_run(sim, _everything(), 60)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "hashes %s" % [hashes]
	return ""


func test_the_bot_sends_nothing_for_a_destroyed_ship() -> String:
	var sim: Sim = _sim()
	var bot: BotPilot = BotPilot.new(sim)
	sim.ships[0].hull = 0.0
	var input: ShipInput = bot.next_input(0)
	if input.fire_primary or input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO \
			or input.afterburner or input.slot_held or input.reset_to_start:
		return "the bot sent input for a wreck"
	return ""
