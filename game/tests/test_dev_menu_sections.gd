extends RefCounted

## The dev menu in sections (#1301, CMF-4, CMF-8, PLT-5, DEV-7): section rows
## and their entries from the data file, open / Back / reopen, a scrolled
## window of at most `max_rows_visible` rows, notes only on the highlighted
## row, every shipped text within `max_row_chars`, and every row still
## reaching its action.

## The grouping the issue asked for, as the shipped file holds it.
const SHIPPED_SECTIONS: Array = [
	["Comfort", ["comfort", "break", "refresh", "swivel", "auto_level", "foveation"]],
	["Controls", ["controls", "hands", "pitch"]],
	["Mine", ["level", "restart", "return", "flight_test"]],
	["Display", ["corner", "map_place", "map_turn"]],
]


static func _shipped() -> DevMenuModel:
	return DevMenuModel.new(DevMenuSpec.load_file(), DevMenuLevels.files())


static func _row_texts(model: DevMenuModel, rows: Array[int]) -> Array[String]:
	var texts: Array[String] = []
	for row: int in rows:
		texts.append(DevMenu.row_text(model, row, false))
	return texts


func test_sections_and_their_entries_come_from_the_data_file() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if spec.error != "" or spec.max_rows_visible != 6 or spec.max_row_chars != 28:
		return "the shipped file: %s, %d rows, %d chars" % [spec.error, spec.max_rows_visible,
			spec.max_row_chars]
	var shipped: Array = []
	for section: Dictionary in spec.sections:
		shipped.append([section["label"], section["kinds"]])
	if str(shipped) != str(SHIPPED_SECTIONS):
		return "the shipped sections are %s" % [shipped]
	var model: DevMenuModel = _shipped()
	model.open("centre", "")
	var top: Array[String] = _row_texts(model, model.rows.rows())
	if top != ["Comfort", "Controls", "Mine", "Display", "Close"]:
		return "the top list without a waiting build is %s" % [top]
	model.set_update("abc1234", false)
	top = _row_texts(model, model.rows.rows())
	if top != ["Comfort", "Controls", "Mine", "Display", "Update to abc1234", "Close"]:
		return "the top list with a waiting build is %s" % [top]
	# A file's own grouping is used as written.
	var text: String = JSON.stringify({"entries": [{"kind": "close", "label": "Done"},
		{"kind": "level", "label": "Fly"}, {"kind": "restart", "label": "Again"}],
		"corners": ["centre"], "sections": [{"label": "Go", "entries": ["restart", "level"]}],
		"back_text": "Up"})
	var own: DevMenuModel = DevMenuModel.new(DevMenuSpec.parse(text), [])
	own.open("centre", "")
	var own_top: Array[String] = _row_texts(own, own.rows.rows())
	DevMenuWalk.tap(own, DevMenuModel.CONFIRM)
	var inside: Array[String] = _row_texts(own, own.rows.rows())
	if own_top != ["Go", "Done"] or inside != ["Up", "Again", "Fly: Test tunnel"]:
		return "a file's own sections show %s, then %s" % [own_top, inside]
	return ""


func test_a_bad_section_list_is_named() -> String:
	var base: Dictionary = {"entries": [{"kind": "close", "label": "Close"},
		{"kind": "level", "label": "Level"}], "corners": ["centre"]}
	var cases: Dictionary = {
		"\"sections\" must be a list": {"sections": {"label": "A"}},
		"exactly \"label\" and \"entries\"": {"sections": [{"label": "A"}]},
		"non-empty label": {"sections": [{"label": " ", "entries": ["level"]}]},
		"non-empty list of entries": {"sections": [{"label": "A", "entries": []}]},
		"which is not an entry": {"sections": [{"label": "A", "entries": ["pitch"]}]},
		"more than one section": {"sections": [{"label": "A", "entries": ["level"]},
			{"label": "B", "entries": ["level"]}]},
		"\"max_rows_visible\" must be": {"max_rows_visible": 0},
		"\"max_row_chars\" must be": {"max_row_chars": 2.5},
		"\"back_text\" must be": {"back_text": ""},
	}
	for expected: String in cases:
		var data: Dictionary = base.duplicate(true)
		data.merge(cases[expected], true)
		var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
		if not spec.error.contains(expected):
			return "expected '%s', got '%s'" % [expected, spec.error]
	return ""


