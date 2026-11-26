class_name OtherShipsView
extends Node3D

## Draws the ships flown beside the local one (#1354, PRF-8, GFX-2): the
## stress scene's three extra ships now, the co-op crew later. Each is a
## `ShipModel` of the shipped look, blended between the tick before the latest
## one and the latest, as the robots are. A ship destroyed or gone out through
## the exit is hidden.
##
## It is handed copies of ship states and reads them only; it holds no
## simulation object, so it can never write simulation state (MP-2).

const NODE_NAME: String = "OtherShips"

var _look: ShipLook = null
var _models: Array[ShipModel] = []


func _init(look: ShipLook = null) -> void:
	name = NODE_NAME
	_look = look


## Shows one ship per entry of `current`, at `fraction` (0..1) of the way from
## its pose in `previous` (the same order; a missing entry is drawn where
## `current` has it). Models beyond `current` are hidden.
func show_ships(previous: Array[ShipState], current: Array[ShipState], fraction: float) -> void:
	while _models.size() < current.size():
		if _look == null:
			_look = ShipLook.load_file()
		var model: ShipModel = ShipModel.create(_look)
		model.name = "Ship%d" % (_models.size() + 1)
		_models.append(model)
		add_child(model)
	for index: int in _models.size():
		var model: ShipModel = _models[index]
		var ship: ShipState = current[index] if index < current.size() else null
		model.visible = ship != null and not ship.is_destroyed() and not ship.escaped
		if model.visible:
			var before: ShipState = previous[index] if index < previous.size() else ship
			model.show_at(pose_between(before, ship, fraction), thrust_of(ship))


## The models, ship 1 first, shown or not.
func models() -> Array[ShipModel]:
	return _models.duplicate()


## Number of ships drawn this frame.
func shown() -> int:
	var count: int = 0
	for model: ShipModel in _models:
		if model.visible:
			count += 1
	return count


## `before`'s pose blended toward `after`'s by `fraction`.
static func pose_between(before: ShipState, after: ShipState, fraction: float) -> Transform3D:
	var amount: float = clampf(fraction, 0.0, 1.0)
	var turn: Quaternion = before.orientation.get_rotation_quaternion().slerp(
		after.orientation.get_rotation_quaternion(), amount)
	return Transform3D(Basis(turn), before.position.lerp(after.position, amount))


## How hard the engine glows: full on the afterburner, else the share of top speed.
static func thrust_of(ship: ShipState) -> float:
	if ship.afterburner_active:
		return 1.0
	return clampf(ship.velocity.length() / maxf(ship.max_speed, 0.001), 0.0, 1.0)
