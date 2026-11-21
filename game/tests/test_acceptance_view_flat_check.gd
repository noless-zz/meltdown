extends RefCounted

## The `view_not_flat` acceptance check (#737, part 1 of #734): a flat eye
## image fails, a tunnel or a dark but textured one does not, the thresholds
## come from the data file, the check is skipped off the headset, and `m1`
## carries the step.

const FakeXr := preload("res://tests/fake_initialized_xr.gd")
const FRAME_90: float = 1.0 / 90.0
const FRAME_LIMIT: int = 20000
const SIZE: int = 128
const TEMP_DATA: String = "user://test_view_flat.json"


static func _flat_image(colour: Color, noise: float) -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 737
	for y: int in SIZE:
		for x: int in SIZE:
			image.set_pixel(x, y, Color(colour.r + rng.randf_range(-noise, noise),
				colour.g + rng.randf_range(-noise, noise), colour.b + rng.randf_range(-noise, noise)))
	return image


## A lit tunnel seen down its length: a radial falloff towards the far end
## with the panel seams as dark lines.
static func _tunnel_image() -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: Vector2 = Vector2(SIZE, SIZE) * 0.5
	for y: int in SIZE:
		for x: int in SIZE:
			var distance: float = Vector2(x, y).distance_to(centre) / (SIZE * 0.7)
			var level: float = clampf(distance, 0.05, 0.9)
			if x % 16 == 0 or y % 16 == 0:
				level *= 0.3
			image.set_pixel(x, y, Color(level, level * 0.9, level * 0.8))
	return image


## Mostly near black, with dim texture: a tunnel lit only by a weak lamp.
static func _dark_textured_image() -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 734
	for y: int in SIZE:
		for x: int in SIZE:
			var level: float = 0.02 + 0.1 * float(((x >> 3) + (y >> 3)) % 2) + rng.randf_range(0.0, 0.05)
			image.set_pixel(x, y, Color(level, level, level * 1.1))
	return image


static func _judged(image: Image) -> Dictionary:
	var check: AcceptanceViewFlatCheck = AcceptanceViewFlatCheck.from_file()
	if check.error != "":
		return {"error": check.error}
	return check.sample(image, 1.0)


func test_one_colour_is_flat() -> String:
	var measured: Dictionary = _judged(_flat_image(Color(0.3, 0.45, 0.6), 0.0))
	if not measured.get("flat", false) or int(measured["colours"]) != 1 or float(measured["stddev"]) != 0.0:
		return "one colour judged %s" % measured
	return ""


func test_one_colour_with_faint_noise_is_flat() -> String:
	var measured: Dictionary = _judged(_flat_image(Color(0.4, 0.2, 0.7), 0.01))
	if not measured.get("flat", false):
		return "faint noise judged %s" % measured
	return ""


func test_a_tunnel_is_not_flat() -> String:
	var measured: Dictionary = _judged(_tunnel_image())
	if measured.get("flat", true):
		return "tunnel judged %s" % measured
	return ""


func test_a_dark_textured_view_is_not_flat() -> String:
	var measured: Dictionary = _judged(_dark_textured_image())
	if measured.get("flat", true):
		return "dark textured view judged %s" % measured
	if float(measured["stddev"]) > 0.1:
		return "the dark image is not dark: %s" % measured
	return ""


## The shipped file is what the check reads, and a different file changes the verdict.
func test_thresholds_come_from_the_data_file() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AcceptanceViewFlatCheck.DATA_PATH))
	var check: AcceptanceViewFlatCheck = AcceptanceViewFlatCheck.from_file()
	if check.error != "" or check.flat_stddev_below != float(shipped["flat_luminance_stddev_below"]) \
			or check.flat_colours_below != int(shipped["flat_colours_below"]) \
			or check.sample_size != int(shipped["sample_size"]) \
			or check.interval_seconds != float(shipped["sample_interval_seconds"]):
		return "shipped thresholds not read: %s" % check.error
	var loose: Dictionary = shipped.duplicate()
	loose["flat_luminance_stddev_below"] = 0.5
	loose["flat_colours_below"] = 256
	var problem: String = _write_temp(loose)
	if problem != "":
		return problem
	var tuned: AcceptanceViewFlatCheck = AcceptanceViewFlatCheck.from_file(TEMP_DATA)
	if tuned.error != "" or not tuned.sample(_tunnel_image(), 2.0)["flat"]:
		problem = "the tuned file did not change the verdict: %s" % tuned.error
	var cases: Dictionary = {"sample_interval_seconds": 3.0, "flat_colours_below": 1.5, "colour_levels": true,
		"flat_luminance_stddev_below": 0.0}
	for key: String in cases:
		if problem != "":
			break
		var bad: Dictionary = shipped.duplicate()
		bad[key] = cases[key]
		problem = _write_temp(bad)
		if problem == "" and not AcceptanceViewFlatCheck.from_file(TEMP_DATA).error.contains(key):
			problem = "%s = %s was accepted" % [key, cases[key]]
	DirAccess.remove_absolute(TEMP_DATA)
	if problem == "" and AcceptanceViewFlatCheck.from_file(TEMP_DATA).error == "":
		problem = "a missing data file was accepted"
	return problem


