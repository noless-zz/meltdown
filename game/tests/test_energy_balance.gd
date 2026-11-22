extends RefCounted

## Energy balance from the data files alone (#603, CMB-1, CMB-2, ARC-4). The
## owner could hold the trigger forever: 6 shots/s at 2 energy matched the
## ship's recharge, so the energy bar never meant anything. These bounds keep
## sustained fire limited by the pool whatever the files are tuned to.
##
## The pool counts as empty on the first tick a shot is due but the pool cannot
## pay for it: from then on the trigger no longer fires at the weapon's rate.

const SHIP_FILE: String = "res://data/ships/default_ship.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## The issue's rate: 4 shots per second.
const FIRE_INTERVAL_TICKS: int = 15
## Sustained fire alone empties a full pool in this window, inclusive.
const FIRE_EMPTY_MIN_S: float = 8.0
const FIRE_EMPTY_MAX_S: float = 12.0
## Firing while boosting empties the pool faster than this.
const BOOST_FIRE_EMPTY_MAX_S: float = 5.0
## Resting this long after emptying brings back at least REST_SHARE of the pool.
const REST_S: float = 3.0
const REST_SHARE: float = 1.0 / 3.0
## A minute: a pool that has not emptied by then never will.
const TICK_LIMIT: int = 3600


static func _ship() -> ShipState:
	var ship: ShipState = ShipState.new()
	ShipTuning.parse_json(FileAccess.get_file_as_string(SHIP_FILE)).apply_to(ship)
	ship.primary_slots[0] = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	return ship


## Seconds of holding the trigger (and the afterburner when `boost`) before
## the first shot the pool cannot pay for, or INF. Fires after `step` as the
## simulation does.
static func seconds_to_empty(ship: ShipState, boost: bool) -> float:
	var thrust: Vector3 = Vector3.FORWARD if boost else Vector3.ZERO
	for tick: int in TICK_LIMIT:
		ship.step(thrust, Vector3.ZERO, boost)
		var due: bool = ship.fire_cooldowns[0] <= 1
		if ship.fire_primary(true).is_empty() and due:
			return float(tick + 1) * ShipState.TICK_DT
	return INF


## Energy regained over `seconds` of flying without firing or boosting.
static func regained(ship: ShipState, seconds: float) -> float:
	var before: float = ship.energy
	for tick: int in roundi(seconds / ShipState.TICK_DT):
		ship.step(Vector3.ZERO, Vector3.ZERO, false)
		ship.fire_primary(false)
	return ship.energy - before


## The numbers the pull request states.
static func table() -> Dictionary:
	var fire_ship: ShipState = _ship()
	var fire_s: float = seconds_to_empty(fire_ship, false)
	var rest: float = regained(fire_ship, REST_S)
	var boost_s: float = seconds_to_empty(_ship(), true)
	return {"fire_s": fire_s, "rest_regained": rest, "boost_fire_s": boost_s,
		"max_energy": fire_ship.max_energy}


func test_the_pulse_cannon_fires_four_times_a_second() -> String:
	var cannon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	if cannon.fire_interval_ticks != FIRE_INTERVAL_TICKS:
		return "pulse cannon fires every %d ticks, want %d" % [cannon.fire_interval_ticks, FIRE_INTERVAL_TICKS]
	return ""


func test_sustained_fire_empties_a_full_pool_in_8_to_12_s() -> String:
	var seconds: float = seconds_to_empty(_ship(), false)
	if seconds < FIRE_EMPTY_MIN_S or seconds > FIRE_EMPTY_MAX_S:
		return "sustained fire empties the pool in %.2f s, want %.0f to %.0f s" % [
			seconds, FIRE_EMPTY_MIN_S, FIRE_EMPTY_MAX_S]
	return ""


func test_three_seconds_rest_brings_back_a_third_of_the_pool() -> String:
	var ship: ShipState = _ship()
	seconds_to_empty(ship, false)
	var gained: float = regained(ship, REST_S)
	if gained < ship.max_energy * REST_SHARE:
		return "%.0f s without firing regains %.1f energy, want at least %.1f" % [
			REST_S, gained, ship.max_energy * REST_SHARE]
	return ""


func test_firing_while_boosting_empties_the_pool_in_under_5_s() -> String:
	var seconds: float = seconds_to_empty(_ship(), true)
	if seconds >= BOOST_FIRE_EMPTY_MAX_S:
		return "firing while boosting empties the pool in %.2f s, want under %.0f s" % [
			seconds, BOOST_FIRE_EMPTY_MAX_S]
	return ""


## The shield refills from the same pool, so a ship recharging its shield
## runs dry sooner than one with a full shield.
func test_shield_recharge_draws_from_the_firing_pool() -> String:
	var full: float = seconds_to_empty(_ship(), false)
	var hurt: ShipState = _ship()
	hurt.shield = 0.0
	var hurt_s: float = seconds_to_empty(hurt, false)
	if hurt.shield <= 0.0:
		return "the shield did not recharge while firing"
	if hurt_s >= full:
		return "an empty shield emptied the pool in %.2f s, a full one in %.2f s; want sooner" % [
			hurt_s, full]
	return ""


func test_the_stated_numbers_are_finite() -> String:
	var rows: Dictionary = table()
	print("Meltdown: energy balance %s" % JSON.stringify(rows))
	for key: String in ["fire_s", "boost_fire_s"]:
		if is_inf(float(rows[key])):
			return "%s never empties" % key
	return ""