func test_a_opens_a_section_back_and_closing_return_to_the_top_list() -> String:
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), [])
	var model: DevMenuModel = menu.model
	menu.open("centre", "")
	var opened: Array[String] = menu.texts()
	menu.update({DevMenuModel.CONFIRM: true})
	var in_comfort: Array[String] = menu.texts()
	var comfort_kind: String = model.kind()
	menu.update({})
	menu.update({DevMenuModel.UP: true})
	menu.update({})
	var on_back: String = model.kind()
	var back_result: String = menu.update({DevMenuModel.CONFIRM: true})
	menu.update({})
	var after_back: Array[String] = menu.texts()
	DevMenuWalk.select(model, DevMenuSpec.KIND_HANDS)
	menu.close()
	var closed_section: int = model.rows.section
	DevMenuWalk.select(model, DevMenuSpec.KIND_LEVEL)
	menu.open("centre", "")
	var reopened: Array[String] = menu.texts()
	menu.free()
	if opened != ["> Comfort", "Controls", "Mine", "Display", "Close"]:
		return "the menu opened on %s" % [opened]
	if in_comfort.size() != 6 or in_comfort[0] != "Back" or comfort_kind != DevMenuSpec.KIND_COMFORT \
			or not in_comfort[1].begins_with("> Comfort: <"):
		return "A on Comfort showed %s, highlighting %s" % [in_comfort, comfort_kind]
	if on_back != DevMenuModel.KIND_BACK or back_result != "" or after_back != opened:
		return "Back (%s) returned '%s' and showed %s" % [on_back, back_result, after_back]
	if closed_section != DevMenuRows.TOP or reopened != opened:
		return "closing left section %d; reopening showed %s" % [closed_section, reopened]
	return ""


func test_at_most_max_rows_show_and_the_highlight_stays_on_screen() -> String:
	# The built-in menu has no sections: every entry on one list.
	var menu: DevMenu = DevMenu.new(DevMenuSpec.fallback(), [])
	var model: DevMenuModel = menu.model
	model.set_run(true)
	model.checklist_shown = true  # A development build with a checklist (#1325).
	menu.set_update("abc1234", false)
	menu.open("centre", "")
	var problem: String = ""
	var count: int = model.rows.rows().size()
	for step: int in count * 2 + 3:
		var action: String = DevMenuModel.DOWN if step <= count else DevMenuModel.UP
		menu.update({action: true})
		menu.update({})
		var shown: Array[String] = menu.texts()
		var marked: int = 0
		for line: String in shown:
			marked += 1 if line.begins_with("> ") else 0
		if shown.size() != model.spec.max_rows_visible or marked != 1 \
				or not model.rows.visible_rows().has(model.selected):
			problem = "step %d (%s) shows %s" % [step, action, shown]
			break
	menu.free()
	if count != DevMenuSpec.KINDS.size():
		return "the built-in list has %d rows" % count
	return problem


func test_notes_show_only_on_the_highlighted_row() -> String:
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), [])
	var model: DevMenuModel = menu.model
	menu.open("centre", "")
	model.set_refresh(false, false)
	model.set_swivel(true, true)
	model.values.auto_level.noted = true
	var notes: Dictionary = {DevMenuSpec.KIND_REFRESH: model.spec.refresh_note_text,
		DevMenuSpec.KIND_SWIVEL: model.spec.swivel_custom_text,
		DevMenuSpec.KIND_AUTO_LEVEL: model.spec.auto_level_preset_text,
		DevMenuSpec.KIND_FOVEATION: model.spec.foveation_note_text}
	var problem: String = ""
	for kind: String in notes:
		DevMenuWalk.select(model, kind)
		menu.update({})
		for line: String in menu.texts():
			var chosen: bool = line.begins_with("> ")
			for other: String in notes:
				var label: String = DevMenuWalk.entry_line(model, other).get_slice(":", 0)
				if not line.trim_prefix("> ").begins_with(label + ":"):
					continue
				var noted: bool = line.contains(notes[other])
				if noted != (chosen and other == kind):
					problem = "with %s highlighted the line reads \"%s\"" % [kind, line]
		if problem != "":
			break
	menu.free()
	return problem


