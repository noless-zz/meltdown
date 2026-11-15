class_name ShipInputSource
extends RefCounted

## Supplies the local ship's input, one call per simulation tick.
##
## The session pulls input from here instead of reading devices itself, so
## `net/` stays free of nodes and input devices (ARC-1). The `xr/` layer will
## provide a subclass that returns the latest sampled controller state; tests
## provide scripted ones. This base class flies no input at all.


## Returns the input for simulation tick `tick` (the tick about to run).
func next_input(_tick: int) -> ShipInput:
	return ShipInput.new()
