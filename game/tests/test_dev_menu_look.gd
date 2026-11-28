extends RefCounted

## The dev menu drawn with icons and values (#1458, record 0012, CRW-2, PLT-5,
## ARC-3, ARC-4): every row names an icon the base's set draws, every value
## kind maps to a drawing, words show on the highlighted row only (and beside a
## bar), the plate holds the base's readability thresholds (#1359), and the
## drawing changes nothing the menu does.


static func _menu() -> DevMenu:
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), DevMenuLevels.files())
	menu.open("centre", "")
	return menu


func test_every_row_names_an_icon_the_base_set_draws() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var icons: HubIcons = HubIcons.load_file()
	if spec.error != "" or icons.error != "":
		return "the files were refused: %s %s" % [spec.error, icons.error]
	var rows: Array[int] = [DevMenuRows.BACK]
	for index: int in spec.sections.size():
		rows.append(DevMenuRows.section_row(index))
	for index: int in spec.entries.size():
		rows.append(index)
	for row: int in rows:
		var named: String = DevMenuIcons.name_for(spec, row)
		var parts: PackedStringArray = named.split("/")
		if named == "" or parts.size() != 2 or not icons.has_icon(parts[0], parts[1]):
			return "row %d (%s) names icon \"%s\", which the set does not draw" % [row,
				DevMenu.row_text(DevMenuModel.new(spec, []), row, false), named]
	return ""


func test_every_value_kind_maps_to_a_drawing() -> String:
	var menu: DevMenu = _menu()
	var model: DevMenuModel = menu.model
	var expected: Dictionary = {DevMenuSpec.KIND_BREAK: DevMenuValue.DRAW_SWITCH,
		DevMenuSpec.KIND_SWIVEL: DevMenuValue.DRAW_SWITCH, DevMenuSpec.KIND_CORNER: DevMenuValue.DRAW_MARKS,
		DevMenuSpec.KIND_COMFORT: DevMenuValue.DRAW_MARKS, DevMenuSpec.KIND_RENDER_SCALE: DevMenuValue.DRAW_BAR}
	var problem: String = ""
	for kind: String in DevMenuSpec.KINDS:
		var helper: DevMenuValue = model.value(kind)
		if helper == null:
			continue
		var drawn: DevMenuValueDrawing = DevMenuValueDrawing.new()
		drawn.show_value(helper)
		var parts: int = drawn.part_count()
		drawn.free()
		if not DevMenuValue.DRAWINGS.has(helper.drawing()) or parts == 0:
			problem = "%s draws \"%s\" in %d parts" % [kind, helper.drawing(), parts]
		elif expected.has(kind) and expected[kind] != helper.drawing():
			problem = "%s is drawn as %s, expected %s" % [kind, helper.drawing(), expected[kind]]
		if problem != "":
			break
	menu.free()
	return problem


