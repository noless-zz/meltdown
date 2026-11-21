class_name DevMenuWiring
extends RefCounted

## Opens the in-headset dev menu (#753) on a short tap of the left menu button
## and acts on what it returns (#763, decision record 0009). The owner chose
## the tap on #748; the hold of the same button stays the reset (#162), so one
## press is never both (`MenuTap`).
##
## While the menu is open it takes the controls: the frame's values reach the
## rest of `main.gd` idle, so the ship gets neutral input and drifts to a stop
## the way the flight test holds it, and the right stick, A, B, Y and the
## triggers drive the menu's named actions instead. Only the menu button
## passes through, so a hold still resets. Nothing here writes simulation
## state: a level or restart goes through `main.gd`'s `restart_level`, a new
## session from the start, behind a fade (MP-2, ARC-3, CMF-8).
##
## The tap does nothing during the first-launch flight test or while the
## destroyed or escape screen is up, and closes a menu left open then. The
## break prompt (#716) still takes a tap first, through `UpdateWiring.tap_taker`.
## A newer build that waits is an entry in the menu, and choosing it does
## what the tap did before (`UpdateWiring.choose_waiting`).
##
## A Controls choice (#778) switches `ControlSchemeSwitch` for the rest of
## the session and saves it in `ControlsChoice`. The menu is open at that
## moment, so the ship is already on neutral input, and the switch lets go of
## any grip the gripped scheme held.
##
## It sits beside `main.gd` because it restarts the `net/` session and reads
## the flight test and the end screens; `main.gd` gains only a few lines.

## A stick pushed this far counts as a menu step; well past drift, short of the rim.
const STICK_STEP: float = 0.6
## A trigger pulled this far steps the seed by ten.
const TRIGGER_STEP: float = 0.5
## Button -> menu action while the menu is open. A confirms, as it restarts
## after a loss; B and Y step the seed up and down, as they lift the ship.
const BUTTON_ACTIONS: Dictionary[String, String] = {
	"right_button_lower": DevMenuModel.CONFIRM,
	"right_button_upper": DevMenuModel.SEED_UP,
	"left_button_upper": DevMenuModel.SEED_DOWN,
}
const FADE_SECONDS: float = ResetHold.FADE_SECONDS
const LOG_PREFIX: String = "Meltdown: dev menu"

## Under the rig once `attach` has run.
var menu: DevMenu = null
var tap: MenuTap = MenuTap.new()
## Saves the chosen corner; tests point it at a temporary file.
var corner_store: PanelCorner = PanelCorner.new()
## Saves the chosen control scheme; tests point it at a temporary file.
var controls_store: ControlsChoice = ControlsChoice.new()
## The scheme the ship flies through and the mapping whose hand setting it
## prints; null in tests that do not switch schemes.
var scheme: ControlSchemeSwitch = null
var mapping: ThumbstickMapping = null
## Picks the seed for `random` (`LevelSwitch.random_seed` when not set);
## tests inject one so they are not flaky.
var pick_seed: Callable = Callable()
## The fade's opacity, 0 (clear) to 1 (black), for the fade quad.
var alpha: float = 0.0

var _update: UpdateWiring = null
var _level_start: LevelStart = null
var _restart: Callable = Callable()
var _flight_test: FlightTestWiring = null
var _destroyed: DestroyedWiring = null
## The source to fly once the view is black; null while no restart waits.
var _pending: Variant = null
## When the current fade phase began on the steady clock; < 0 when no fade runs.
var _fade_from: float = -1.0


func _init(p_scheme: ControlSchemeSwitch = null, p_mapping: ThumbstickMapping = null) -> void:
	scheme = p_scheme
	mapping = p_mapping


## Hangs `p_menu` under `rig` (none in some tests). `restart` flies
## `level_start.source` again from its start; the flight test and the end
## screens say when the tap is ignored. Calling it again adds nothing.
func attach(rig: Node3D, update: UpdateWiring, level_start: LevelStart, restart: Callable,
		flight_test: FlightTestWiring, destroyed: DestroyedWiring, p_menu: DevMenu = null) -> void:
	if menu != null:
		return
	_update = update
	_level_start = level_start
	_restart = restart
	_flight_test = flight_test
	_destroyed = destroyed
	menu = p_menu if p_menu != null else DevMenu.new()
	if rig != null:
		rig.add_child(menu)


func is_open() -> bool:
	return menu != null and menu.visible


