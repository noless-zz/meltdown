extends RefCounted

## The status panel's swivel tag (#792, CMF-7, CMF-1, CMF-3, ARC-3, ARC-4):
## a short tag from the look file after the preset's name while the active
## preset has swivel-chair mode on, nothing on presets 1 to 4, and a label
## that never moves when the tag comes or goes.

const FRAME: float = 1.0 / 90.0


## A comfort wiring flying shipped preset `number`, with swivel on when `on`.
static func _comfort(number: int, on: bool) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.set_preset(number)
	if on:
		var preset: ComfortPreset = comfort.preset.duplicate() as ComfortPreset
		preset.swivel_enabled = true
		comfort.preset = preset
	return comfort


## The small and large preset labels after one frame for `comfort`.
static func _shown(panel: StatusPanel, comfort: ComfortWiring) -> Array[String]:
	RigViews.show_swivel(panel, comfort)
	RigViews.show_ship(panel, ShipState.new(), comfort.number, comfort.preset.display_name, "", FRAME)
	var texts: Dictionary = panel.texts()
	return [str(texts[StatusPanel.PRESET_NAME]), str(texts[StatusPanel.PRESET_LARGE_NAME])]


func test_presets_one_to_four_show_no_tag() -> String:
	for number: int in [1, 2, 3, 4]:
		var panel: StatusPanel = StatusPanel.new()
		var comfort: ComfortWiring = _comfort(number, false)
		var shown: Array[String] = _shown(panel, comfort)
		panel.free()
		var expected: String = "Preset %d %s" % [number, comfort.preset.display_name]
		if shown != [expected, expected]:
			return "preset %d shows %s, expected \"%s\"" % [number, str(shown), expected]
	return ""


func test_a_swivel_on_preset_tags_the_name() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var comfort: ComfortWiring = _comfort(3, true)
	var shown: Array[String] = _shown(panel, comfort)
	panel.free()
	var expected: String = "Preset 3 %s Swivel" % comfort.preset.display_name
	if shown != [expected, expected]:
		return "swivel-on preset shows %s, expected \"%s\"" % [str(shown), expected]
	return ""


func test_the_tag_goes_with_the_preset_and_the_label_stays_put() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var small: Label3D = panel.get_node(StatusPanel.PRESET_NAME) as Label3D
	var at: Transform3D = small.transform
	var on: Array[String] = _shown(panel, _comfort(3, true))
	var off: Array[String] = _shown(panel, _comfort(3, false))
	var moved: bool = small.transform != at
	panel.free()
	if not on[0].ends_with(" Swivel") or off[0].ends_with(" Swivel"):
		return "tag did not follow the preset: on \"%s\", off \"%s\"" % [on[0], off[0]]
	if moved:
		return "the preset label moved when the tag changed"
	return ""


func test_the_tag_text_is_read_from_the_look() -> String:
	var shipped: Dictionary = StatusPanelLook.load_file()
	if shipped.has("error"):
		return "the shipped look was rejected: %s" % shipped["error"]
	if shipped["preset_swivel_text"] != "Swivel":
		return "the shipped look's tag is \"%s\"" % shipped["preset_swivel_text"]
	var text: String = FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE)
	var data: Dictionary = JSON.parse_string(text)
	data["preset_swivel_text"] = "Chair"
	var look: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
	if look.has("error"):
		return "a look with another tag was rejected: %s" % look["error"]
	var holder: Node3D = Node3D.new()
	var row: StatusPanelPresetRow = StatusPanelPresetRow.new(holder, look)
	row.add_large(holder)
	row.show_swivel(true)
	row.show(3, "Pilot", "")
	var small: String = (holder.get_node(StatusPanel.PRESET_NAME) as Label3D).text
	holder.free()
	if small != "Preset 3 Pilot Chair":
		return "the row read \"%s\", not the look's tag" % small
	var source: String = FileAccess.get_file_as_string("res://xr/status_panel_preset_row.gd")
	if source.contains("\"Swivel\""):
		return "status_panel_preset_row.gd writes the tag in code"
	return ""


func test_the_look_rejects_an_empty_or_non_text_tag() -> String:
	var text: String = FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE)
	for bad: Variant in ["  ", 3, true]:
		var data: Dictionary = JSON.parse_string(text)
		data["preset_swivel_text"] = bad
		var look: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
		if not str(look.get("error", "")).contains("preset_swivel_text"):
			return "tag %s accepted or not named: %s" % [str(bad), str(look)]
	return ""
