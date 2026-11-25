extends RefCounted

## The home base screens' look and the arithmetic that says whether they can
## be read (#1359, CRW-2, ARC-4): the shipped look parses and matches its
## fallback, a bad file is refused with the key named, every word colour
## passes the contrast floor on the screen's face, the contrast, angle and
## pixel formulas give known values, and no screen material outshines the room.

const CHECK: GDScript = preload("res://acceptance/checks/hub_screens_check.gd")
const TEXT_KEYS: Array[String] = ["title_color", "text_color", "selected_color", "reason_color"]


func test_the_shipped_look_parses_and_matches_the_fallback() -> String:
	var look: Dictionary = HubScreenLook.parse(FileAccess.get_file_as_string(HubScreenLook.DEFAULT_FILE))
	if look.has("error"):
		return "the shipped look is refused: %s" % look["error"]
	for key: String in HubScreenLook.FALLBACK:
		if look[key] != HubScreenLook.FALLBACK[key]:
			return "\"%s\" is %s in the file and %s in the fallback" % [key, look[key], HubScreenLook.FALLBACK[key]]
	return ""


func test_a_bad_look_is_refused_with_the_key_named() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubScreenLook.DEFAULT_FILE))
	var cases: Array[Array] = [
		["rows_shown", 2.5, "whole"],
		["focus_seconds", 0.05, "focus_seconds"],
		["row_font_size", true, "row_font_size"],
		["screen_color", [0.1, 0.2], "screen_color"],
	]
	for each: Array in cases:
		var data: Dictionary = shipped.duplicate(true)
		data[each[0]] = each[1]
		var error: String = str(HubScreenLook.parse(JSON.stringify(data)).get("error", ""))
		if not error.contains(each[2]):
			return "%s = %s gives \"%s\"" % [each[0], each[1], error]
	var extra: Dictionary = shipped.duplicate(true)
	extra["glow"] = 1
	if not str(HubScreenLook.parse(JSON.stringify(extra)).get("error", "")).contains("glow"):
		return "an unknown key is not refused"
	return ""


func test_every_word_colour_passes_the_contrast_floor() -> String:
	var look: Dictionary = HubScreenLook.load_file()
	for key: String in TEXT_KEYS:
		var ratio: float = HubScreenMeasure.contrast(look[key], look["screen_color"])
		if ratio < float(look["min_contrast"]):
			return "%s on the screen is %.1f:1, under %s:1" % [key, ratio, look["min_contrast"]]
	if HubScreenMeasure.luminance(look["screen_color"]) > 0.05:
		return "the screen's face is not dark"
	return ""


func test_contrast_arithmetic() -> String:
	var white_black: float = HubScreenMeasure.contrast(Color.WHITE, Color.BLACK)
	if not is_equal_approx(white_black, 21.0):
		return "white on black is %.3f:1, expected 21:1" % white_black
	if not is_equal_approx(HubScreenMeasure.contrast(Color(0.3, 0.5, 0.7), Color(0.3, 0.5, 0.7)), 1.0):
		return "a colour on itself is not 1:1"
	# Mid grey #777777 on white is the textbook 4.48:1.
	var grey: float = HubScreenMeasure.contrast(Color8(0x77, 0x77, 0x77), Color.WHITE)
	if absf(grey - 4.48) > 0.01:
		return "#777 on white is %.3f:1, expected 4.48:1" % grey
	# The old screens: pale text on the bright cyan face (#1359's recording).
	var old: float = HubScreenMeasure.contrast(Color(0.6, 0.7, 0.8), Color(0.2, 0.75, 0.85))
	if old >= 7.0:
		return "the old pale-on-cyan screens would pass at %.1f:1" % old
	return ""


func test_angle_and_pixel_arithmetic() -> String:
	var height: float = HubScreenMeasure.height_for_deg(0.9, 1.4)
	if absf(height - 0.022) > 0.0005:
		return "0.9 deg at 1.4 m is %.4f m, expected about 0.022 m" % height
	if absf(HubScreenMeasure.angle_deg(height, 1.4) - 0.9) > 0.0001:
		return "the angle does not invert the height"
	# 2 m tall at 1 m over a 90 deg field fills the buffer: tan(45) = 1.
	if not is_equal_approx(HubScreenMeasure.pixels(2.0, 1.0, 90.0, 1000.0), 1000.0):
		return "a height filling a 90 deg field is %.1f px of 1000" % HubScreenMeasure.pixels(2.0, 1.0, 90.0, 1000.0)
	var cap: float = HubScreenMeasure.cap_height_m(40.0, 0.0005, 0.7, 2.0)
	if not is_equal_approx(cap, 0.028):
		return "font 40 at 0.5 mm, ratio 0.7, scale 2 is %.4f m, expected 0.028" % cap
	var look: Dictionary = HubScreenLook.load_file()
	var at_least: float = HubScreenMeasure.pixels(HubScreenMeasure.height_for_deg(look["min_text_deg"], 1.4), 1.4,
		look["vertical_fov_deg"], look["eye_height_px"])
	if at_least < float(look["min_text_px"]):
		return "the angle floor gives %.1f px, under the pixel floor %s: the floors disagree" % [at_least,
			look["min_text_px"]]
	return ""


func test_no_screen_outshines_the_room() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	var look: Dictionary = HubScreenLook.load_file()
	var problem: String = CHECK.emission_problem(spec, look)
	if problem != "":
		return "the shipped room: %s" % problem
	var bright: Dictionary = (spec.materials["screen"] as Dictionary).duplicate()
	bright["emission_energy"] = 0.9  # The screens before #1359.
	spec.materials["screen"] = bright
	if CHECK.emission_problem(spec, look) == "":
		return "the old bright screens pass the emission cap"
	return ""
