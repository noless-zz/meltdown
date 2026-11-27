extends RefCounted

## The `glass_clear` check (#1459, GFX-2, CMF-8, PRF-1, ARC-3, DEV-6, decision
## record 0005), lane-c's file under `acceptance/checks/`. In
## `suites/m6/look.json` it has its own step:
##
##     {"id": "glass_clear", "replay": "res://acceptance/replays/frame_budget_flight.replay",
##      "checks": ["final_hash", "glass_clear", "no_script_errors"], "expected_hash": ...}
##
## The owner found the mine dark and brown through the canopy. After the replay,
## for each of the four presets the scene's own `set_comfort_preset` builds that
## cockpit, and the same frame is drawn twice: with the glass shown and with it
## hidden. Both pictures are saved. The area seen through the canopy (the
## window shrunk by `WINDOW_FRACTION`, so the frame's edge stays out) is judged
## on its mean luminance and its contrast (luminance standard deviation). With
## the glass on, both must stay within `MAX_CHANGE` of glass off. The step
## message prints both numbers for every preset.
##
## Hiding the glass only hides a view node, and the preset in force before is
## restored, so the simulation never notices (ARC-3, MP-2; the step's
## `final_hash`). Off a display that draws, the check is skipped.

const CHECK: String = "glass_clear"
## Glass on may differ from glass off by at most this fraction (#1459).
const MAX_CHANGE: float = 0.1
## A relative change is measured against at least this, so a near-black
## picture cannot fail on a difference no one could see.
const MIN_BASE: float = 0.02
## The part of the window judged, as a fraction of its half-angles: the
## middle of the view, where the reflection near the edge is too faint to count.
const WINDOW_FRACTION: float = 0.6
## The judged area is scaled to at most this width first; enough for a mean.
const SAMPLE_WIDTH: int = 160
const PRESETS: Array[int] = [1, 2, 3, 4]


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	if comfort == null or comfort.cockpit_frame == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no cockpit frame"]
	var camera: Camera3D = main.get_viewport().get_camera_3d() if main.is_inside_tree() else null
	var before: int = comfort.number
	var folder: String = runner.screenshots.dir.path_join(CHECK)
	var lines: PackedStringArray = []
	var faults: PackedStringArray = []
	for number: int in PRESETS:
		main.call("set_comfort_preset", number)
		var shot_name: String = "%s_preset%d" % [step.id, number]
		var pair: Dictionary = measure_frame(comfort.cockpit_frame, runner.screenshots.grab, camera, folder, shot_name)
		if pair.has("skipped"):
			main.call("set_comfort_preset", before)
			return [AcceptanceReport.RESULT_FAIL if step.required else AcceptanceReport.RESULT_SKIPPED,
				"nothing drawn to judge: %s" % pair["skipped"]]
		measurements["preset_%d" % number] = pair
		var line: String = "preset %d %s" % [number, describe(pair)]
		lines.append(line)
		if not passes(pair):
			faults.append(line)
	main.call("set_comfort_preset", before)
	var limits: String = "glass on within %d%% of glass off" % roundi(MAX_CHANGE * 100.0)
	if not faults.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the glass changes the view: %s (%s)" % ["; ".join(faults), limits]]
	return [AcceptanceReport.RESULT_PASS, "%s (%s)" % ["; ".join(lines), limits]]


## Draws `frame`'s view with its glass shown and hidden, saves both pictures
## under `folder` as `<shot_name>_glass_on.png` and `_glass_off.png`, and returns the
## numbers of both: `mean_on`, `mean_off`, `contrast_on`, `contrast_off`,
## `mean_change`, `contrast_change`, `shot_on`, `shot_off`. Returns `skipped`
## with the reason when `grab` gives no picture. The glass is left as found.
static func measure_frame(frame: CockpitFrame, grab: Callable, camera: Camera3D, folder: String,
		shot_name: String) -> Dictionary:
	var glass: MultiMeshInstance3D = frame.part("Glass")
	var was_visible: bool = glass != null and glass.visible
	var on: Variant = _draw_and_grab(grab)
	if glass != null:
		glass.visible = false
	var off: Variant = _draw_and_grab(grab)
	if glass != null:
		glass.visible = was_visible
	if not on is Image or not off is Image:
		return {"skipped": str(off) if not off is Image else str(on)}
	var area: Rect2i = canopy_rect(frame, camera, (on as Image).get_size())
	var lit_on: Dictionary = stats(on as Image, area)
	var lit_off: Dictionary = stats(off as Image, area)
	var pair: Dictionary = {"glass_built": glass != null, "area": [area.position.x, area.position.y,
		area.size.x, area.size.y], "mean_on": lit_on["mean"], "mean_off": lit_off["mean"],
		"contrast_on": lit_on["contrast"], "contrast_off": lit_off["contrast"],
		"mean_change": change(float(lit_on["mean"]), float(lit_off["mean"])),
		"contrast_change": change(float(lit_on["contrast"]), float(lit_off["contrast"]))}
	pair["shot_on"] = _save(on as Image, folder, "%s_glass_on.png" % shot_name)
	pair["shot_off"] = _save(off as Image, folder, "%s_glass_off.png" % shot_name)
	return pair


