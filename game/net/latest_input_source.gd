class_name LatestInputSource
extends ShipInputSource

## Holds the most recently sampled input and hands it to every tick until a
## newer one is set. Frames and ticks run at different rates, so one sample
## may cover several ticks, or none.
##
## The caller (the main scene, later the controller reader) sets the input;
## nothing here reads a device, so `net/` stays free of input APIs (ARC-1).

var _latest: ShipInput = ShipInput.new()


## Makes `input` the input for every tick from now on. The values are copied,
## so changing `input` afterwards does not change what the ship flies.
func set_input(input: ShipInput) -> void:
	_latest = _copy(input) if input != null else ShipInput.new()


## The values that the next tick will fly, as a copy.
func latest_input() -> ShipInput:
	return _copy(_latest)


## Returns a new object on every call: the replay stores each tick's object,
## so handing out one shared object would let a later `set_input` or a caller
## rewrite the recorded past.
func next_input(_tick: int) -> ShipInput:
	return _copy(_latest)


static func _copy(input: ShipInput) -> ShipInput:
	return ShipInput.new(input.thrust_q, input.turn_q, input.afterburner)
