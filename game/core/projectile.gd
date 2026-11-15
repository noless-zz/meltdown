class_name Projectile
extends RefCounted

## One live projectile, owned by `Sim` and advanced on the fixed tick (CMB-1).
## Plain data in world space: no node, so the server can simulate it and the
## view can draw it from the same state (MP-2).

var position: Vector3 = Vector3.ZERO
## Metres per second.
var velocity: Vector3 = Vector3.ZERO
## Index in `Sim.ships` of the ship that fired it.
var owner_index: int = 0
## Ticks it still flies; it is removed when this reaches zero.
var ticks_left: int = 0
## Damage it deals on a hit (hits arrive in a later issue).
var damage: float = 0.0


func _init(p_position: Vector3 = Vector3.ZERO, p_velocity: Vector3 = Vector3.ZERO,
		p_owner_index: int = 0, p_ticks_left: int = 0, p_damage: float = 0.0) -> void:
	position = p_position
	velocity = p_velocity
	owner_index = p_owner_index
	ticks_left = p_ticks_left
	damage = p_damage


## Moves one tick and counts it off. Returns false once its lifetime is over.
func advance() -> bool:
	position += velocity * ShipState.TICK_DT
	ticks_left -= 1
	return ticks_left > 0


func state_hash() -> int:
	return hash([position, velocity, owner_index, ticks_left, damage])
