extends RefCounted

## The m6 `glass_clear` step (#1459, GFX-2, CMF-8, DEV-6, decision record
## 0005): after m6's flight, each preset's view is drawn with the cockpit glass
## on and off, both pictures saved, and the area seen through the canopy must
## keep its mean luminance and contrast within 10 percent. Only the headset
## draws; here the check's parts are driven with pictures made to order.

const CHECK_SCRIPT: String = "res://acceptance/checks/glass_clear_check.gd"
const FrameTests := preload("res://tests/test_cockpit_frame.gd")
const STEP_ID: String = "glass_clear"
const SCRATCH: String = "user://meltdown_test_glass_clear"


static func _step(id: String) -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == id:
			return found
	return null


## A picture of `size` square: a left-to-right ramp from `low` to `high` grey.
static func _ramp(size: int, low: float, high: float) -> Image:
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	for x: int in size:
		var grey: float = lerpf(low, high, float(x) / float(size - 1))
		for y: int in size:
			image.set_pixel(x, y, Color(grey, grey, grey))
	return image


## Measures a preset-4 frame whose "drawn" picture is `on` with its glass
## shown and `off` with it hidden; returns [pair, glass visible after].
static func _measure(on: Variant, off: Variant, folder: String) -> Array:
	var check: GDScript = load(CHECK_SCRIPT)
	var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(4))
	var glass: MultiMeshInstance3D = frame.part("Glass")
	var grab: Callable = func() -> Variant: return on if glass.visible else off
	var pair: Dictionary = check.measure_frame(frame, grab, null, folder, "test")
	var visible_after: bool = glass.visible
	frame.free()
	return [pair, visible_after]


static func _remove_scratch() -> void:
	for file_name: String in ["test_glass_on.png", "test_glass_off.png"]:
		var path: String = SCRATCH.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func test_the_step_flies_m6s_flight_and_judges_the_glass() -> String:
	var found: AcceptanceStep = _step(STEP_ID)
	var walls: AcceptanceStep = _step("wall_material")
	if found == null or walls == null:
		return "steps found: %s %s, wall_material %s" % [STEP_ID, found, walls]
	if found.replay_path != walls.replay_path or found.expected_hash != walls.expected_hash:
		return "the step flies %s to %d, not wall_material's flight" % [found.replay_path, found.expected_hash]
	for needed: String in ["final_hash", "glass_clear", "no_script_errors"]:
		if not found.has_check(needed):
			return "the step does not check %s: %s" % [needed, found.checks]
	var check: GDScript = load(CHECK_SCRIPT)
	if str(check.PRESETS) != "[1, 2, 3, 4]" or not is_equal_approx(check.MAX_CHANGE, 0.1):
		return "the check judges presets %s within %s" % [check.PRESETS, check.MAX_CHANGE]
	return ""


func test_clear_glass_passes_and_both_pictures_are_saved() -> String:
	_remove_scratch()
	var measured: Array = _measure(_ramp(64, 0.1, 0.5), _ramp(64, 0.1, 0.52), SCRATCH)
	var pair: Dictionary = measured[0]
	var check: GDScript = load(CHECK_SCRIPT)
	var problem: String = ""
	if pair.has("skipped") or not check.passes(pair):
		problem = "clear glass judged %s" % pair
	elif not measured[1]:
		problem = "the glass was left hidden"
	elif not FileAccess.file_exists(str(pair["shot_on"])) or not FileAccess.file_exists(str(pair["shot_off"])):
		problem = "the pair was not saved: %s, %s" % [pair["shot_on"], pair["shot_off"]]
	elif check.describe(pair).find("on") < 0:
		problem = "the message does not give both numbers: %s" % check.describe(pair)
	_remove_scratch()
	return problem


func test_a_darkening_glass_fails_on_the_mean() -> String:
	var measured: Array = _measure(_ramp(64, 0.06, 0.3), _ramp(64, 0.1, 0.5), "")
	var pair: Dictionary = measured[0]
	var check: GDScript = load(CHECK_SCRIPT)
	if check.passes(pair) or float(pair["mean_change"]) > -0.1:
		return "a glass taking 40 percent away judged %s" % pair
	return "" if measured[1] else "the glass was left hidden"


func test_a_veil_fails_on_the_contrast() -> String:
	# The #1306 glass on a dark mine: brighter and flatter at once.
	var measured: Array = _measure(_ramp(64, 0.25, 0.35), _ramp(64, 0.1, 0.5), "")
	var pair: Dictionary = measured[0]
	var check: GDScript = load(CHECK_SCRIPT)
	if check.passes(pair) or float(pair["contrast_change"]) > -0.1:
		return "a veil judged %s" % pair
	return ""


func test_no_picture_is_skipped_and_leaves_the_glass_shown() -> String:
	var measured: Array = _measure("headless display: nothing is drawn", "headless display: nothing is drawn", "")
	var pair: Dictionary = measured[0]
	if not pair.has("skipped") or str(pair["skipped"]).find("headless") < 0:
		return "no picture judged %s" % pair
	return "" if measured[1] else "the glass was left hidden"


func test_stats_and_change() -> String:
	var check: GDScript = load(CHECK_SCRIPT)
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(4, 0, 4, 8), Color.WHITE)
	var lit: Dictionary = check.stats(image, Rect2i(0, 0, 8, 8))
	if not is_equal_approx(float(lit["mean"]), 0.5) or not is_equal_approx(float(lit["contrast"]), 0.5):
		return "half black, half white measured %s" % lit
	var right: Dictionary = check.stats(image, Rect2i(4, 0, 4, 8))
	if not is_equal_approx(float(right["mean"]), 1.0) or float(right["contrast"]) != 0.0:
		return "the white half measured %s" % right
	if not is_equal_approx(check.change(0.55, 0.5), 0.1):
		return "0.55 against 0.5 changed %s" % check.change(0.55, 0.5)
	if absf(check.change(0.005, 0.0)) > 0.3:
		return "a near-black difference counted as %s" % check.change(0.005, 0.0)
	return ""


func test_without_a_camera_the_middle_of_the_picture_is_judged() -> String:
	var check: GDScript = load(CHECK_SCRIPT)
	var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(1))
	var area: Rect2i = check.canopy_rect(frame, null, Vector2i(200, 100))
	frame.free()
	return "" if area == Rect2i(50, 25, 100, 50) else "judged %s" % area
