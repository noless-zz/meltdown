class_name DevMenuRestart
extends DevMenuEntry

## The dev menu's Level, Restart level and Flight test entries (#763, #839,
## CMF-8): each closes the menu and flies again behind a fade. Split from
## `DevMenuWiring` (#892).
##
## A level flies that file or seed, Random a fresh seed, Restart the current
## source, all from the start. Flight test restarts the test tunnel behind the
## same fade and runs the first-launch test again there
## (`FlightTestWiring.run_again`). Nothing here writes simulation state: the
## restart goes through `main.gd`'s `restart_level`, a new session from the
## start (MP-2, ARC-3).

const FADE_SECONDS: float = ResetHold.FADE_SECONDS
const LOG_PREFIX: String = "Meltdown: dev menu"

## Picks the seed for `random` (`LevelSwitch.random_seed` when not set);
## tests inject one so they are not flaky.
var pick_seed: Callable = Callable()
## The fade's opacity, 0 (clear) to 1 (black), for the fade quad.
var alpha: float = 0.0
## Set by `DevMenuWiring.attach`.
var level_start: LevelStart = null
var restart: Callable = Callable()
var flight_test: FlightTestWiring = null
var rig: Node3D = null

var _test_pending: bool = false  # The pending restart is the Flight test entry's (#839).
## The source to fly once the view is black; null while no restart waits.
var _pending: Variant = null
## When the current fade phase began on the steady clock; < 0 when no fade runs.
var _fade_from: float = -1.0


func _init() -> void:
	super([DevMenuSpec.KIND_LEVEL, DevMenuSpec.KIND_RESTART, DevMenuSpec.KIND_FLIGHT_TEST],
		[DevMenuModel.LEVEL_PREFIX, DevMenuModel.RESTART, DevMenuModel.FLIGHT_TEST], true)


func choose(result: String) -> void:
	if result.begins_with(DevMenuModel.LEVEL_PREFIX):
		var source: String = result.substr(DevMenuModel.LEVEL_PREFIX.length())
		if source == DevMenuModel.RANDOM:
			var picked: int = int(pick_seed.call()) if pick_seed.is_valid() else LevelSwitch.random_seed()
			source = LevelSwitch.SEED_PREFIX + str(picked)
		_start(source)
	elif result == DevMenuModel.RESTART:
		_start(level_start.source if level_start != null else "")
	elif result == DevMenuModel.FLIGHT_TEST and flight_test != null:
		_start("")  # The test flies in the test tunnel, as on first launch.
		_test_pending = true


func _start(source: String) -> void:
	print("%s flies %s" % [LOG_PREFIX, source if source != "" else "the test tunnel"])
	_pending = source
	_fade_from = -1.0  # Started on the next `advance`, on its clock.


## Drops a restart that waits and ends its fade at once, clear (#1170): the
## hub opened, and a level must not start behind it.
func cancel() -> void:
	if _pending != null:
		print("%s drops %s: the hub opened" % [LOG_PREFIX, str(_pending)])
	_pending = null
	_test_pending = false
	_fade_from = -1.0
	alpha = 0.0


## Once a frame: fades out, restarts on the black frame, fades back in.
func advance(now: float) -> void:
	if _pending == null and _fade_from < 0.0:
		alpha = 0.0
		return
	if _fade_from < 0.0:
		_fade_from = now
	var part: float = clampf((now - _fade_from) / FADE_SECONDS, 0.0, 1.0)
	if _pending == null:
		alpha = 1.0 - part
		if part >= 1.0:
			_fade_from = -1.0
		return
	alpha = part
	if part >= 1.0:
		if level_start != null:
			level_start.source = str(_pending)
		_pending = null
		_fade_from = now
		if restart.is_valid():
			restart.call()
		if _test_pending:
			_test_pending = false
			flight_test.run_again(rig)