func test_a_switch_shows_its_state_and_marks_light_the_choice() -> String:
	var toggle: DevMenuValueToggle = DevMenuValueToggle.new("break:", "on", "off", "On", "Off")
	var drawn: DevMenuValueDrawing = DevMenuValueDrawing.new()
	drawn.show_value(toggle)
	var off_x: float = (drawn.get_node("Knob") as Node3D).position.x
	toggle.on = true
	drawn.show_value(toggle)
	var knob: MeshInstance3D = drawn.get_node("Knob") as MeshInstance3D
	var on_x: float = knob.position.x
	var lit: Color = (knob.material_override as StandardMaterial3D).albedo_color
	var list: DevMenuValueList = DevMenuValueList.new("corner:", ["a", "b", "c"] as Array[String])
	list.index = 2
	drawn.show_value(list)
	var marks: int = drawn.part_count()
	var third: Color = ((drawn.get_node("Mark2") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	var first: Color = ((drawn.get_node("Mark0") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	drawn.free()
	if on_x <= off_x or lit != DevMenuLook.LIT_COLOR:
		return "the knob sits at %.3f off and %.3f on, lit %s" % [off_x, on_x, lit]
	if marks != 3 or third != DevMenuLook.LIT_COLOR or first != DevMenuLook.DIM_COLOR:
		return "a list of three on its third drew %d marks, lit %s, dim %s" % [marks, third, first]
	return ""


func test_words_show_on_the_highlighted_row_and_beside_a_bar() -> String:
	var menu: DevMenu = _menu()
	DevMenuWalk.select(menu.model, DevMenuSpec.KIND_MAP_PLACE)
	menu.update({})
	var shown: Array[String] = menu.texts()
	var rows: Array[DevMenuRow] = menu.shown_rows()
	var drawn: int = 0
	for row: DevMenuRow in rows:
		drawn += 1 if row.drawing.part_count() > 0 else 0
	menu.free()
	var expected: Array[String] = ["Back", "Panel corner", "> Map place: < hand >", "Map turn",
		"Render scale: 100%"]
	if shown != expected:
		return "the Display section shows %s, expected %s" % [shown, expected]
	if rows.size() != 5 or drawn != 4:
		return "%d of %d rows drew their value" % [drawn, rows.size()]
	return ""


func test_each_shown_row_draws_its_icon() -> String:
	var menu: DevMenu = _menu()
	var problem: String = ""
	for row: DevMenuRow in menu.shown_rows():
		if row.icon == null or row.icon.part_count() == 0:
			problem = "row %s draws no icon (%s)" % [row.name, row.icon_name]
			break
		for part: Node in row.icon.get_children():
			var material: StandardMaterial3D = (part as MeshInstance3D).material_override as StandardMaterial3D
			if not material.no_depth_test or material.render_priority >= DevMenu.RENDER_PRIORITY:
				problem = "row %s's icon is depth tested or drawn over the words" % row.name
	if not menu.icons.fell_back.is_empty():
		problem = "the menu fell back for %s" % [menu.icons.fell_back]
	menu.free()
	return problem


func test_the_plate_holds_the_bases_readability_thresholds() -> String:
	var look: Dictionary = HubScreenLook.load_file()
	var icons: HubIcons = HubIcons.load_file()
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if not DevMenuLook.PLATE_COLOR.is_equal_approx(look["screen_color"]):
		return "the plate %s is not the screens' face %s" % [DevMenuLook.PLATE_COLOR, look["screen_color"]]
	var plate: Color = DevMenuLook.PLATE_COLOR
	var least: float = maxf(float(look["min_contrast"]), DevMenuLook.MIN_TEXT_CONTRAST)
	for color: Color in [DevMenu.TEXT_COLOR, DevMenu.SELECTED_COLOR, DevMenuInfo.TEXT_COLOR,
			DevMenuInfo.TITLE_COLOR, DevMenuLook.LIT_COLOR]:
		if HubScreenMeasure.contrast(color, plate) < least:
			return "%s is %.1f:1 on the plate" % [color, HubScreenMeasure.contrast(color, plate)]
	var shapes: Array[Color] = [DevMenuLook.DIM_COLOR, DevMenuLook.ON_TRACK_COLOR, DevMenuLook.OFF_KNOB_COLOR]
	for id: String in icons.ids("menu"):
		shapes.append(icons.icon("menu", id)["color"])
	for color: Color in shapes:
		if HubScreenMeasure.contrast(color, plate) < DevMenuLook.MIN_SHAPE_CONTRAST:
			return "%s is %.1f:1 on the plate" % [color, HubScreenMeasure.contrast(color, plate)]
	var ratio: float = float(look["cap_height_ratio"])
	for font: int in [DevMenu.FONT, DevMenuInfo.FONT]:
		var degrees: float = HubScreenMeasure.angle_deg(
			HubScreenMeasure.cap_height_m(font, DevMenu.PIXEL_SIZE, ratio), spec.distance_m)
		if degrees < float(look["min_text_deg"]):
			return "a %d px line stands %.2f degrees" % [font, degrees]
	if HubScreenMeasure.angle_deg(DevMenuLook.ICON_M, spec.distance_m) < float(look["min_text_deg"]):
		return "an icon is smaller than a word"
	return ""


func test_the_drawing_changes_nothing_the_menu_does() -> String:
	var menu: DevMenu = _menu()
	var bare: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), DevMenuLevels.files())
	bare.open("centre", "")
	var presses: Array[Dictionary] = [{DevMenuModel.CONFIRM: true}, {DevMenuModel.DOWN: true},
		{DevMenuModel.RIGHT: true}, {DevMenuModel.CONFIRM: true}, {DevMenuModel.UP: true},
		{DevMenuModel.UP: true}, {DevMenuModel.CONFIRM: true}, {DevMenuModel.DOWN: true},
		{DevMenuModel.DOWN: true}, {DevMenuModel.CONFIRM: true}, {DevMenuModel.RIGHT: true},
		{DevMenuModel.CONFIRM: true}]
	var problem: String = ""
	for held: Dictionary in presses:
		for frame: Dictionary in [held, {}]:
			var drawn: String = menu.update(frame)
			var plain: String = bare.press(frame)
			if drawn != plain or menu.model.selected != bare.selected or menu.model.rows.section != bare.rows.section:
				problem = "after %s the drawn menu gave \"%s\" on %d, the bare model \"%s\" on %d" % [
					held, drawn, menu.model.selected, plain, bare.selected]
		if problem != "":
			break
	menu.free()
	return problem


func test_a_bad_icons_block_is_named() -> String:
	var base: Dictionary = {"entries": [{"kind": "close", "label": "Done"}], "corners": ["centre"],
		"sections": [{"label": "Go", "entries": ["close"]}]}
	for case: Array in [[{"nope": {}}, "unknown key"], [{"back": "menu"}, "icons.back"],
			[{"entries": {"level": "menu/level"}}, "does not list"],
			[{"sections": {"Stop": "menu/back"}}, "does not list"],
			[{"entries": {"close": 3}}, "icons.entries.close"]]:
		var data: Dictionary = base.duplicate(true)
		data["icons"] = case[0]
		var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
		if not spec.error.contains(case[1]):
			return "%s gave \"%s\"" % [case[0], spec.error]
	var good: Dictionary = base.duplicate(true)
	good["icons"] = {"back": "menu/back", "sections": {"Go": "menu/level"}, "entries": {"close": "menu/close"}}
	var read: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(good))
	if read.error != "" or DevMenuIcons.name_for(read, DevMenuRows.section_row(0)) != "menu/level" \
			or DevMenuIcons.name_for(read, 0) != "menu/close":
		return "a good block gave %s: %s" % [read.icons, read.error]
	return ""