## Whether the tap is ignored now: the flight test runs or an end screen is up.
func blocked() -> bool:
	if _flight_test != null and _flight_test.running():
		return true
	if _destroyed == null:
		return false
	return _destroyed.fade_alpha() > 0.0 or _destroyed.sequence.line_shown() \
		or _destroyed.escape.sequence.line_shown()


## Once per frame, first, with the sampled `values`. Returns the values the
## rest of the frame should read: `values` while the menu is closed, idle
## values but for the menu button while it is open.
func read(values: Dictionary, now: float = MenuTap.steady_seconds()) -> Dictionary:
	if _update != null:
		_update.step()
	_advance_fade(now)
	var tapped: bool = tap.feed(ResetHold.is_held(values), now)
	if tapped and _update != null and _update.tap_taker.is_valid() and bool(_update.tap_taker.call()):
		tapped = false
	if menu == null:
		return values
	menu.set_update(_update.waiting_version() if _update != null else "",
		_update != null and _update.download_busy())
	if blocked():
		menu.close()
	elif tapped:
		_toggle()
	if not is_open():
		return values
	apply(menu.update(actions(values)))
	return neutral(values)


## The menu's named actions held in `values`.
static func actions(values: Dictionary) -> Dictionary:
	var stick: Vector2 = values.get("right_stick", Vector2.ZERO)
	var buttons: Dictionary = values.get("buttons", {})
	var held: Dictionary = {
		DevMenuModel.UP: stick.y >= STICK_STEP,
		DevMenuModel.DOWN: stick.y <= -STICK_STEP,
		DevMenuModel.LEFT: stick.x <= -STICK_STEP,
		DevMenuModel.RIGHT: stick.x >= STICK_STEP,
		DevMenuModel.SEED_UP_FAR: float(values.get("right_trigger", 0.0)) >= TRIGGER_STEP,
		DevMenuModel.SEED_DOWN_FAR: float(values.get("left_trigger", 0.0)) >= TRIGGER_STEP,
	}
	for button: String in BUTTON_ACTIONS:
		held[BUTTON_ACTIONS[button]] = bool(buttons.get(button, false))
	return held


## Idle values keeping only the menu button (and its flat-build key).
static func neutral(values: Dictionary) -> Dictionary:
	var idle: Dictionary = ControllerSampler.idle_values()
	var buttons: Dictionary = values.get("buttons", {})
	for button: String in [ResetHold.BUTTON, ResetHold.KEYBOARD_BUTTON]:
		if bool(buttons.get(button, false)):
			idle["buttons"][button] = true
	return idle


## Acts on a result of `DevMenuModel.press`. A corner or control scheme is
## saved and the menu stays open so the change can be seen; a level, restart
## or update closes it.
func apply(result: String) -> void:
	if result == "":
		return
	if result.begins_with(DevMenuModel.CORNER_PREFIX):
		corner_store.choose(result.substr(DevMenuModel.CORNER_PREFIX.length()))
		return
	if result.begins_with(DevMenuModel.CONTROLS_PREFIX):
		_switch_controls(result.substr(DevMenuModel.CONTROLS_PREFIX.length()))
		return
	menu.close()
	if result.begins_with(DevMenuModel.LEVEL_PREFIX):
		var source: String = result.substr(DevMenuModel.LEVEL_PREFIX.length())
		if source == DevMenuModel.RANDOM:
			var picked: int = int(pick_seed.call()) if pick_seed.is_valid() else LevelSwitch.random_seed()
			source = LevelSwitch.SEED_PREFIX + str(picked)
		_start_restart(source)
	elif result == DevMenuModel.RESTART:
		_start_restart(_level_start.source if _level_start != null else "")
	elif result == DevMenuModel.UPDATE and _update != null:
		_update.choose_waiting()


func _toggle() -> void:
	if is_open():
		menu.close()
	else:
		menu.open(PanelCorner.current, _level_start.source if _level_start != null else "",
			scheme.scheme if scheme != null else "")


## Only called while the menu is open, so the ship is on neutral input now.
func _switch_controls(to: String) -> void:
	if scheme == null:
		return
	if scheme.switch_to(to, mapping != null and mapping.left_handed):
		controls_store.save(to)


func _start_restart(source: String) -> void:
	print("%s flies %s" % [LOG_PREFIX, source if source != "" else "the test tunnel"])
	_pending = source
	_fade_from = -1.0  # Started on the next `read`, on its clock.


## Fades out, restarts on the black frame, fades back in.
func _advance_fade(now: float) -> void:
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
		if _level_start != null:
			_level_start.source = str(_pending)
		_pending = null
		_fade_from = now
		if _restart.is_valid():
			_restart.call()
