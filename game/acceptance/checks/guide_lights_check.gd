extends RefCounted

## The guide light checks (#1463, GFX-2, GFX-4, GFX-5, PRF-2, PRF-4, DEV-6,
## decision record 0005), lane-a's file under `acceptance/checks/`. In
## `suites/m6/look.json` the `guide_lights` step flies the stress replay and
## `guide_lights_g2` flies G2 (it has the tunnels, junction, room and reactor
## room the stress scene's single room lacks), then:
##
## - `guide_lights_drawn`: the look's `guide_lights` section was read, every box
##   the camera shows draws its strips in its bevels' surface, no box costs more
##   than its two draw calls, at least two box kinds are lit so places are told
##   apart (on a level of more than one box), and the strips added no light.
##   It reports the strips' cost: their triangles, and the draw calls they add
##   (none). It then saves a picture in a tunnel, a junction and the reactor
##   room, looking along each, as `<step id>_<kind>.png` under `m6/`; one that
##   cannot be taken is noted and never fails the step.
## - `guide_lights_brighter`: draws the same frame with the strips off and on
##   and requires the mean luminance to rise, reporting both. Skipped where
##   nothing is drawn (headless).
##
## Both read the view only and put the renderer's camera back; the step's
## pinned hash holds the simulation (ARC-1). Whether the mine is "not gloomy,
## tunnel readable" stays human-checked in the headset.

const CHECK_DRAWN: String = "guide_lights_drawn"
const CHECK_BRIGHTER: String = "guide_lights_brighter"
const SHOT_FOLDER: String = "m6"
const SHOT_KINDS: Array[String] = [GuideLightRules.KIND_TUNNEL, GuideLightRules.KIND_JUNCTION,
	GuideLightRules.KIND_REACTOR]
## How far back from a box's middle, as a share of its length, its picture is taken.
const SHOT_BACK_SHARE: float = 0.33
## The square the frames are shrunk to before their luminance is averaged.
const SAMPLE_SIZE: int = 64


static func judges() -> Dictionary[String, Callable]:
	return {CHECK_DRAWN: _judge_drawn, CHECK_BRIGHTER: _judge_brighter}


static func _view(runner: AcceptanceRunner) -> LevelView:
	var main: Node = runner.main if runner != null else null
	return main.get_node_or_null(LevelView.NODE_NAME) as LevelView if main != null else null


