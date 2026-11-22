class_name DestroyedWiring
extends RefCounted

## Joins the session's local ship to what the pilot sees and feels when it is
## lost (#616, RUN-7, CMB-2, PLT-6): the fade and `SHIP DESTROYED` screen with
## the restart prompt, and the low-hull and shield-break pulses before that.
##
## It sits beside `main.gd`, like `CombatWiring`, because it reads the `net/`
## session, which `xr/` may not depend on. It reads copies of the ship only;
## a restart is answered to `main.gd`, which loads the level again (MP-2).
##
## It also runs the escape's end screen (`EscapeEndWiring`, #751) on the same
## restart button, so `main.gd` restarts after either end without growing.

## The A button, on the right Touch controller in either hand mode.
const RESTART_BUTTON: String = "right_button_lower"
## The flat build's restart key, read here so `main.gd` stays short, and the
## button name that counts as it, so tests can press it without a keyboard.
const KEYBOARD_KEY: Key = KEY_ENTER
const KEYBOARD_BUTTON: String = "restart_key"

var sequence: DestroyedSequence = DestroyedSequence.load_file()
var haptics: DefenceHaptics = DefenceHaptics.load_shipped()
## Under the rig origin once `attach` has run, null before.
var screen: DestroyedScreen = null
var escape: EscapeEndWiring = EscapeEndWiring.new()
## Hides the status panel and the map while an end screen is up (#1228).
var cover: EndScreenCover = EndScreenCover.new()
## Whether the fade went down on some frame while an end screen was up, since
## the last `reset`; the acceptance check reads it (#1228, CMF-8).
var fade_dropped: bool = false

var _last_alpha: float = 0.0

var _restart_held: bool = false


## Hangs the screen under `rig` and hands the warnings the controllers.
## Calling it again adds nothing.
func attach(rig: Node3D, left: XRController3D, right: XRController3D) -> void:
	haptics.left_controller = left
	haptics.right_controller = right
	escape.attach(rig)
	if rig != null:
		cover.attach(rig)
	if screen != null or rig == null:
		return
	screen = DestroyedScreen.new()
	rig.add_child(screen)


## Reads this frame's buttons: A, or Enter in the flat build, restarts.
func read_buttons(buttons: Dictionary) -> void:
	_restart_held = bool(buttons.get(RESTART_BUTTON, false)) or bool(buttons.get(KEYBOARD_BUTTON, false)) \
		or Input.is_physical_key_pressed(KEYBOARD_KEY)


## Once per frame after the ticks. Runs the warnings and the sequence from a
## copy of the local ship, holding the sequence still while the session is
## paused, and puts the screen at the head point; then the escape's end
## screen. Returns true on the frame the level should restart.
func update(session: LocalSession, delta_seconds: float, recentre: HeadRecentre,
		xr_running: bool) -> bool:
	var ship: ShipState = session.current_ship()
	var shield: float = ship.shield / ship.max_shield if ship.max_shield > 0.0 else 0.0
	var hull: float = ship.hull / ship.max_hull if ship.max_hull > 0.0 else 0.0
	haptics.update(shield, hull, xr_running)
	var due: bool = sequence.update(ship.hull, 0.0 if session.paused else delta_seconds, _restart_held)
	if due:
		haptics.reset()
	if screen != null:
		screen.transform = RigViews.head_point(recentre)
		screen.show_state(sequence.line_shown(), sequence.prompt_shown(), xr_running)
	var escape_due: bool = escape.update(session, delta_seconds, _restart_held, RigViews.head_point(recentre),
		xr_running)
	_watch_fade()
	return due or escape_due


## True from the frame either end screen starts its fade until the press that
## ends it, and while the shaft panel holds the view dark after an escape.
func end_screen_up() -> bool:
	return sequence.line_shown() or escape.sequence.line_shown() or escape.choice.is_open()


## Hides the panel and map while an end screen is up and notes a fade that went down.
func _watch_fade() -> void:
	var up: bool = end_screen_up()
	cover.update(up)
	var alpha: float = fade_alpha()
	if up and alpha < _last_alpha:
		fade_dropped = true
	_last_alpha = alpha if up else 0.0


## The fade's opacity this frame from either end screen, 0..1.
func fade_alpha() -> float:
	return maxf(sequence.fade_alpha(), escape.fade_alpha())


## Back to flying with neither end screen up and no fade (#917): what a
## restart leaves once its fade-in is over, reached at once. The acceptance
## runner calls it before each step, because a step swaps the session without
## the restart press that would otherwise take a screen down.
func reset() -> void:
	sequence = DestroyedSequence.new({"fade_seconds": sequence.fade_seconds, "hold_seconds": sequence.hold_seconds})
	haptics.reset()  # As on the restart frame, so the next low hull warns again.
	if screen != null:
		screen.visible = false
	escape.reset()
	cover.restore()
	fade_dropped = false
	_last_alpha = 0.0
