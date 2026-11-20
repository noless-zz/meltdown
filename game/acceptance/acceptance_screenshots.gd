class_name AcceptanceScreenshots
extends RefCounted

## Screenshots at named ticks of a step's replay (#718, DEV-6, GFX-2), so a
## failed device run shows what the headset saw. A step names
## `"screenshot_at_ticks": [..]` and/or `"screenshot_at_end": true`; at each
## tick the main viewport is saved as `<dir>/<suite>/<step>_<tick>.png`.
##
## Only the viewport's image is read: nothing here touches the session, so the
## replay ends on the same hash with or without screenshots (ARC-2). A
## screenshot that cannot be taken is listed as skipped with the reason and
## never fails its step.

const DIR: String = "user://acceptance"
const KEY_TICKS: String = "screenshot_at_ticks"
const KEY_END: String = "screenshot_at_end"
const STEP_KEYS: Array[String] = [KEY_TICKS, KEY_END]
## The cap when the replay cannot be read to find its end: an hour at 60 Hz.
const MAX_TICK: int = 216000
## What the image shows, said in the report. With XR on, the main viewport
## holds both eyes; Godot's image of it is the left eye's layer, or whatever
## the runtime hands back, which the first device report will show.
const VIEW_FLAT: String = "main viewport"
const VIEW_XR: String = "main viewport with XR on (the left eye's layer, or what Godot gives for it)"

## Returns the Image to save, or a String saying why there is none. Tests
## pass their own; `live()` reads the main viewport.
var grab: Callable = Callable()
## Where the suite's folder of screenshots goes; tests use their own.
var dir: String = DIR

var _suite: String = ""
var _step_id: String = ""
var _ticks: Array[int] = []
var _at_end: bool = false
var _end_tick: int = -1
var _entries: Array[Dictionary] = []


static func live() -> AcceptanceScreenshots:
	var shots: AcceptanceScreenshots = AcceptanceScreenshots.new()
	shots.grab = grab_main_viewport
	return shots


## The main viewport's last drawn frame, or why there is none.
static func grab_main_viewport() -> Variant:
	if DisplayServer.get_name() == "headless":
		return "headless display: nothing is drawn"
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return "no main viewport"
	var texture: ViewportTexture = tree.root.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return "the renderer gave no image (%s)" % RenderingServer.get_current_rendering_method()
	return image


static func view_name() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return VIEW_XR if tree != null and tree.root != null and tree.root.use_xr else VIEW_FLAT


## Reads the step's screenshot keys. Ticks count into the replay: 0 is before
## its first tick, its length is its end. Returns the problem, naming the field.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if data.has(KEY_END):
		if typeof(data[KEY_END]) != TYPE_BOOL:
			return "%s.%s: must be true or false" % [field, KEY_END]
		step.screenshot_at_end = data[KEY_END]
	if data.has(KEY_TICKS):
		var raw: Variant = data[KEY_TICKS]
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			return "%s.%s: must be a list of at least one tick" % [field, KEY_TICKS]
		var last: int = replay_length(step.replay_path)
		var values: Array = raw
		for index: int in values.size():
			var name: String = "%s.%s[%d]" % [field, KEY_TICKS, index]
			var value: Variant = values[index]
			# A bool must not pass as 0 or 1.
			if typeof(value) != TYPE_INT and (typeof(value) != TYPE_FLOAT or not is_finite(value) \
					or float(value) != floorf(value)):
				return "%s: must be a whole number of ticks" % name
			if float(value) < 0.0:
				return "%s: %d is negative" % [name, int(value)]
			if float(value) > float(last):
				return "%s: %d is past the end of the replay (%d ticks)" % [name, int(value), last]
			if step.screenshot_ticks.has(int(value)):
				return "%s: %d is listed twice" % [name, int(value)]
			step.screenshot_ticks.append(int(value))
	if (step.screenshot_at_end or not step.screenshot_ticks.is_empty()) and step.replay_path == "":
		return "%s.replay: needed by screenshots, which are taken at ticks of the replay" % field
	return ""


## The replay's length in ticks, or MAX_TICK when it cannot be read here (a
## missing replay fails its step when it flies).
static func replay_length(path: String) -> int:
	if path == "" or not FileAccess.file_exists(path):
		return MAX_TICK
	var replay: Replay = Replay.load_file(path)
	return replay.frames.size() if replay.error == "" else MAX_TICK


## Starts a step's screenshots; nothing is taken until `take`.
func begin(suite_name: String, step: AcceptanceStep) -> void:
	_suite = suite_name
	_step_id = step.id
	_ticks = step.screenshot_ticks.duplicate()
	_at_end = step.screenshot_at_end
	_end_tick = -1
	_entries.clear()


## Called with the session's tick before the runner flies it, and with the
## replay's length once it has ended. The last drawn frame then shows `tick`.
func take(tick: int, end_tick: int) -> void:
	_end_tick = end_tick
	var wanted: bool = _ticks.has(tick) or (_at_end and tick == end_tick)
	if not wanted or _has_entry(tick):
		return
	var entry: Dictionary = {"tick": tick, "view": view_name()}
	var got: Variant = grab.call() if grab.is_valid() else "nothing to take it with"
	if got is Image:
		var folder: String = dir.path_join(_suite)
		var path: String = folder.path_join("%s_%d.png" % [_step_id, tick])
		DirAccess.make_dir_recursive_absolute(folder)
		var error: Error = (got as Image).save_png(path)
		if error == OK:
			entry["path"] = path
		else:
			entry["skipped"] = "cannot write %s: %s" % [path, error_string(error)]
	else:
		entry["skipped"] = str(got)
	_entries.append(entry)


## The step's screenshots by tick, each with a path or the reason it was
## skipped, a tick the replay never reached included. Clears them.
func finish_step() -> Array[Dictionary]:
	for tick: int in _ticks:
		if not _has_entry(tick):
			_entries.append({"tick": tick, "skipped": "the replay did not reach tick %d" % tick})
	if _at_end and (_end_tick < 0 or not _has_entry(_end_tick)):
		_entries.append({"tick": _end_tick, "skipped": "the replay did not fly to its end"})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tick"]) < int(b["tick"]))
	var done: Array[Dictionary] = _entries.duplicate(true)
	_entries.clear()
	_ticks.clear()
	_at_end = false
	return done


func _has_entry(tick: int) -> bool:
	for entry: Dictionary in _entries:
		if int(entry["tick"]) == tick:
			return true
	return false