## True when both numbers of `pair` stay within `MAX_CHANGE`.
static func passes(pair: Dictionary) -> bool:
	return absf(float(pair["mean_change"])) <= MAX_CHANGE and absf(float(pair["contrast_change"])) <= MAX_CHANGE


## "mean 0.210 on, 0.205 off (+2.4%), contrast ..." for the step message.
static func describe(pair: Dictionary) -> String:
	return "mean %.3f on, %.3f off (%+.1f%%), contrast %.3f on, %.3f off (%+.1f%%)" % [
		float(pair["mean_on"]), float(pair["mean_off"]), float(pair["mean_change"]) * 100.0,
		float(pair["contrast_on"]), float(pair["contrast_off"]), float(pair["contrast_change"]) * 100.0]


## How far `on` is from `off`, as a signed fraction of `off` (at least `MIN_BASE`).
static func change(on: float, off: float) -> float:
	return snappedf((on - off) / maxf(off, MIN_BASE), 0.0001)


## Mean luminance and its standard deviation (`contrast`), 0..1, of `area` of
## `image`. Works on a copy.
static func stats(image: Image, area: Rect2i) -> Dictionary:
	var clipped: Rect2i = area.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		clipped = Rect2i(Vector2i.ZERO, image.get_size())
	var copy: Image = image.get_region(clipped)
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGB8)
	if copy.get_width() > SAMPLE_WIDTH:
		copy.resize(SAMPLE_WIDTH, maxi(1, copy.get_height() * SAMPLE_WIDTH / copy.get_width()),
			Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	var squares: float = 0.0
	for y: int in copy.get_height():
		for x: int in copy.get_width():
			var colour: Color = copy.get_pixel(x, y)
			var luminance: float = 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
			total += luminance
			squares += luminance * luminance
	var count: float = float(copy.get_width() * copy.get_height())
	var mean: float = total / count
	return {"mean": snappedf(mean, 0.0001), "contrast": snappedf(sqrt(maxf(squares / count - mean * mean, 0.0)), 0.0001)}


## The part of a picture of `size` seen through `frame`'s window: its corners,
## `WINDOW_FRACTION` of the half-angles out, projected by `camera`. Without a
## camera, or with a corner behind it, the middle half of the picture.
static func canopy_rect(frame: CockpitFrame, camera: Camera3D, size: Vector2i) -> Rect2i:
	var middle: Rect2i = Rect2i(size / 4, size / 2)
	if camera == null or frame == null or not frame.is_inside_tree() or not camera.is_inside_tree():
		return middle
	var yaw: float = deg_to_rad(frame.spec.window_half_angle_h_deg * WINDOW_FRACTION)
	var pitch: float = deg_to_rad(frame.spec.window_half_angle_v_deg * WINDOW_FRACTION)
	var view: Vector2 = camera.get_viewport().get_visible_rect().size
	var scale: Vector2 = Vector2(size) / view if view.x > 0.0 and view.y > 0.0 else Vector2.ONE
	var corners: Array[Vector2] = []
	for side: float in [-1.0, 1.0]:
		for up: float in [-1.0, 1.0]:
			var a: float = yaw * side
			var b: float = pitch * up
			var local: Vector3 = Vector3(sin(a) * cos(b), sin(b), -cos(a) * cos(b)) * frame.spec.frame_distance_m
			var point: Vector3 = frame.global_transform * local
			if camera.is_position_behind(point):
				return middle
			corners.append(camera.unproject_position(point) * scale)
	var low: Vector2 = corners[0]
	var high: Vector2 = corners[0]
	for corner: Vector2 in corners:
		low = low.min(corner)
		high = high.max(corner)
	var found: Rect2i = Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil())).intersection(
		Rect2i(Vector2i.ZERO, size))
	return found if found.size.x > 0 and found.size.y > 0 else middle


static func _draw_and_grab(grab: Callable) -> Variant:
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(true, 0.0)
	return grab.call() if grab.is_valid() else "nothing to take it with"


static func _save(image: Image, folder: String, file_name: String) -> String:
	if folder == "":
		return "not saved"
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(file_name)
	var error: Error = image.save_png(path)
	return path if error == OK else "not saved: cannot write %s: %s" % [path, error_string(error)]
