class_name StickDeadZone
extends RefCounted

## The thumbstick dead zone as a feel value read from a layout file (#855,
## PLT-5, ARC-4), so it can be tuned without code (decision record 0003).
##
## A layout file may carry `"stick_dead_zone"` beside its bindings. It is
## optional: a file without it uses `DEFAULT`. A bad value is not fatal the
## way a bad binding is, because flying with the default dead zone is safe:
## it is dropped with a warning naming the file and the field, and the rest
## of the layout still loads.
## Input side only: nothing here reaches the simulation (ARC-3).

const FIELD: String = "stick_dead_zone"
## The value the constant had before #855; both shipped layouts set it.
const DEFAULT: float = 0.15
const MIN: float = 0.0
## Past half the stick's travel the ship would barely respond.
const MAX: float = 0.5


## The dead zone `data` (a parsed layout file) asks for, and a warning when
## the value was rejected: `{"value": float, "warning": String}`. `source`
## names the file in the warning.
static func read(data: Dictionary, source: String) -> Dictionary:
	if not data.has(FIELD):
		return {"value": DEFAULT, "warning": ""}
	var raw: Variant = data[FIELD]
	# A bool must not pass as 0 or 1.
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return _rejected(source, "must be a number, got %s" % JSON.stringify(raw))
	var value: float = float(raw)
	if value < MIN or value > MAX:
		return _rejected(source, "is %s, must be in %s..%s" % [value, MIN, MAX])
	return {"value": value, "warning": ""}


## Scales a stick so that the dead zone gives exactly zero and the output
## rises from zero at its edge to 1 at full deflection, in the same direction.
static func apply(stick: Vector2, dead_zone: float) -> Vector2:
	var length: float = stick.length()
	# Vector2 holds 32-bit floats, so a stick reading exactly on the edge can
	# come out a hair longer than the 64-bit value.
	if length <= dead_zone or is_equal_approx(length, dead_zone):
		return Vector2.ZERO
	var scaled: float = (minf(length, 1.0) - dead_zone) / (1.0 - dead_zone)
	return stick / length * scaled


static func _rejected(source: String, problem: String) -> Dictionary:
	return {
		"value": DEFAULT,
		"warning": "%s: \"%s\" %s; using %s" % [source, FIELD, problem, DEFAULT],
	}