func test_skipped_off_the_headset_and_failed_when_required() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.checks = [AcceptanceStep.CHECK_VIEW_NOT_FLAT]
	step.view_seconds = 60.0
	if AcceptanceViewFlatCheck.for_step(step, false, false, Callable()) != null \
			or AcceptanceViewFlatCheck.for_step(step, true, false, Callable()) != null:
		return "the image was sampled off the headset"
	for xr: bool in [false, true]:
		var outcome: Array = AcceptanceViewFlatCheck.run(xr, false, step, null, {})
		if outcome[0] != AcceptanceReport.RESULT_SKIPPED:
			return "off the headset (xr %s): %s" % [xr, outcome]
	step.required = true
	var required: Array = AcceptanceViewFlatCheck.run(false, false, step, null, {})
	if required[0] != AcceptanceReport.RESULT_FAIL:
		return "a required step passed without a session: %s" % [required]
	return ""


func test_m1_has_the_step() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("m1")[0]
	if suite.error != "":
		return suite.error
	for step: AcceptanceStep in suite.steps:
		if step.id == "view_not_flat":
			if step.checks != [AcceptanceStep.CHECK_VIEW_NOT_FLAT] or step.view_seconds != 60.0 \
					or step.replay_path != "" or step.level != "":
				return "m1 view_not_flat: %s, %s s" % [step.checks, step.view_seconds]
			return ""
	return "m1 has no view_not_flat step"


func test_the_suite_keys_are_checked() -> String:
	var cases: Dictionary = {
		"\"checks\": [\"view_not_flat\"]": "view_seconds: needed",
		"\"checks\": [\"refresh_rate\"], \"view_seconds\": 60": "only used by the view_not_flat check",
		"\"checks\": [\"view_not_flat\"], \"view_seconds\": true": "must be a number",
		"\"checks\": [\"view_not_flat\"], \"view_seconds\": 1": "must be a number",
		"\"checks\": [\"view_not_flat\"], \"view_seconds\": 601": "must be a number",
	}
	for keys: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"x\", \"steps\": [{\"id\": \"v\", %s}]}" % keys)
		if not suite.error.contains(cases[keys]):
			return "%s gave '%s'" % [keys, suite.error]
	return ""


## On a stand-in headset the runner samples for the step's length, every two
## seconds, and fails naming the first flat sample's time.
func test_the_runner_fails_on_a_flat_sample() -> String:
	var calls: Array[int] = [0]
	var grab: Callable = func() -> Variant:
		calls[0] += 1
		return _flat_image(Color(0.5, 0.5, 0.5), 0.0) if calls[0] == 3 else _tunnel_image()
	var step: Dictionary = _run_step(grab)
	var measurements: Dictionary = step.get("measurements", {})
	if step.get("result") != AcceptanceReport.RESULT_FAIL or not str(step.get("message")).contains("flat at 6.0") \
			or measurements.get("samples") != 5 or measurements.get("flat_samples") != 1 \
			or measurements.get("lowest_luminance_stddev") != 0.0:
		return "flat sample: %s" % step
	return ""


func test_the_runner_passes_a_textured_view() -> String:
	var step: Dictionary = _run_step(func() -> Variant: return _tunnel_image())
	var measurements: Dictionary = step.get("measurements", {})
	if step.get("result") != AcceptanceReport.RESULT_PASS or measurements.get("samples") != 5 \
			or measurements.get("flat_samples") != 0:
		return "textured view: %s" % step
	return ""


func test_the_runner_fails_when_no_image_can_be_read() -> String:
	var step: Dictionary = _run_step(func() -> Variant: return "the renderer gave no image")
	if step.get("result") != AcceptanceReport.RESULT_FAIL \
			or not str(step.get("message")).contains("the renderer gave no image"):
		return "no image: %s" % step
	return ""


## Runs one 10 s view_not_flat step at 90 Hz on a stand-in headset.
func _run_step(grab: Callable) -> Dictionary:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t737\", \"steps\": [{\"id\": \"v\", "
		+ "\"checks\": [\"view_not_flat\"], \"view_seconds\": 10}]}")
	var suites: Array[AcceptanceSuite] = [suite]
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.on_headset = true
	runner.screenshots.grab = grab
	runner.setup(main, suites, FakeXr.new())
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame(FRAME_90)
		frames += 1
	var step: Dictionary = {"result": "unfinished", "message": "\n".join(runner.messages)}
	if runner.finished and not runner.reports.is_empty():
		step = runner.reports[0].steps[0]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return step


func _write_temp(data: Dictionary) -> String:
	var file: FileAccess = FileAccess.open(TEMP_DATA, FileAccess.WRITE)
	if file == null:
		return "cannot write %s" % TEMP_DATA
	file.store_string(JSON.stringify(data))
	file.close()
	return ""
