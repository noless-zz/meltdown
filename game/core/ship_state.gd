class_name ShipState
extends RefCounted

## Deterministic state of one ship, advanced on the fixed simulation tick.
##
## No nodes, no input devices, no wall-clock time: the same sequence of
## inputs always produces the same state (ARC-1, ARC-2). Presentation and
## comfort code read this state and never write it (ARC-3).

const TICK_RATE: int = 60
const TICK_DT: float = 1.0 / TICK_RATE

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var orientation: Basis = Basis.IDENTITY

var max_speed: float = 20.0
var acceleration: float = 40.0
var damping: float = 2.0

## Afterburner (FLT-2). Energy is in abstract units; rates are per second and
## applied per tick. With these values a full pool lasts four seconds of boost
## and refills from empty in eight.
var max_energy: float = 100.0
var energy: float = 100.0
var afterburner_max_speed: float = 35.0
var afterburner_acceleration: float = 80.0
var afterburner_drain: float = 25.0
var energy_recharge: float = 12.5
## Once the pool runs dry the afterburner stays off until energy is back at
## this level. Without it, a held button would flick the boost on and off
## every tick as each tick's recharge was spent at once.
var afterburner_restart_energy: float = 25.0
## True from the tick the pool ran dry until it reaches the restart level.
var afterburner_locked: bool = false
## Whether the afterburner boosted on the last tick. Derived from the tick's
## input and the energy pool, so it is not hashed; `Sim` compares it across
## ticks to report the afterburner starting and stopping.
var afterburner_active: bool = false

## Hull and wall bounces (FLT-3). Hull is in abstract points; collision
## damage is permanent for the run (CMB-2). With these values a head-on hit at
## full normal speed (20 m/s) costs 10 points: minor, as FLT-3 asks.
var max_hull: float = 100.0
var hull: float = 100.0
## Radius of the ship's collision sphere, in metres.
var radius: float = 1.0
## Fraction of the speed into a wall that is kept, reversed, by the bounce.
## Unitless, 0..1. Values below MIN_WALL_RESTITUTION are raised to it so that
## a bounce never stops the ship dead (FLT-3).
var wall_restitution: float = 0.5
## Hull points lost per metre per second of impact speed into the wall.
var wall_damage_per_speed: float = 0.5
## Impact speed into the wall, in metres per second, below which a bounce
## deals no damage: scraping along a wall is not punished.
var wall_damage_min_speed: float = 4.0

## Shields (CMB-2). Shield is in the same abstract points as hull and takes
## every hit first; unlike hull it recharges from the energy pool. With these
## values an empty shield refills in ten seconds and costs half the pool.
var max_shield: float = 50.0
var shield: float = 50.0
## Shield points regained per second while below `max_shield` and energy is
## available.
var shield_recharge: float = 5.0
## Energy units spent per shield point regained.
var shield_energy_cost: float = 1.0

## Weapon slots (CMB-1). Every slot starts empty; in a run they are filled
## only by salvage, so a ship cannot simply choose its loadout. Two primary
## and two secondary slots.
var primary_slots: Array[WeaponDef] = [null, null]
var secondary_slots: Array[WeaponDef] = [null, null]
## Part id of the weapon in each primary slot, "" when empty or unknown. A
## weapon replaced by slotting is dropped under this id, so it can be picked up
## again (`PartSlotting`). Not hashed: the id is fixed by the replay's weapon
## lines and hold, and the weapon's values are already in the hash.
var primary_ids: Array[String] = ["", ""]
## Index into `primary_slots` of the weapon `fire_primary` uses.
var selected_primary: int = 0
## Ticks until the selected primary may fire again; 0 means ready.
var fire_cooldown: int = 0

## Salvage hold (SLV-1). Parts taken from the mine wait here, by id, until
## they are slotted. One part, as it is pulled into the cockpit.
const HOLD_CAPACITY: int = 1
## Part ids in the order they were taken, at most HOLD_CAPACITY.
var hold: Array[String] = []
## Set by `ExitRule` when the ship leaves through the exit during the meltdown
## (RUN-3); `Sim` then stops stepping it and nothing can hit it. Not in this
## state's hash: `Sim` hashes it with the reactor, so levels without one keep
## their hashes.
var escaped: bool = false

const MIN_WALL_RESTITUTION: float = 0.05


