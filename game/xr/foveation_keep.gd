class_name FoveationKeep
extends RefCounted

## Keep-or-revert for a foveation setting chosen in the dev menu (#1523, part 4
## of #734; CMF-8, PRF-1, GFX-1, DEV-6). The owner's words: a setting that
## leaves the picture stuck must come back by itself unless he confirms the new
## one, and the confirm must work without reading the screen, since the screen
## is what breaks.
##
## A change is applied at once through `FoveationSwitch.choose`, as before, and
## starts a timer of `keep_seconds`. Holding A for `hold_seconds` keeps it.
## The press of A that chose the setting does not count: A must be let go and
## held again, so a confirm is always a deliberate second act. When the timer
## ends, the menu closes or focus is lost before the confirm, the setting from
## before the change comes back through the same `choose` path, with a
## `revert` log line. A second change while waiting keeps that earlier setting
## as the one to return to, and restarts the timer.
##
## Each step sends a cue name (`FoveationKeepSpec.CUE_*`) to `cue_hook`, which
## `FoveationKeepCue` turns into a tone at the head and a pulse on both hands.
## The clock is the caller's: `update` takes the time, so tests use a fake one.
## View side only: nothing here reaches `core/` or is saved (ARC-3).

var switch: FoveationSwitch
var spec: FoveationKeepSpec
## Every cue sent, oldest first, for tests.
var cues: Array[String] = []
## Called with the cue name; unset, cues are only recorded.
var cue_hook: Callable = Callable()
## How many reverts have happened, so the menu can show the setting again.
var reverts: int = 0

var _waiting: bool = false
var _previous: Vector2i = Vector2i.ZERO
var _chosen: Vector2i = Vector2i.ZERO
## When the timer ends; negative until the first `update` after a change.
var _deadline: float = -1.0
## When the current hold of A began; negative when A is not counted as held.
var _hold_from: float = -1.0
## True from a change until A is next seen released.
var _needs_release: bool = false


func _init(p_switch: FoveationSwitch, p_spec: FoveationKeepSpec = FoveationKeepSpec.load_file()) -> void:
	switch = p_switch
	spec = p_spec
	if spec.error != "":
		push_warning("Meltdown: foveation keep file rejected (%s); using the built-in values" % spec.error)


## True while a new setting waits for its confirm.
func is_waiting() -> bool:
	return _waiting


## The setting a revert would return to.
func previous() -> Vector2i:
	return _previous


## The menu's choice of `level` and `dynamic`: applied at once and, when it
## differs from the setting in use, held until confirmed.
func choose(level: int, dynamic: bool) -> void:
	var setting: Vector2i = Vector2i(clampi(level, 0, FoveationSwitch.MAX_LEVEL), int(dynamic))
	if _waiting and setting == _chosen:
		return  # A on the row already chosen: the start of a keep hold, not a change.
	if not _waiting:
		_previous = switch.in_use()
	switch.choose(setting.x, dynamic)
	if setting == _previous:
		_waiting = false  # Back where it was: nothing left to keep.
		return
	_chosen = setting
	_waiting = true
	_deadline = -1.0
	_hold_from = -1.0
	_needs_release = true
	_cue(FoveationKeepSpec.CUE_START)


## One frame at `now` seconds: `confirm_held` is A, `menu_open` whether the
## dev menu shows. Keeps after a long enough hold; reverts at the deadline or
## once the menu has closed.
func update(confirm_held: bool, menu_open: bool, now: float) -> void:
	if not _waiting:
		return
	if not menu_open:
		_revert()
		return
	if _deadline < 0.0:
		_deadline = now + spec.keep_seconds
	if not confirm_held:
		_needs_release = false
		_hold_from = -1.0
	elif not _needs_release:
		if _hold_from < 0.0:
			_hold_from = now
		if now - _hold_from >= spec.hold_seconds:
			_waiting = false
			_cue(FoveationKeepSpec.CUE_KEPT)
			return
	if now >= _deadline:
		_revert()


## Focus lost or anything else that ends the chance to confirm: reverts now.
func cancel() -> void:
	if _waiting:
		_revert()


func _revert() -> void:
	_waiting = false
	reverts += 1
	switch.choose(_previous.x, _previous.y != 0, FoveationSwitch.SOURCE_REVERT)
	_cue(FoveationKeepSpec.CUE_REVERTED)


func _cue(cue: String) -> void:
	cues.append(cue)
	if cue_hook.is_valid():
		cue_hook.call(cue)
