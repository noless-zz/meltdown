class_name ShipGauges
extends RefCounted

## What a pilot reads off the ship in a fight, taken once a frame (#1216,
## from the owner's #1207): hull, shield and energy as fractions 0..1 of their
## maximums, and the meltdown countdown in seconds, or none. The status panel
## reads its bars and countdown only through this, and the cockpit's own
## instruments (M6) will read the same snapshot, so every display agrees.
##
## A plain snapshot: it is made from session copies of the ship and the
## reactor, keeps no reference to either and writes nothing back (ARC-3,
## MP-2).

## The gauge names a cockpit file's instruments may read (`CockpitInstrument`).
const HULL: String = "hull"
const SHIELD: String = "shield"
const ENERGY: String = "energy"
const COUNTDOWN: String = "countdown"
const NAMES: Array[String] = [HULL, SHIELD, ENERGY, COUNTDOWN]
## `countdown` when no meltdown is running.
const NO_COUNTDOWN: float = -1.0

## Fraction of the hull left, 0..1.
var hull: float = 1.0
## Fraction of the shield left, 0..1.
var shield: float = 1.0
## Fraction of the energy pool left, 0..1.
var energy: float = 1.0
## Seconds of meltdown left, or `NO_COUNTDOWN`.
var countdown: float = NO_COUNTDOWN


## Gauges with the given values; fractions are clamped to 0..1, a value that
## is not a finite number reads empty (as the panel's bars always drew it),
## and a negative countdown means none.
static func of(p_hull: float, p_shield: float, p_energy: float,
		p_countdown: float = NO_COUNTDOWN) -> ShipGauges:
	var gauges: ShipGauges = ShipGauges.new()
	gauges.hull = _clamped(p_hull)
	gauges.shield = _clamped(p_shield)
	gauges.energy = _clamped(p_energy)
	gauges.countdown = p_countdown if p_countdown >= 0.0 and is_finite(p_countdown) else NO_COUNTDOWN
	return gauges


## This frame's gauges from `ship` and `reactor`, session copies; `reactor`
## may be null (the test tunnel has none). A maximum of zero reads empty. The
## countdown runs only once the reactor is destroyed, at its 60 ticks a second.
static func take(ship: ShipState, reactor: ReactorState) -> ShipGauges:
	var countdown_seconds: float = NO_COUNTDOWN
	if reactor != null and reactor.destroyed:
		countdown_seconds = float(reactor.meltdown_ticks_left) / float(ReactorState.TICKS_PER_SECOND)
	return of(_fraction(ship.hull, ship.max_hull), _fraction(ship.shield, ship.max_shield),
		_fraction(ship.energy, ship.max_energy), countdown_seconds)


## Whether a meltdown countdown is running.
func has_countdown() -> bool:
	return countdown >= 0.0


## The value of the gauge named `gauge_name` (one of `NAMES`); 0 for an
## unknown name, which `CockpitInstrument` never lets through.
func value(gauge_name: String) -> float:
	match gauge_name:
		HULL:
			return hull
		SHIELD:
			return shield
		ENERGY:
			return energy
		COUNTDOWN:
			return countdown
	return 0.0


static func _clamped(fraction: float) -> float:
	return clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0


static func _fraction(amount: float, maximum: float) -> float:
	return amount / maximum if maximum > 0.0 else 0.0
