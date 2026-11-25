extends RefCounted

## Drawing the home base's icons (#1365, CRW-2, CRF-3, GFX-2, ARC-3, DEV-6):
## an icon is its file's parts as unshaded flat meshes within its size, the
## icon-and-count widget shows "have" or "have/need" coloured short while have
## is under need, the sheet draws the whole set inside the screen it is given,
## and the `hub_icons` acceptance step is in the m6 base suite. No icon code
## reads a comfort setting or writes simulation state.

const SUITE_PATH: String = "res://acceptance/suites/m6/base.json"
const ICON_FILES: Array[String] = ["res://xr/hub_icons.gd", "res://xr/hub_icon_parts.gd", "res://xr/hub_icon.gd",
	"res://xr/hub_icon_count.gd", "res://xr/hub_icon_sheet.gd"]
const SCREEN_W_M: float = 0.36
const SCREEN_H_M: float = 0.24


func test_an_icon_draws_its_parts_flat_and_unshaded_within_its_size() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var data: Dictionary = icons.icon("weapon", "quill_battery")
	var size: float = icons.numbers["size_m"]
	var icon: HubIcon = HubIcon.new(data, size, 4)
	var result: String = ""
	if icon.part_count() != (data["parts"] as Array).size():
		result = "drew %d of %d parts" % [icon.part_count(), (data["parts"] as Array).size()]
	for child: Node in icon.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if result == "" and (material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or mesh.layers != 4):
			result = "%s is shaded or on layers %d" % [mesh.name, mesh.layers]
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		if result == "" and (absf(box.position.x) > size * 0.6 or absf(box.end.y) > size * 0.6 or box.size.z > 0.005):
			result = "%s spans %s, outside a %s m icon or not flat" % [mesh.name, box, size]
	if result == "" and icon.part_colors()[0] != data["color"]:
		result = "the first part is not in the icon's colour"
	icon.free()
	return result


func test_every_shape_lies_flat_facing_the_pilot() -> String:
	var shapes: Array[String] = ["rect", "disc", "ring", "tri"]
	for shape: String in shapes:
		var icon: HubIcon = HubIcon.new({"color": Color.WHITE, "parts": [{"shape": shape, "size": Vector2(0.8, 0.4),
			"at": Vector2.ZERO, "turn_deg": 0.0, "color": Color.WHITE}]}, 0.1)
		var mesh: MeshInstance3D = icon.get_child(0) as MeshInstance3D
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		icon.free()
		if not is_equal_approx(box.size.x, 0.08) or not is_equal_approx(box.size.y, 0.04) or box.size.z > 0.002:
			return "a %s 0.8 x 0.4 of 0.1 m spans %s" % [shape, box.size]
	return ""


func test_the_count_widget_shows_have_and_need() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var widget: HubIconCount = HubIconCount.new(icons, "component", "core_glass")
	var result: String = ""
	if widget.count_text() != "" or widget.icon.part_count() == 0:
		result = "a new widget shows \"%s\" and %d parts" % [widget.count_text(), widget.icon.part_count()]
	widget.show_count(3, 5)
	if result == "" and (widget.count_text() != "3/5" or widget.count_color() != icons.colors["short_color"]):
		result = "3 of 5 shows \"%s\" in %s" % [widget.count_text(), widget.count_color()]
	widget.show_count(5, 5)
	if result == "" and widget.count_color() != icons.colors["count_color"]:
		result = "5 of 5 is still coloured short"
	widget.show_count(7)
	if result == "" and (widget.count_text() != "7" or widget.count_color() != icons.colors["count_color"]):
		result = "a held count shows \"%s\"" % widget.count_text()
	widget.hide_count()
	if result == "" and widget.count_text() != "":
		result = "a hidden count still shows"
	widget.free()
	return result


func test_the_count_widget_for_an_unknown_id_draws_the_marker() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var widget: HubIconCount = HubIconCount.new(icons, "component", "moon_dust")
	var parts: int = widget.icon.part_count()
	widget.free()
	if parts != (icons.fallback["parts"] as Array).size() or icons.fell_back != ["component/moon_dust"]:
		return "an unknown component drew %d parts, fell back %s" % [parts, icons.fell_back]
	return ""


func test_the_sheet_draws_the_whole_set_inside_the_screen() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var total: int = 0
	for group: String in HubIcons.GROUPS:
		total += icons.ids(group).size()
	var sheet: HubIconSheet = HubIconSheet.new(icons, SCREEN_W_M, SCREEN_H_M)
	var drawn: int = sheet.icon_count()
	var covered: Vector2 = sheet.covered_m(icons)
	sheet.free()
	if drawn != total or not icons.fell_back.is_empty():
		return "the sheet drew %d of %d icons, fell back %s" % [drawn, total, icons.fell_back]
	if covered.x > SCREEN_W_M + 0.0001 or covered.y > SCREEN_H_M + 0.0001:
		return "the sheet covers %s, past the screen" % covered
	return ""


func test_the_check_counts_the_sheet() -> String:
	var check: GDScript = load("res://acceptance/checks/hub_icons_check.gd") as GDScript
	var none: Array[String] = []
	if check.call("sheet_count_problem", 30, 30, none) != "":
		return "a full sheet failed"
	if check.call("sheet_count_problem", 30, 29, none) == "":
		return "a short sheet passed"
	var fell: Array[String] = ["weapon/x"]
	if check.call("sheet_count_problem", 30, 30, fell) == "":
		return "a sheet with a fallback passed"
	return ""


func test_the_acceptance_step_is_in_the_m6_base_suite() -> String:
	if not AcceptanceCheckFiles.known_checks().has("hub_icons"):
		return "the hub_icons check is not registered: %s" % AcceptanceCheckFiles.problem()
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return "m6 did not load: %s" % [suites[0].error if suites.size() == 1 else suites.size()]
	if not FileAccess.get_file_as_string(SUITE_PATH).contains("\"hub_icons\""):
		return "%s has no hub_icons step" % SUITE_PATH
	for step: AcceptanceStep in suites[0].steps:
		if step.id == "hub_icons":
			return "" if step.checks.has("hub_icons") and step.checks.has(AcceptanceStep.CHECK_NO_SCRIPT_ERRORS) \
				else "the step checks %s" % [step.checks]
	return "the m6 suite has no hub_icons step"


func test_icon_code_reads_no_comfort_and_writes_no_simulation() -> String:
	for path: String in ICON_FILES:
		var text: String = FileAccess.get_file_as_string(path)
		for word: String in ["Comfort", "comfort", "Sim.", "LocalSession", "ShipState"]:
			if text.contains(word):
				return "%s names %s" % [path, word]
	return ""
