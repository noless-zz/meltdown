extends RefCounted

## The guide light acceptance checks (#1463, DEV-6, decision record 0005):
## `guide_lights_drawn` passes a lit level and fails an unlit one, reports the
## strips' cost, accepts the stress scene's single room, and the m6 look suite
## flies both guide light steps; `guide_lights_brighter` averages luminance.

const GuideLightsCheck := preload("res://acceptance/checks/guide_lights_check.gd")
const SUITE_FILE: String = "res://acceptance/suites/m6/look.json"


## A narrow tunnel along -z opening into a room at z = -18..-20.
func _tunnel_and_room() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-3, -3, -20), Vector3(3, 3, 0)),
		BoxBounds.new(Vector3(-10, -6, -40), Vector3(10, 6, -18))]
	return BoxUnion.new(boxes)


func test_the_check_passes_a_lit_level_and_fails_an_unlit_one() -> String:
	var view: LevelView = LevelView.new()
	view.build(_tunnel_and_room())
	var measurements: Dictionary = {}
	var verdict: Array = GuideLightsCheck.judge_view(view, measurements)
	var result: String = ""
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		result = "a lit level failed: %s" % verdict[1]
	elif int(measurements["guide_draw_calls"]) != 0 or int(measurements["guide_triangles"]) != view.guide_lights.strips.size() * 2:
		result = "the cost is reported as %s" % measurements
	view.guide_lights = GuideLights.new()
	if result == "" and GuideLightsCheck.judge_view(view, {})[0] != AcceptanceReport.RESULT_FAIL:
		result = "a level without strips passed"
	view.free()
	return result


func test_mean_luminance_of_a_flat_image() -> String:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 0.5))
	var dark: float = GuideLightsCheck.mean_luminance(image)
	image.fill_rect(Rect2i(0, 0, 8, 1), Color(1, 1, 1))
	var lit: float = GuideLightsCheck.mean_luminance(image)
	if absf(dark - 0.5) > 0.01 or lit <= dark:
		return "a grey image reads %.3f and with a white line %.3f" % [dark, lit]
	return ""


func test_the_m6_look_suite_flies_the_guide_lights_steps() -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUITE_FILE))
	var wanted: Dictionary = {"guide_lights": [GuideLightsCheck.CHECK_DRAWN, GuideLightsCheck.CHECK_BRIGHTER],
		"guide_lights_g2": [GuideLightsCheck.CHECK_DRAWN, "final_hash"]}
	for step: Variant in (data as Dictionary)["steps"]:
		var id: String = (step as Dictionary)["id"]
		if not wanted.has(id):
			continue
		for check: String in wanted[id]:
			if not (step["checks"] as Array).has(check):
				return "the %s step lists %s, not %s" % [id, step["checks"], check]
		wanted.erase(id)
	return "" if wanted.is_empty() else "suites/m6/look.json has no %s step" % [wanted.keys()]


func test_a_one_box_level_passes_with_one_kind() -> String:
	var view: LevelView = LevelView.new()
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-15, -8, -15), Vector3(15, 8, 15))]
	view.build(BoxUnion.new(boxes), Vector3.ZERO)
	var verdict: Array = GuideLightsCheck.judge_view(view, {})
	view.free()
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else "the stress scene's one room failed: %s" % verdict[1]
