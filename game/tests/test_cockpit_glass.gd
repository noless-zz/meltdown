extends RefCounted

## The canopy glass lets the mine through (#1459, GFX-2, CMF-8, ARC-3, ARC-4):
## its transmission and tint are keys of each cockpit file, the parser refuses
## a dark glass and names the field, every shipped cockpit lets at least
## `SHIPPED_MIN_TRANSMISSION` through with a near-neutral tint, and the built
## glass multiplies the view by them instead of laying a colour over it.

const FrameTests := preload("res://tests/test_cockpit_frame.gd")
const CHECK_SCRIPT: String = "res://acceptance/checks/glass_clear_check.gd"
## The issue's shipped defaults.
const SHIPPED_MIN_TRANSMISSION: float = 0.92
## Largest channel less smallest: "close to neutral".
const NEUTRAL_TINT_MAX_SPREAD: float = 0.06
## Linear brightness of a mine pixel from near black to a lit wall.
const MINE_LEVELS: Array[float] = [0.003, 0.01, 0.03, 0.1, 0.3]


static func _parsed(changes: Dictionary) -> CockpitSpec:
	var data: Dictionary = FrameTests.valid_data()
	for key: String in changes:
		if changes[key] == null:
			data.erase(key)
		else:
			data[key] = changes[key]
	return CockpitSpec.parse_json(JSON.stringify(data))


func test_the_file_sets_transmission_and_tint() -> String:
	var spec: CockpitSpec = _parsed({"glass_transmission": 0.93, "glass_tint": [0.9, 0.95, 1.0]})
	if spec.error != "":
		return spec.error
	if not is_equal_approx(spec.glass_transmission, 0.93) or not is_equal_approx(spec.glass_opacity(), 0.07):
		return "transmission %s, opacity %s" % [spec.glass_transmission, spec.glass_opacity()]
	if not spec.glass_tint.is_equal_approx(Color(0.9, 0.95, 1.0)):
		return "tint %s" % spec.glass_tint
	if not is_equal_approx(spec.tint_spread(), 0.1):
		return "tint spread %s" % spec.tint_spread()
	return ""


func test_the_parser_refuses_a_dark_glass_and_names_the_field() -> String:
	var floor_spec: CockpitSpec = _parsed({"glass_transmission": CockpitSpec.MIN_GLASS_TRANSMISSION})
	if floor_spec.error != "":
		return "the floor itself is refused: %s" % floor_spec.error
	if CockpitSpec.MIN_GLASS_TRANSMISSION < 0.8:
		return "the floor is %s; the issue sets 0.8" % CockpitSpec.MIN_GLASS_TRANSMISSION
	for dark: float in [0.79, 0.5, 0.0]:
		var error: String = _parsed({"glass_transmission": dark}).error
		if error.find("glass_transmission") < 0:
			return "transmission %s: error \"%s\" does not name the field" % [dark, error]
	var old: String = _parsed({"glass_transmission": null, "glass_tint_alpha": 0.05}).error
	if old.find("glass_tint_alpha") < 0:
		return "the retired key is not named: \"%s\"" % old
	return ""


func test_a_bad_tint_names_the_field() -> String:
	var cases: Dictionary[String, Variant] = {
		"missing": null, "two numbers": [1.0, 1.0], "too bright": [1.0, 1.0, 1.2], "a string": "white",
		"a bool": [true, 1.0, 1.0],
	}
	for case: String in cases:
		var error: String = _parsed({"glass_tint": cases[case]}).error
		if error.find(CockpitSpec.GLASS_TINT_KEY) < 0:
			return "%s: error \"%s\" does not name %s" % [case, error, CockpitSpec.GLASS_TINT_KEY]
	return ""


func test_every_shipped_cockpit_lets_the_mine_through() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
		if spec.glass_transmission < SHIPPED_MIN_TRANSMISSION:
			return "preset %d lets %s through, below %s" % [number, spec.glass_transmission, SHIPPED_MIN_TRANSMISSION]
		if spec.tint_spread() > NEUTRAL_TINT_MAX_SPREAD:
			return "preset %d tint %s is %s from grey" % [number, spec.glass_tint, spec.tint_spread()]
		if spec.finish.glass_fresnel <= 0.0:
			return "preset %d glass has no edge reflection to say it is glass" % number
	return ""


func test_the_filter_scales_by_transmission_on_the_brightest_channel() -> String:
	var neutral: Color = CockpitMaterials.glass_filter(Color(0.5, 0.5, 0.5, 0.05))
	if not neutral.is_equal_approx(Color(0.95, 0.95, 0.95)):
		return "a grey tint filters %s" % neutral
	var tinted: Color = CockpitMaterials.glass_filter(Color(0.8, 0.9, 1.0, 0.1))
	if not tinted.is_equal_approx(Color(0.72, 0.81, 0.9)):
		return "a blue tint filters %s" % tinted
	var black: Color = CockpitMaterials.glass_filter(Color(0.0, 0.0, 0.0, 0.08))
	if not black.is_equal_approx(Color(0.92, 0.92, 0.92)):
		return "a black tint filters %s" % black
	return ""


func test_the_built_glass_multiplies_by_the_files_filter() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var glass: MultiMeshInstance3D = frame.part("Glass")
		var material: ShaderMaterial = glass.material_override as ShaderMaterial if glass != null else null
		var built: Variant = material.get_shader_parameter("filter_color") if material != null else null
		frame.free()
		var tint: Color = spec.glass_tint
		tint.a = spec.glass_opacity()
		var expected: Color = CockpitMaterials.glass_filter(tint)
		if not built is Vector3 or not (built as Vector3).is_equal_approx(Vector3(expected.r, expected.g, expected.b)):
			return "preset %d glass filters %s, the file says %s" % [number, built, expected]
	return ""


## What `glass_clear` measures on the headset, worked out here for a mine of
## even brightness: the shipped filter and the reflection across the judged
## part of the window must keep the mean within the check's limit, from a
## near-black tunnel to a lit wall. The #1306 glass mixed in a light colour
## and failed this by far on a dark mine.
func test_shipped_glass_keeps_a_dark_mine_within_the_check() -> String:
	var check: GDScript = load(CHECK_SCRIPT)
	var fraction: float = check.WINDOW_FRACTION
	var steps: int = 24
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		var tint: Color = spec.glass_tint
		tint.a = spec.glass_opacity()
		var filter: Color = CockpitMaterials.glass_filter(tint)
		var shine: Color = spec.finish.glass_fresnel_color.srgb_to_linear()
		for level: float in MINE_LEVELS:
			var on: float = 0.0
			for i: int in steps:
				for j: int in steps:
					var edge: float = maxf(absf((i + 0.5) / steps * 2.0 - 1.0), absf((j + 0.5) / steps * 2.0 - 1.0)) * fraction
					var added: float = spec.finish.glass_fresnel * pow(edge, spec.finish.glass_fresnel_power)
					var seen: Color = Color(level * filter.r + added * shine.r, level * filter.g + added * shine.g,
						level * filter.b + added * shine.b)
					on += seen.linear_to_srgb().get_luminance()
			on /= float(steps * steps)
			var off: float = Color(level, level, level).linear_to_srgb().get_luminance()
			var changed: float = check.change(on, off)
			if absf(changed) > check.MAX_CHANGE:
				return "preset %d over a mine at %s: mean %.3f on, %.3f off (%+.1f%%)" % [number, level, on, off, changed * 100.0]
	return ""
