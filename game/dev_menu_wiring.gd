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
## passes through, so a hold still resets. The frame it closes is idle too,
## and a stick, trigger or button still held then stays away from the ship
## until released once (`DevMenuRelease`, #1206). The status panel hides while
## the menu is open, so the menu never covers it. Nothing here writes simulation
## state: a level or restart goes through `main.gd`'s `restart_level`, a new
## session from the start, behind a fade (MP-2, ARC-3, CMF-8). In solo play
## the open menu also pauses the session (`DevMenuPause`, #1245).
##
## The tap does nothing during the first-launch flight test, while the
## destroyed or escape screen is up or while the hub is open, and closes a
## menu left open then; the hub also drops a level the menu was fading to, so
## nothing flies hidden behind it (#1170, decision record 0009). The
## break prompt (#716) still takes a tap first, through `UpdateWiring.tap_taker`.
## A newer build that waits is an entry in the menu, and choosing it does
## what the tap did before (`UpdateWiring.choose_waiting`).
##
## Each entry's choice goes to its helper (`DevMenuEntry`, #892): the Panel
## corner to `DevMenuCorner`, Controls, Hands and Pitch to `DevMenuControls`,
## Comfort to `DevMenuComfort`, Break reminder to `DevMenuBreak`, Refresh to
## `DevMenuRefresh`, Swivel chair to `DevMenuSwivel`, Foveation to
## `DevMenuFoveation` (#871), the update to
## `DevMenuUpdate`, and Level, Restart level and Flight test to
## `DevMenuRestart`, which owns the fade. A new entry adds one helper and one
## line in `_init`. It sits beside `main.gd` because it restarts the `net/`
## session and reads the flight test and the end screens.

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
const FADE_SECONDS: float = DevMenuRestart.FADE_SECONDS
const LOG_PREFIX: String = DevMenuRestart.LOG_PREFIX

## Under the rig once `attach` has run.
var menu: DevMenu = null
var tap: MenuTap = MenuTap.new()
## What the menu was using when it closed, kept from the ship until released (#1206).
var release: DevMenuRelease = DevMenuRelease.new()
## One helper per entry kind, in the order `dev_menu.json` lists them.
var entries: Array[DevMenuEntry] = []
## The comfort wiring the Comfort, Refresh, Swivel chair and Auto-level entries read; null in tests without one.
var comfort: ComfortWiring = null
## The break prompt the Break reminder entry shows and switches; null in tests without one.
var break_prompt: BreakPromptWiring = null
## The Refresh entry's 120 Hz option; null in tests without a refresh rate.
var refresh: DevMenuRefresh = null
## The Swivel chair entry; applies the saved choice to `comfort` when made.
var swivel: DevMenuSwivel = null
## The read-only Info section under the menu's entries, once `attach` has run.
var info: DevMenuInfo = null

## The stores and settings below live in the helpers; these names stay for
## `main.gd` and the tests.
var corner_store: PanelCorner:
	get: return _corner.store
	set(value): _corner.store = value
var controls_store: ControlsChoice:
	get: return _controls.store
	set(value): _controls.store = value
var scheme: ControlSchemeSwitch:
	get: return _controls.scheme
var mapping: ThumbstickMapping:
	get: return _controls.mapping
var pick_seed: Callable:
	get: return _restarts.pick_seed
	set(value): _restarts.pick_seed = value
var alpha: float:
	get: return _restarts.alpha

var _corner: DevMenuCorner = DevMenuCorner.new()
var _controls: DevMenuControls = null
var _comfort_entry: DevMenuComfort = null
var _break_entry: DevMenuBreak = null
var _update_entry: DevMenuUpdate = DevMenuUpdate.new()
var _restarts: DevMenuRestart = DevMenuRestart.new()
var _update: UpdateWiring = null
var _level_start: LevelStart = null
var _flight_test: FlightTestWiring = null
var _destroyed: DestroyedWiring = null
## True while the hub is open (`HubWiring.is_open`); unset, there is no hub.
var _hub_open: Callable = Callable()
## The session the open menu pauses (`DevMenuPause`); unset, nothing pauses.
var _session_of: Callable = Callable()


func _init(p_scheme: ControlSchemeSwitch = null, p_mapping: ThumbstickMapping = null,
		p_comfort: ComfortWiring = null, p_break_prompt: BreakPromptWiring = null,
		p_rate: RefreshRate = null, p_foveation: FoveationSwitch = null) -> void:
	refresh = DevMenuRefresh.new(p_rate, p_comfort) if p_rate != null else null
	comfort = p_comfort
	break_prompt = p_break_prompt
	_controls = DevMenuControls.new(p_scheme, p_mapping)
	_comfort_entry = DevMenuComfort.new(p_comfort)
	_break_entry = DevMenuBreak.new(p_break_prompt)
	swivel = DevMenuSwivel.new(p_comfort)
	swivel.start()
	var no_refresh: DevMenuEntry = DevMenuEntry.new([DevMenuSpec.KIND_REFRESH], [DevMenuModel.REFRESH_PREFIX])
	var close: DevMenuEntry = DevMenuEntry.new([DevMenuSpec.KIND_CLOSE], [DevMenuModel.CLOSE], true)
	entries = [_update_entry, _corner, _comfort_entry, _break_entry,
		refresh if refresh != null else no_refresh, swivel, DevMenuAutoLevel.started(p_comfort), _controls,
		DevMenuFoveation.new(p_foveation), _restarts, close]


