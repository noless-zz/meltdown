extends RefCounted

## The `view_not_magnified` check (#1513, CMF-8, PRF-1, GFX-7, DEV-6, decision
## record 0005), lane-a's file under `acceptance/checks/`. In `suites/m1.json`:
##
##     {"id": "view_not_magnified", "checks": ["view_not_magnified"]}
##
## Its frame work puts a flat magenta square of known size (`half_size_m`) at a
## known distance (`distance_m`) straight ahead of the camera in the test tunnel,
## drawn over everything, and waits `settle_frames` drawn frames. It then takes
## the drawn picture and measures the square (`AcceptanceMagnify`). With a stereo
## runtime the picture is the left eye's, so its projection and pose are the
## runtime's; otherwise the camera's. A render scale of 0.7 stretched over the
## view (the fault of 27 Nov, #1503) draws the square 1.43 times too big and fails.
##
## The square is a view node, taken out when the step ends; the simulation
## never sees it (ARC-3). Where nothing is drawn the check is skipped.

const CHECK: String = "view_not_magnified"
const DATA_FILE: String = "res://acceptance/checks/eye_frames.json"
const TARGET_NAME: String = "MagnifyTarget"
const KEYS: Dictionary = {
	"distance_m": Vector2(0.5, 10.0),
	"half_size_m": Vector2(0.02, 2.0),
	"settle_frames": Vector2(1.0, 30.0),
	"tolerance": Vector2(0.005, 0.3),
}


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func frame_work() -> Dictionary[String, Callable]:
	return {CHECK: _start}


## The values of the check's section in `path` as floats, or {"error": ...} naming the file and key.
static func read_values(path: String) -> Dictionary:
	var section: Dictionary = AcceptanceEyePair.read_section(path, CHECK)
	if section.has("error"):
		return section
	var values: Dictionary = {}
	for key: String in KEYS:
		var value: Variant = section.get(key)
		var range_: Vector2 = KEYS[key]
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or float(value) < range_.x or float(value) > range_.y:
			return {"error": "%s: %s.%s must be a number within %s..%s" % [path, CHECK, key, range_.x, range_.y]}
		values[key] = float(value)
	return values


## A square facing -z, unshaded and drawn over everything, in `TARGET_COLOUR`.
static func make_target(half_size: float) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = AcceptanceMagnify.TARGET_COLOUR
	material.disabled_fog = true
	# Depth testing is skipped only in the transparent pass, so the square is drawn
	# there, last, over the cockpit and the glass.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = Material.RENDER_PRIORITY_MAX
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(half_size * 2.0, half_size * 2.0)
	var target: MeshInstance3D = MeshInstance3D.new()
	target.name = TARGET_NAME
	target.mesh = quad
	target.material_override = material
	target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return target


static func _start(_step: AcceptanceStep, runner: AcceptanceRunner, frames: AcceptanceFrameHook) -> void:
	var values: Dictionary = read_values(DATA_FILE)
	if values.has("error"):
		frames.results[CHECK] = {"error": values["error"]}
		return
	var camera: Camera3D = runner.main.get_viewport().get_camera_3d() if runner.main.is_inside_tree() else null
	if camera == null:
		frames.results[CHECK] = {"skipped": "the scene has no camera in a viewport"}
		return
	var target: MeshInstance3D = make_target(float(values["half_size_m"]))
	target.position = Vector3(0.0, 0.0, -float(values["distance_m"]))
	camera.add_child(target)
	frames.on_end(func() -> void:
		if is_instance_valid(target):
			target.get_parent().remove_child(target)
			target.free())
	var left: Array[int] = [int(values["settle_frames"])]
	var on_frame: Array[Callable] = []
	on_frame.append(func(drawn: bool, _usec: int) -> void:
		if not drawn:
			frames.results[CHECK] = {"skipped": "nothing is drawn here (headless display or dummy renderer)"}
			return
		left[0] -= 1
		if left[0] > 0:
			frames.next_drawn_frame(on_frame[0])
			return
		frames.results[CHECK] = _measure(runner, camera, values))
	frames.next_drawn_frame(on_frame[0])


## What the drawn picture shows of the target: {"expected", "measured", "source", ...} or {"skipped"}.
static func _measure(runner: AcceptanceRunner, camera: Camera3D, values: Dictionary) -> Dictionary:
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return {"skipped": str(got)}
	var image: Image = got
	var centre_world: Vector3 = camera.global_transform * Vector3(0.0, 0.0, -float(values["distance_m"]))
	var projection: Projection = camera.get_camera_projection()
	var eye: Transform3D = camera.global_transform
	var source: String = "camera"
	var xr: XRInterface = runner.xr_interface
	if xr != null and xr.is_initialized() and xr.get_view_count() == 2:
		var origin: Node3D = camera.get_parent() as Node3D
		var origin_transform: Transform3D = origin.global_transform if origin != null else Transform3D.IDENTITY
		projection = xr.get_projection_for_view(AcceptanceEyePair.LEFT, float(image.get_width()) / float(image.get_height()),
			camera.near, camera.far)
		eye = xr.get_transform_for_view(AcceptanceEyePair.LEFT, origin_transform)
		source = "left eye"
	var centre: Vector3 = eye.affine_inverse() * centre_world
	var expected: Rect2 = AcceptanceMagnify.expected_rect(projection, centre, float(values["half_size_m"]), image.get_size())
	return {"expected": expected, "measured": AcceptanceMagnify.measure(image, expected), "source": source,
		"picture_px": [image.get_width(), image.get_height()], "render_scale": RenderScaler.in_use,
		"tolerance": float(values["tolerance"])}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var frames: AcceptanceFrameHook = runner.frame_hook() if runner != null else null
	var found: Dictionary = frames.results.get(CHECK, {}) if frames != null else {}
	if found.has("error"):
		return [AcceptanceReport.RESULT_FAIL, found["error"]]
	if found.has("skipped"):
		measurements["skipped"] = found["skipped"]
		return [AcceptanceReport.RESULT_FAIL if step.required else AcceptanceReport.RESULT_SKIPPED,
			"nothing drawn to measure: %s" % found["skipped"]]
	if not found.has("expected"):
		return [AcceptanceReport.RESULT_FAIL, "no picture was measured: the check's frame work did not finish"]
	measurements["source"] = found["source"]
	measurements["picture_px"] = found["picture_px"]
	measurements["render_scale"] = found["render_scale"]
	var result: Array = AcceptanceMagnify.judge(found["expected"], found["measured"], float(found["tolerance"]),
		measurements)
	return [result[0], "%s (%s, render scale %.2f)" % [result[1], found["source"], float(found["render_scale"])]]