func test_every_shipped_label_and_its_longest_value_fit() -> String:
	var model: DevMenuModel = _shipped()
	var spec: DevMenuSpec = model.spec
	var limit: int = spec.max_row_chars
	var version: String = "a".repeat(BuildInfo.SHORT_LENGTH)
	var texts: Array[String] = [spec.back_text, spec.confirm_return_text,
		spec.cancel_update_text.replace("{version}", version)]
	for section: Dictionary in spec.sections:
		texts.append(str(section["label"]))
	var values: Dictionary = {
		DevMenuSpec.KIND_CORNER: spec.corners, DevMenuSpec.KIND_CONTROLS: spec.schemes,
		DevMenuSpec.KIND_HANDS: [spec.right_handed_text, spec.left_handed_text],
		DevMenuSpec.KIND_PITCH: [spec.normal_pitch_text, spec.inverted_pitch_text],
		DevMenuSpec.KIND_COMFORT: model.values.comfort.preset_names + [spec.custom_text.replace("{base}", "4")],
		DevMenuSpec.KIND_BREAK: [spec.break_on_text, spec.break_off_text],
		DevMenuSpec.KIND_REFRESH: [spec.refresh_90_text, spec.refresh_120_text],
		DevMenuSpec.KIND_SWIVEL: [spec.swivel_on_text, spec.swivel_off_text],
		DevMenuSpec.KIND_AUTO_LEVEL: [spec.auto_level_on_text, spec.auto_level_off_text],
		DevMenuSpec.KIND_LEVEL: [spec.tunnel_text, spec.random_text,
			spec.seed_text.replace("{seed}", str(DevMenuLevels.SEED_MAX))],
		DevMenuSpec.KIND_FOVEATION: [],
	}
	for path: String in model.levels.choices:
		if path.begins_with("res://"):
			(values[DevMenuSpec.KIND_LEVEL] as Array).append(
				path.get_file().trim_suffix(LevelSwitch.LEVEL_SUFFIX).to_upper())
	for setting: Vector2i in FoveationSwitch.MENU_STEPS:
		model.values.foveation.setting = setting
		(values[DevMenuSpec.KIND_FOVEATION] as Array).append(model.values.foveation.plain_text())
	for entry: Dictionary in spec.entries:
		var label: String = str(entry["label"]).replace("{version}", version)
		if not values.has(entry["kind"]):
			texts.append(label)
			continue
		for value: Variant in values[entry["kind"]]:
			texts.append("%s: %s" % [label, value])
	var long: Array[String] = []
	for text: String in texts:
		if text.length() > limit:
			long.append("%s (%d)" % [text, text.length()])
	return "" if long.is_empty() else "over %d characters: %s" % [limit, ", ".join(long)]


func test_every_row_still_reaches_its_action() -> String:
	# Value rows confirm their value with its prefix; the rest their action.
	var expected: Dictionary = {
		DevMenuSpec.KIND_LEVEL: "level:", DevMenuSpec.KIND_RESTART: DevMenuModel.RESTART,
		DevMenuSpec.KIND_FLIGHT_TEST: DevMenuModel.FLIGHT_TEST, DevMenuSpec.KIND_UPDATE: DevMenuModel.UPDATE,
		DevMenuSpec.KIND_RETURN: DevMenuModel.RETURN, DevMenuSpec.KIND_CLOSE: DevMenuModel.CLOSE,
		DevMenuSpec.KIND_CHECKLIST: DevMenuModel.CHECKLIST,
	}
	var model: DevMenuModel = _shipped()
	model.open("centre", "")
	model.set_run(true)
	model.checklist_shown = true
	model.set_update("abc1234", false)
	for entry: Dictionary in model.spec.entries:
		var kind: String = str(entry["kind"])
		if not DevMenuWalk.select(model, kind):
			return "the walk never reached %s" % kind
		var helper: DevMenuValue = model.value(kind)
		if helper != null and kind != DevMenuSpec.KIND_LEVEL:
			expected[kind] = helper.confirmed()
			if not str(expected[kind]).contains(":"):
				return "%s confirms '%s', not a prefixed value" % [kind, expected[kind]]
		var result: String = DevMenuWalk.tap(model, DevMenuModel.CONFIRM)
		if kind == DevMenuSpec.KIND_RETURN:
			result = DevMenuWalk.tap(model, DevMenuModel.CONFIRM)  # The two-press confirm.
		if result != str(expected.get(kind, "?")):
			return "confirming %s gave '%s'" % [kind, result]
	return ""
