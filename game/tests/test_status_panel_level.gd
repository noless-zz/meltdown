extends RefCounted

## The status panel's level row (#747, DEV-6, GEN-1, ARC-3, ARC-4): it names
## the seed, the level file or the test tunnel, follows a `--seed=random`
## pick, is set only on a change, is smaller and dimmer than the hull row, and
## reads "Seed 31" in the real main scene flying seed 31.

const FRAME: float = 1.0 / 90.0
const G2_FILE: String = "res://data/levels/g2_level.json"


## The panel after one frame of values for a launch flying `source`.
static func _shown(source: String) -> String:
	var panel: StatusPanel = StatusPanel.new()
	RigViews.show_ship(panel, ShipState.new(), 2, "Guided", "", FRAME, source)
	var text: String = panel.texts()[StatusPanel.LEVEL_NAME]
	panel.free()
	return text


static func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


func test_seed_level_file_and_tunnel_are_named() -> String:
	var cases: Dictionary = {"seed:31": "Seed 31", G2_FILE: "G2", "": "Test tunnel"}
	for source: String in cases:
		var text: String = _shown(source)
		if text != cases[source]:
			return "%s shows \"%s\", expected \"%s\"" % [source, text, cases[source]]
	return ""


func test_an_unwired_panel_names_the_tunnel_not_a_blank() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var text: String = panel.texts()[StatusPanel.LEVEL_NAME]
	panel.free()
	return "" if text == "Test tunnel" else "an unwired panel's level row reads \"%s\"" % text


func test_a_random_seed_shows_the_number_picked() -> String:
	var source: String = LevelSwitch.requested_source(PackedStringArray(["--seed=random"]), "", "",
		func() -> int: return 4242)
	if source != "seed:4242":
		return "the random pick gave the source %s" % source
	var text: String = _shown(source)
	return "" if text == "Seed 4242" else "a random pick of 4242 shows \"%s\"" % text


func test_the_text_is_set_once_per_change_not_every_frame() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var ship: ShipState = ShipState.new()
	for i: int in 30:
		RigViews.show_ship(panel, ship, 2, "Guided", "", FRAME, "seed:31")
	var after_seed: int = panel.level_text_changes
	for i: int in 30:
		RigViews.show_ship(panel, ship, 2, "Guided", "", FRAME, G2_FILE)
	var after_level: int = panel.level_text_changes
	for i: int in 30:
		RigViews.show_ship(panel, ship, 2, "Guided", "", FRAME, "")
	var after_tunnel: int = panel.level_text_changes
	panel.free()
	if after_seed != 1 or after_level != 2 or after_tunnel != 3:
		return "text changes %d, %d, %d over three sources of 30 frames each, expected 1, 2, 3" \
			% [after_seed, after_level, after_tunnel]
	return ""


func test_smaller_and_dimmer_than_the_hull_row_and_still() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var level: Label3D = panel.get_node(StatusPanel.LEVEL_NAME) as Label3D
	var hull: Label3D = panel.get_node(StatusPanel.HULL_LABEL_NAME) as Label3D
	var look: Dictionary = StatusPanelLook.load_file()
	var at: Vector3 = level.position
	RigViews.show_ship(panel, ShipState.new(), 2, "Guided", "", FRAME, "seed:31")
	panel.advance(5.0)
	var moved: bool = level.position != at
	var font: int = level.font_size
	var color: Color = level.modulate
	var hull_font: int = hull.font_size
	var hull_color: Color = hull.modulate
	panel.free()
	if font != int(look["level_font"]) or not color.is_equal_approx(look["level_color"]):
		return "the row does not take its size and colour from the look file"
	if font >= hull_font:
		return "the level row's font %d is not smaller than the hull row's %d" % [font, hull_font]
	if _luminance(color) >= _luminance(hull_color):
		return "the level row is not dimmer than the hull row"
	if moved:
		return "the level row moved"
	return ""


func test_the_look_file_rejects_bad_level_values() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE))
	var bad: Dictionary = {"level_font": 200, "level_color": [0.5, 2.0, 0.5], "level_seed_text": ""}
	for key: String in bad:
		var data: Dictionary = shipped.duplicate()
		data[key] = bad[key]
		var parsed: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
		if not parsed.has("error") or not String(parsed["error"]).contains(key):
			return "%s = %s gives %s, not an error naming it" % [key, bad[key], parsed]
	var words: Dictionary = shipped.duplicate()
	words["level_seed_text"] = "Mine {seed}"
	var reworded: Dictionary = StatusPanelLook.parse(JSON.stringify(words))
	var text: String = StatusPanelLevelRow.text_for("31", "", reworded)
	return "" if text == "Mine 31" else "the file's seed words give \"%s\"" % text


func test_the_panel_file_stays_under_300_lines() -> String:
	var lines: int = FileAccess.get_file_as_string("res://xr/status_panel.gd").split("\n").size()
	return "" if lines < 300 else "xr/status_panel.gd has %d lines" % lines


func test_the_main_scene_flying_seed_31_reads_seed_31_and_keeps_it_on_restart() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var level_start: LevelStart = main.get("level_start")
	level_start.source = "seed:31"  # As `_ready` sets it for `--seed=31`.
	var loaded: bool = main.call("use_level", level_start.source)
	main.call("advance_frame", FRAME)
	var panel: StatusPanel = main.get("status_panel")
	var text: String = panel.texts()[StatusPanel.LEVEL_NAME]
	var changes: int = panel.level_text_changes
	main.call("restart_level")
	main.call("advance_frame", FRAME)
	var after_restart: String = panel.texts()[StatusPanel.LEVEL_NAME]
	var changes_after: int = panel.level_text_changes
	main.free()
	if not loaded:
		return "seed 31 did not load"
	if text != "Seed 31":
		return "the main scene's panel reads \"%s\" flying seed 31" % text
	if after_restart != "Seed 31" or changes_after != changes:
		return "a restart of the same seed changed the row to \"%s\"" % after_restart
	return ""