static func _judge_drawn(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var view: LevelView = _view(runner)
	var verdict: Array = judge_view(view, measurements)
	if view != null and verdict[0] == AcceptanceReport.RESULT_PASS:
		measurements["screenshots"] = ", ".join(PackedStringArray(_place_shots(runner, view, step.id)))
	return verdict


## [result, message] for `view`, adding what the strips cost to `measurements`.
static func judge_view(view: LevelView, measurements: Dictionary) -> Array:
	if view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no level"]
	var lights: GuideLights = view.guide_lights
	if lights.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the guide light rules were rejected: %s" % lights.error]
	if not lights.enabled or lights.strips.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the level draws no guide lights"]
	var shown: int = 0
	var kinds: Dictionary = {}
	for box: int in view.box_count():
		kinds[lights.kinds[box]] = int(kinds.get(lights.kinds[box], 0)) + 1
		if view.surfaces_of(box) > 2:
			return [AcceptanceReport.RESULT_FAIL, "box %d costs %d draw calls" % [box, view.surfaces_of(box)]]
		var node: Node3D = view.box_node(box)
		if node == null or not node.visible:
			continue
		shown += 1
		var glowing: int = glowing_vertices(view.bevels_of(box))
		if glowing != lights.strips_of(box).size() * 6:
			return [AcceptanceReport.RESULT_FAIL, "shown box %d (%s) draws %d strip vertices for %d strips" % [
				box, lights.kinds[box], glowing, lights.strips_of(box).size()]]
	# A one-box level (the stress scene's reactor room) has one kind by definition.
	if kinds.size() < 2 and view.box_count() > 1:
		return [AcceptanceReport.RESULT_FAIL, "every box is a %s, so no place stands apart" % [kinds.keys()]]
	var added_lights: int = 0
	for box: int in view.box_count():
		added_lights += view.box_node(box).find_children("*", "Light3D", true, false).size()
	measurements["guide_strips"] = lights.strips.size()
	measurements["guide_triangles"] = lights.strips.size() * 2
	measurements["guide_draw_calls"] = 0
	measurements["guide_boxes_shown"] = shown
	measurements["guide_kinds"] = JSON.stringify(kinds)
	if added_lights > 0:
		return [AcceptanceReport.RESULT_FAIL, "the boxes hold %d lights; the strips must add none" % added_lights]
	return [AcceptanceReport.RESULT_PASS, "%d strips (%d triangles, no extra draw call) over %d boxes, %d shown; kinds %s" % [
		lights.strips.size(), lights.strips.size() * 2, view.box_count(), shown, JSON.stringify(kinds)]]


## Vertices of `part`'s first surface whose colour is not black: strip vertices.
static func glowing_vertices(part: MeshInstance3D) -> int:
	if part == null or part.mesh == null or part.mesh.get_surface_count() == 0:
		return 0
	var colors: Variant = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var count: int = 0
	if colors is PackedColorArray:
		for color: Color in colors as PackedColorArray:
			if color.r > 0.0 or color.g > 0.0 or color.b > 0.0:
				count += 1
	return count


static func _judge_brighter(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var view: LevelView = _view(runner)
	if view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no level"]
	if DisplayServer.get_name() == "headless":
		return [AcceptanceReport.RESULT_SKIPPED, "headless display: nothing is drawn"]
	var was_on: bool = view.guide_lights.is_on()
	var means: Array[float] = []
	for on: bool in [false, true]:
		view.guide_lights.set_on(on)
		RenderingServer.force_draw(true, 0.0)
		var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to read the image with"
		if not got is Image or (got as Image).is_empty():
			view.guide_lights.set_on(was_on)
			return [AcceptanceReport.RESULT_SKIPPED, "no image to measure: %s" % str(got)]
		means.append(mean_luminance(got as Image))
	view.guide_lights.set_on(was_on)
	measurements["luminance_strips_off"] = snappedf(means[0], 0.0001)
	measurements["luminance_strips_on"] = snappedf(means[1], 0.0001)
	var message: String = "mean luminance %.4f with the strips off, %.4f on" % [means[0], means[1]]
	if means[1] <= means[0]:
		return [AcceptanceReport.RESULT_FAIL, message + ": the strips do not brighten the mine"]
	return [AcceptanceReport.RESULT_PASS, message]


## The mean luminance (0 to 1) of `image` shrunk to `SAMPLE_SIZE` square. Works on a copy.
static func mean_luminance(image: Image) -> float:
	var copy: Image = image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGB8)
	copy.resize(SAMPLE_SIZE, SAMPLE_SIZE, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in SAMPLE_SIZE:
		for x: int in SAMPLE_SIZE:
			var colour: Color = copy.get_pixel(x, y)
			total += 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
	return total / float(SAMPLE_SIZE * SAMPLE_SIZE)


## A picture of the first box of each kind in `SHOT_KINDS`, looking along it
## towards its middle. Only the renderer's camera is posed for the picture, then
## put back. Returns the paths saved, or why each was not.
static func _place_shots(runner: AcceptanceRunner, view: LevelView, step_id: String) -> Array[String]:
	var notes: Array[String] = []
	var camera: Camera3D = view.get_viewport().get_camera_3d() if view.is_inside_tree() else null
	for kind: String in SHOT_KINDS:
		var file: String = "%s_%s.png" % [step_id, kind]
		var box: int = view.guide_lights.kinds.find(kind)
		if box < 0:
			notes.append("skipped %s: the level has no %s" % [file, kind])
		elif camera == null:
			notes.append("skipped %s: the scene has no camera" % file)
		elif DisplayServer.get_name() == "headless":
			notes.append("skipped %s: headless display, nothing is drawn" % file)
		else:
			notes.append(_shot_in(runner, view, camera, box, file))
	return notes


static func _shot_in(runner: AcceptanceRunner, view: LevelView, camera: Camera3D, box: int, file: String) -> String:
	var bounds: BoxBounds = view.guide_lights.union.boxes[box]
	var look: Vector3 = Vector3.ZERO
	var size: Vector3 = bounds.max_corner - bounds.min_corner
	look[size.max_axis_index()] = -1.0
	var middle: Vector3 = (bounds.min_corner + bounds.max_corner) * 0.5
	# A third of the way back, looking at the middle: from the middle itself the
	# reactor room's picture is the inside of the reactor's glow.
	var eye: Vector3 = view.global_transform * (middle - look * size[size.max_axis_index()] * SHOT_BACK_SHARE)
	var up: Vector3 = Vector3.FORWARD if absf(look.y) > 0.5 else Vector3.UP
	var wanted: Transform3D = Transform3D(Basis.IDENTITY, eye).looking_at(view.global_transform * middle, up)
	# The renderer's camera is posed directly: a moved node only reaches the
	# renderer once the frame's transform notifications are flushed, after
	# `force_draw`. No node moves, so the rig and the cockpit stay where they are.
	var kept: Transform3D = camera.global_transform
	_cull_from(view, wanted)
	RenderingServer.camera_set_transform(camera.get_camera_rid(), wanted)
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	RenderingServer.camera_set_transform(camera.get_camera_rid(), kept)
	_cull_from(view, kept)
	if not got is Image:
		return "skipped %s: %s" % [file, str(got)]
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(file)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped %s: cannot write %s: %s" % [file, path, error_string(error)]


## Shows the boxes seen from an eye at `eye` (global); `cull_camera` culls once a frame.
static func _cull_from(view: LevelView, eye: Transform3D) -> void:
	var to_level: Transform3D = view.global_transform.affine_inverse() * eye
	view.cull(to_level.origin, to_level.basis)