## Hangs `p_menu` under `rig` (none in some tests). `restart` flies
## `level_start.source` again from its start; the flight test and the end
## screens say when the tap is ignored, and so does `hub_open` (#1170).
## `session_of` returns the session flying now, which the open menu pauses.
## Calling it again adds nothing.
func attach(rig: Node3D, update: UpdateWiring, level_start: LevelStart, restart: Callable,
		flight_test: FlightTestWiring, destroyed: DestroyedWiring, p_menu: DevMenu = null,
		hub_open: Callable = Callable(), session_of: Callable = Callable()) -> void:
	if menu != null:
		return
	_hub_open = hub_open
	_session_of = session_of
	_update = update
	_level_start = level_start
	_flight_test = flight_test
	_destroyed = destroyed
	_update_entry.update = update
	_restarts.level_start = level_start
	_restarts.restart = restart
	_restarts.flight_test = flight_test
	_restarts.rig = rig
	menu = p_menu if p_menu != null else DevMenu.new()
	info = DevMenuInfo.new(menu.model.spec.info_title_text)  # The panel's development lines (#1207).
	info.source = rig
	menu.add_child(info)
	if rig != null:
		rig.add_child(menu)


func is_open() -> bool:
	return menu != null and menu.visible


## Whether the tap is ignored now: the flight test runs, the hub is open or
## an end screen is up.
func blocked() -> bool:
	if _flight_test != null and _flight_test.running():
		return true
	if hub_is_open():
		return true
	if _destroyed == null:
		return false
	return _destroyed.fade_alpha() > 0.0 or _destroyed.sequence.line_shown() \
		or _destroyed.escape.sequence.line_shown()


## True while the hub is open. The hub has its own controls and its launch
## leaves it, so a tap over it is ignored rather than closing it (#1170).
func hub_is_open() -> bool:
	return _hub_open.is_valid() and bool(_hub_open.call())


## The helper serving `kind` in `dev_menu.json`, or null.
func entry_for(kind: String) -> DevMenuEntry:
	for entry: DevMenuEntry in entries:
		if entry.kinds.has(kind):
			return entry
	return null


## Once per frame, first, with the sampled `values`. Returns the values the
## rest of the frame should read: `values` while the menu is closed, idle
## values but for the menu button while it is open.
func read(values: Dictionary, now: float = MenuTap.steady_seconds()) -> Dictionary:
	if _update != null:
		_update.step()
	if hub_is_open():
		_restarts.cancel()  # A level picked before the hub opened must not fly behind it.
	_restarts.advance(now)
	var tapped: bool = tap.feed(ResetHold.is_held(values), now)
	if tapped and _update != null and _update.tap_taker.is_valid() and bool(_update.tap_taker.call()):
		tapped = false
	if menu == null:
		return values
	menu.set_update(_update.waiting_version() if _update != null else "",
		_update != null and _update.download_busy())
	var was_open: bool = is_open()
	if blocked():
		menu.close()
	elif tapped:
		_toggle()
	if is_open():
		for entry: DevMenuEntry in entries:
			entry.follow(menu.model)  # Refresh and Swivel chair follow a Comfort choice.
		apply(menu.update(actions(values)))
	_show_panel(not is_open())
	if _session_of.is_valid():
		DevMenuPause.hold(_session_of.call() as LocalSession, is_open())
	if not is_open() and not was_open:
		return release.filter(values)
	if not is_open():
		release.hold(values)  # A still down from Close or a level is not the afterburner (#1206).
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


## Acts on a result of `DevMenuModel.press` through the helper that takes it.
## A setting is applied and the menu stays open so the change can be seen; a
## level, restart, update or anything unknown closes it.
func apply(result: String) -> void:
	if result == "":
		return
	for entry: DevMenuEntry in entries:
		if entry.takes(result):
			if entry.closes:
				menu.close()
			entry.choose(result)
			return
	menu.close()


func _toggle() -> void:
	if is_open():
		menu.close()
		return
	for entry: DevMenuEntry in entries:
		entry.show_on(menu.model)
	menu.place(head())  # In front of the eyes as they are now, then world-locked (#1206).
	menu.open(PanelCorner.current, _level_start.source if _level_start != null else "",
		_controls.scheme_shown(), _controls.left_handed(), _controls.invert_pitch(),
		_comfort_shown(), _break_shown(), _comfort_entry.custom_base())


## The head's pose in the rig's space, which is the menu's parent space: the
## rig's camera, or the default eye point without a rig or camera.
func head() -> Transform3D:
	var rig: Node3D = _restarts.rig
	var camera: Node3D = rig.get_node_or_null("Camera") as Node3D if rig != null else null
	return camera.transform if camera != null else DevMenu.DEFAULT_HEAD


## Shows or hides the rig's status panel. It hides while the menu is open:
## the corner panels sit within a few degrees of the view centre, where the
## menu opens, and the menu would cover them (#1206). View only (ARC-3).
func _show_panel(shown: bool) -> void:
	var rig: Node3D = _restarts.rig
	var panel: Node3D = rig.get_node_or_null(StatusPanel.NODE_NAME) as Node3D if rig != null else null
	if panel != null and panel.visible != shown:
		panel.visible = shown


## Whether the Break reminder entry opens on On: the reminder's own state.
func _break_shown() -> bool:
	return _break_entry.shown()


## The preset the Comfort entry opens on: the active one, the custom mode included.
func _comfort_shown() -> int:
	return _comfort_entry.shown()
