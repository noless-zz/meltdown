class_name DevMenuReturn
extends DevMenuEntry

## The menu's "Return to base" row (#1246, RUN-1, CRW-2, CMF-8): shown only
## while a run's level flies (`RunAbandon.flying_run`). The confirm step lives
## in `DevMenuModel`: the first press arms the row, which then reads
## `confirm_return_text`, and only a second press returns `RETURN`. Choosing it
## closes the menu and fades the view out on the steady clock, as the Restart
## entry does; on the black frame `RunAbandon.abandon` ends the run as a lost
## ship and opens the hub, which keeps the view dark until its launch.

const FADE_SECONDS: float = DevMenuRestart.FADE_SECONDS
const LOG_PREFIX: String = DevMenuRestart.LOG_PREFIX

## The fade's opacity, 0 (clear) to 1 (black), for the fade quad.
var alpha: float = 0.0
## Set by `wire`; any of them null in tests without a scene.
var level_start: LevelStart = null
var hub: HubWiring = null
var destroyed: DestroyedWiring = null
var restart: Callable = Callable()

var _pending: bool = false
## When the fade began on the steady clock; < 0 before its first frame.
var _fade_from: float = -1.0


func _init() -> void:
	super([DevMenuSpec.KIND_RETURN], [DevMenuModel.RETURN], true)


## Called by `DevMenuWiring.attach` with what it was given. The hub is the
## object of `hub_open`, which is `HubWiring.is_open` in the game, so `main.gd`
## hands nothing new; another callable (tests) leaves no hub.
func wire(p_level_start: LevelStart, p_restart: Callable, p_destroyed: DestroyedWiring,
		hub_open: Callable) -> void:
	level_start = p_level_start
	restart = p_restart
	destroyed = p_destroyed
	hub = hub_open.get_object() as HubWiring if hub_open.is_valid() else null


## Before the menu opens: the row shows only while a run's level flies.
func show_on(model: DevMenuModel) -> void:
	model.set_run(RunAbandon.flying_run(level_start))


func choose(_result: String) -> void:
	if not RunAbandon.flying_run(level_start):
		return
	print("%s abandons the run" % LOG_PREFIX)
	_pending = true
	_fade_from = -1.0  # Started on the next `advance`, on its clock.


## Whether a return waits for the view to go black.
func pending() -> bool:
	return _pending


## Once a frame: fades out and abandons on the black frame. The hub then
## holds the view dark, so this fade ends at once.
func advance(now: float) -> void:
	if not _pending:
		alpha = 0.0
		return
	if _fade_from < 0.0:
		_fade_from = now
	alpha = clampf((now - _fade_from) / FADE_SECONDS, 0.0, 1.0)
	if alpha < 1.0:
		return
	_pending = false
	_fade_from = -1.0
	if not RunAbandon.abandon(level_start, hub, destroyed, restart):
		print("%s: no run to abandon any more" % LOG_PREFIX)
	alpha = 0.0