## Advances one tick.
## `thrust` is in ship space, each axis in -1..1 (x strafe, y lift, z forward
## is negative, matching Godot's camera convention).
## `turn` is pitch, yaw and roll rate in radians per second.
## `afterburner` is whether the afterburner is held this tick.
func step(thrust: Vector3, turn: Vector3, afterburner: bool = false) -> void:
	if turn != Vector3.ZERO:
		orientation = orientation.rotated(orientation.x.normalized(), turn.x * TICK_DT)
		orientation = orientation.rotated(orientation.y.normalized(), turn.y * TICK_DT)
		orientation = orientation.rotated(orientation.z.normalized(), turn.z * TICK_DT)
		orientation = orientation.orthonormalized()
	# Energy order within a tick: the afterburner drains (or the pool
	# recharges) first, then the shield buys what it can from what is left.
	# Boosting therefore never fails because the shield took the energy.
	var boosting: bool = _update_energy(afterburner)
	afterburner_active = boosting
	_recharge_shield()
	var speed_before: float = velocity.length()
	var wish: Vector3 = orientation * thrust.limit_length(1.0)
	velocity += wish * (afterburner_acceleration if boosting else acceleration) * TICK_DT
	velocity -= velocity * minf(damping * TICK_DT, 1.0)
	# After a boost the ship may be above the normal cap. Clamping straight to
	# it would stop the ship hard in one tick; instead the speed may not grow
	# and damping brings it back down over the next second or so.
	var cap: float = afterburner_max_speed if boosting else maxf(max_speed, speed_before)
	velocity = velocity.limit_length(cap)
	position += velocity * TICK_DT


## Drains or recharges the pool for this tick and returns whether the
## afterburner is active on it.
func _update_energy(held: bool) -> bool:
	if afterburner_locked and energy >= afterburner_restart_energy:
		afterburner_locked = false
	var boosting: bool = held and not afterburner_locked and energy > 0.0
	if boosting:
		energy = maxf(energy - afterburner_drain * TICK_DT, 0.0)
		if energy <= 0.0:
			afterburner_locked = true
	else:
		energy = minf(energy + energy_recharge * TICK_DT, max_energy)
	return boosting


## Refills the shield for this tick from the energy pool, as far as the
## pool allows. Hull is never refilled here: its damage is permanent (CMB-2).
func _recharge_shield() -> void:
	if shield >= max_shield or energy <= 0.0:
		return
	var points: float = minf(shield_recharge * TICK_DT, max_shield - shield)
	var cost: float = points * shield_energy_cost
	if cost > energy:
		points = energy / shield_energy_cost
		cost = energy
	shield = minf(shield + points, max_shield)
	energy = maxf(energy - cost, 0.0)


## The one way any damage reaches a ship: the shield absorbs what it can and
## the rest comes off the hull. Neither drops below zero; what happens at zero
## hull is not decided yet. Negative amounts are ignored, so damage can never
## repair.
func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	var absorbed: float = minf(amount, shield)
	shield -= absorbed
	hull = maxf(hull - (amount - absorbed), 0.0)


## Counts the fire interval down and, if `held`, fires the selected primary
## weapon when it is ready and the pool holds its energy cost. Returns the
## weapon that fired, or null. Call once per tick, after `step`, so a shot
## spends what is left after the afterburner and the shield.
func fire_primary(held: bool) -> WeaponDef:
	if fire_cooldown > 0:
		fire_cooldown -= 1
	if not held or fire_cooldown > 0:
		return null
	var weapon: WeaponDef = primary_slots[selected_primary]
	if weapon == null or energy < weapon.energy_cost:
		return null
	energy -= weapon.energy_cost
	fire_cooldown = weapon.fire_interval_ticks
	return weapon


func hold_has_room() -> bool:
	return hold.size() < HOLD_CAPACITY


## Restitution actually used by a bounce: `wall_restitution` kept in
## MIN_WALL_RESTITUTION..1.
func bounce_factor() -> float:
	return clampf(wall_restitution, MIN_WALL_RESTITUTION, 1.0)


## Applies the damage of one wall hit at `impact_speed` metres per second
## into the wall, through `apply_damage`.
func take_wall_hit(impact_speed: float) -> void:
	if impact_speed < wall_damage_min_speed:
		return
	apply_damage(impact_speed * wall_damage_per_speed)


## Hash of the full state, used by replay tests and network desync checks.
## Hull and shield each join the hash only once they differ from their
## maximum, so replays recorded before they existed, which never touch a
## wall, keep their hashes. Each carries a tag: untagged, a damaged hull with
## a full shield and a full hull with an equally damaged shield appended the
## same number and hashed alike, which would hide a desync (MP-2).
func state_hash() -> int:
	var parts: Array = [position, velocity, orientation, energy, afterburner_locked]
	if hull != max_hull:
		parts.append(["hull", hull])
	if shield != max_shield:
		parts.append(["shield", shield])
	# Weapons join only once a slot is filled or a cooldown runs, so ships
	# that never carried a weapon keep their hashes.
	var weapons: Array = ["weapons", selected_primary, fire_cooldown]
	var armed: bool = fire_cooldown != 0
	for slot: WeaponDef in primary_slots + secondary_slots:
		weapons.append(slot.values_hash() if slot != null else 0)
		armed = armed or slot != null
	if armed:
		parts.append(weapons)
	# Joins only once something is held, so earlier replays keep their hashes.
	if not hold.is_empty():
		parts.append(["hold", hold.duplicate()])
	return hash(parts)
