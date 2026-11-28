class_name AcceptanceFrameHook
extends RefCounted

## Lets a check wait for the next drawn frame (#1480, DEV-6, PRF-7). Judges run synchronously, so a
## check that must measure something the GPU does (a level's first frame, where the headset
## compiles its shaders) starts work before its judge: it builds what it needs in the scene and asks
## for the next drawn frame with a callback. The runner keeps the step open while a callback waits
## and calls it on the frame after the one that drew the work, with whether a frame was really drawn
## and the clock reading when it was. The callback may ask for another frame, so one check can draw
## several loads one after another.
##
## Nothing forces a draw: `RenderingServer.force_draw` inside a frame is unsafe under OpenXR. The
## hook listens to `RenderingServer.frame_post_draw` instead. Where nothing is drawn (the headless
## display, the dummy renderer) the callback comes on the next frame with `drawn` false, so the
## check still measures and can report "skipped" rather than "passed" (decision record 0005).
##
## A step that waits here is still under its time limit (#1444): a frame that never comes fails the
## step like any stuck wait, and `end` puts back what the checks built in the scene.

## What each check's frame work left for its judge, by check name.
var results: Dictionary = {}
## Whether frames are drawn here; false on the headless display or the dummy renderer.
var draws: bool = false
## Microseconds of wall time; tests pass a fake clock.
var clock_usec: Callable = Callable(Time, "get_ticks_usec")

var _waiting: Array[Callable] = []
var _drawn_usec: int = -1
var _cleanups: Array[Callable] = []
var _listening: bool = false


## A hook that listens to the renderer, when this machine draws frames.
static func live() -> AcceptanceFrameHook:
	var hook: AcceptanceFrameHook = AcceptanceFrameHook.new()
	hook.draws = draws_here()
	if hook.draws:
		RenderingServer.frame_post_draw.connect(hook.frame_drawn)
		hook._listening = true
	return hook


## Starts the frame work (`AcceptanceCheckFiles.frame_work`) of each of `step`'s checks that has
## some, in the step's check order, on `hook` or, when that is null, a live one. Returns the hook
## used, or `hook` when no check has frame work.
static func start_work(step: AcceptanceStep, runner: AcceptanceRunner, hook: AcceptanceFrameHook) -> AcceptanceFrameHook:
	var work: Dictionary[String, Callable] = AcceptanceCheckFiles.frame_work()
	for check: String in step.checks:
		if work.has(check):
			if hook == null:
				hook = live()
			work[check].call(step, runner, hook)
	return hook


## False on the headless display and the dummy renderer, where no frame reaches a GPU.
static func draws_here() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_driver_name() != "dummy"


## Calls `callback(drawn: bool, drawn_usec: int)` once the next frame has been drawn.
func next_drawn_frame(callback: Callable) -> void:
	_waiting.append(callback)


## True while a callback waits for its frame; the runner keeps the step open.
func waiting() -> bool:
	return not _waiting.is_empty()


## Called at the end of the step, timed out or not, to take the checks' work out of the scene.
func on_end(cleanup: Callable) -> void:
	_cleanups.append(cleanup)


## The renderer finished a frame. Only a frame drawn after a request counts.
func frame_drawn() -> void:
	if not _waiting.is_empty() and _drawn_usec < 0:
		_drawn_usec = int(clock_usec.call())


## Once per runner frame: calls the waiting callbacks if their frame was drawn, or right away
## where nothing is drawn. A callback's own request waits for a later frame.
func advance() -> void:
	if _waiting.is_empty() or (draws and _drawn_usec < 0):
		return
	var at: int = _drawn_usec if draws else int(clock_usec.call())
	var due: Array[Callable] = _waiting
	_waiting = []
	_drawn_usec = -1
	for callback: Callable in due:
		callback.call(draws, at)


## Once per runner frame: `advance`, then whether a callback still waits.
func still_waiting() -> bool:
	advance()
	return waiting()


## Stops listening, drops waiting callbacks and runs the cleanups, once.
func end() -> void:
	if _listening:
		RenderingServer.frame_post_draw.disconnect(frame_drawn)
		_listening = false
	_waiting.clear()
	var cleanups: Array[Callable] = _cleanups
	_cleanups = []
	for cleanup: Callable in cleanups:
		cleanup.call()
