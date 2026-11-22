class_name AcceptanceAutoLevelCheck
extends RefCounted

## The `auto_level_option` check (#1247, CMF-1, CMF-5, DEV-6, decision record
## 0005). In a suite:
##
##     {"id": "auto_level_option", "preset": 4,
##      "checks": ["auto_level_option", "no_script_errors"]}
##
## With the scene's comfort wiring on the step's preset, it turns the menu's
## Auto-level option on, as choosing it in the menu does, and flies a
## scripted roll: the right grip held, mapped through the default controller
## layout and the wiring's comfort filter, until the bank reaches 60 degrees,
## then released for `RELEASE_SECONDS`. It flies the same with the option off.
## It passes when the bank came back to level with the option on and stayed
## where it was released with it off. The roll flies on a scratch `ShipState`,
## the code the simulation turns ships with, so the scene's session is never
## touched, and the wiring's own choice is put back afterwards; nothing is
## saved.

## Bank the scripted roll holds the grip until, in degrees.
const TARGET_DEG: float = 60.0
## Longest the grip is held, so a roll that never banks cannot hang the step.
const MAX_ROLL_TICKS: int = 600
## Released for 60 / 30 degrees per second plus a margin.
const RELEASE_SECONDS: float = 3.0
## Bank counted as level, and the drift allowed with the option off, in degrees.
const LEVEL_DEG: float = 0.01


## [result, message]; `measurements` gets the bank at release and after it.
static func run(main: Node, measurements: Dictionary) -> Array:
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	if comfort == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no comfort wiring"]
	if AutoLevelChoice.fixed_by(comfort.preset_for(comfort.number)):
		return [AcceptanceReport.RESULT_FAIL, "preset %d always levels; fly a preset the option switches"
			% comfort.number]
	var kept: int = comfort.auto_level_choice
	comfort.set_auto_level_choice(true)
	var on: Vector2 = fly(comfort.filter)
	comfort.set_auto_level_choice(false)
	var off: Vector2 = fly(comfort.filter)
	comfort.auto_level_choice = kept
	comfort.set_preset(comfort.number)
	measurements["released_on_deg"] = snappedf(on.x, 0.001)
	measurements["after_on_deg"] = snappedf(on.y, 0.001)
	measurements["released_off_deg"] = snappedf(off.x, 0.001)
	measurements["after_off_deg"] = snappedf(off.y, 0.001)
	return judge(on, off)


## [result, message] for the banks (at release, after release) with the
## option on and off.
static func judge(on: Vector2, off: Vector2) -> Array:
	for flown: Vector2 in [on, off]:
		if absf(flown.x) < TARGET_DEG:
			return [AcceptanceReport.RESULT_FAIL, "the scripted roll reached only %.2f deg" % flown.x]
	if absf(on.y) > LEVEL_DEG:
		return [AcceptanceReport.RESULT_FAIL, "with the option on, %.3f deg of bank was left" % on.y]
	if absf(off.y - off.x) > LEVEL_DEG:
		return [AcceptanceReport.RESULT_FAIL, "with the option off, the bank moved from %.3f to %.3f deg"
			% [off.x, off.y]]
	return [AcceptanceReport.RESULT_PASS, "on: %.1f deg levelled; off: %.1f deg kept" % [on.x, off.x]]


## Rolls a level ship through `filter` until it banks `TARGET_DEG`, then
## releases; returns (bank at release, bank after `RELEASE_SECONDS`) in degrees.
static func fly(filter: ComfortInputFilter) -> Vector2:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var ship: ShipState = ShipState.new()
	var ticks: int = 0
	while absf(_bank_deg(ship)) < TARGET_DEG and ticks < MAX_ROLL_TICKS:
		_tick(filter, ship, mapping.map_controls(Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 1.0))
		ticks += 1
	var released: float = _bank_deg(ship)
	for tick: int in roundi(RELEASE_SECONDS * ShipState.TICK_RATE):
		_tick(filter, ship, mapping.map_controls(Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0))
	return Vector2(released, _bank_deg(ship))


static func _tick(filter: ComfortInputFilter, ship: ShipState, input: ShipInput) -> void:
	ship.step(Vector3.ZERO, filter.filter(input, ship.orientation).turn())


static func _bank_deg(ship: ShipState) -> float:
	return rad_to_deg(ComfortAutoLevel.bank(ship.orientation))
