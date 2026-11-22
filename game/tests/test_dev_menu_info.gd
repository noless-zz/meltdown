extends RefCounted

## The dev menu's read-only Info section (#1207): the development lines the
## status panel no longer draws in flight, read from the panel's own rows so
## they say exactly what the panel used to say, refreshed while the menu is open.

const BUILD: String = "1a2b3c4, built 2026-11-22 10:00 UTC"


## A rig holding a status panel and an open dev menu with its Info section.
static func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	var panel: StatusPanel = StatusPanel.new()
	rig.add_child(panel)
	panel.show_values(3, "Pilot", 19.6, StatusPanel.BOOST_ON, BUILD)
	panel.show_level("31", "")
	var menu: DevMenu = DevMenu.new()
	rig.add_child(menu)
	var info: DevMenuInfo = DevMenuInfo.new()
	info.source = rig
	menu.add_child(info)
	menu.open("bottom_left", "")
	info.refresh()
	return rig


static func _info(rig: Node3D) -> DevMenuInfo:
	return rig.get_node(DevMenu.NODE_NAME).get_node(DevMenuInfo.NODE_NAME) as DevMenuInfo


static func _panel(rig: Node3D) -> StatusPanel:
	return rig.get_node(StatusPanel.NODE_NAME) as StatusPanel


func test_each_moved_line_is_on_the_info_page_as_the_panel_showed_it() -> String:
	var rig: Node3D = _rig()
	var shown: Array[String] = _info(rig).texts()
	var panel: Dictionary = _panel(rig).texts()
	rig.free()
	var expected: Array[String] = ["Info",
		"%s %s" % [panel[StatusPanel.SPEED_NAME], panel[StatusPanel.BOOST_NAME]],
		panel[StatusPanel.PRESET_NAME], panel[StatusPanel.LEVEL_NAME], panel[StatusPanel.BUILD_NAME]]
	if shown != expected:
		return "the Info page reads %s, the panel's rows %s" % [shown, expected]
	var words: Array[String] = ["Info", "Speed 20 m/s BOOST", "Preset 3 Pilot", "Seed 31", BUILD]
	if shown != words:
		return "the Info page reads %s, expected %s" % [shown, words]
	return ""


func test_the_info_page_follows_the_values_while_the_menu_is_open() -> String:
	var rig: Node3D = _rig()
	var panel: StatusPanel = _panel(rig)
	panel.show_values(3, "Pilot", 4.2, "", BUILD)
	panel.show_level("", "")
	_info(rig).refresh()
	var shown: Array[String] = _info(rig).texts()
	rig.free()
	if shown.size() < 4 or shown[1] != "Speed 4 m/s" or shown[3] != "Test tunnel":
		return "after new values the Info page reads %s" % [shown]
	return ""


func test_the_info_page_sits_under_the_entries_and_cannot_be_chosen() -> String:
	var rig: Node3D = _rig()
	var menu: DevMenu = rig.get_node(DevMenu.NODE_NAME) as DevMenu
	var entries: Array[String] = menu.texts()
	var lowest: float = INF
	var depth: float = 0.0
	for child: Node in menu.get_children():
		if child is Label3D and (child as Label3D).visible and (child as Label3D).position.y < lowest:
			lowest = (child as Label3D).position.y
			depth = (child as Label3D).position.z
	var title: Label3D = _info(rig).get_node(DevMenuInfo.TITLE_NAME) as Label3D
	var at: Vector3 = title.position
	rig.free()
	if at.y >= lowest:
		return "the Info heading at %.3f is not under the lowest entry at %.3f" % [at.y, lowest]
	if not is_equal_approx(at.z, depth):
		return "the Info heading is %.3f deep, the entries %.3f" % [at.z, depth]
	for text: String in entries:
		if text.contains("Speed") or text.contains(BUILD):
			return "an Info line became a menu entry: %s" % text
	return ""


func test_no_panel_shows_only_the_heading() -> String:
	var info: DevMenuInfo = DevMenuInfo.new("Notes")
	info.refresh()
	var shown: Array[String] = info.texts()
	info.free()
	if shown != ["Notes"]:
		return "without a panel the Info page reads %s" % [shown]
	return ""


func test_the_wiring_hangs_the_info_page_under_the_menu() -> String:
	var rig: Node3D = Node3D.new()
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.attach(rig, null, null, Callable(), null, null, DevMenu.new())
	var parent: Node = wiring.info.get_parent() if wiring.info != null else null
	var source: Node3D = wiring.info.source if wiring.info != null else null
	var title: String = wiring.info.texts()[0] if wiring.info != null else ""
	var is_menu: bool = parent == wiring.menu
	rig.free()
	if not is_menu:
		return "the Info section is not under the menu"
	if source != rig:
		return "the Info section does not read the rig's panel"
	if title != DevMenuSpec.load_file().info_title_text:
		return "the heading reads %s" % title
	return ""


func test_the_menu_file_names_the_heading() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE))
	if str(DevMenuSpec.load_file().info_title_text) != str(data.get("info_title_text", "")):
		return "the shipped heading is not read from the file"
	data["info_title_text"] = "Notes"
	var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	if spec.error != "" or spec.info_title_text != "Notes":
		return "a heading of Notes gives '%s' (%s)" % [spec.info_title_text, spec.error]
	data["info_title_text"] = " "
	spec = DevMenuSpec.parse(JSON.stringify(data))
	if not spec.error.contains("info_title_text"):
		return "a blank heading gives '%s'" % spec.error
	return ""
