extends RefCounted

## The status panel in any of the four corners of the view (#752): distinct
## places that keep every row in view, the default unchanged, the choice
## saved and read back, the `--panel=` switch, and no effect on the simulation.

const PATH: String = "user://test_panel_corner.json"
## The limit #752 sets: every corner of every row within this of straight ahead.
const VIEW_LIMIT_DEG: float = 40.0
## The panel's face may point this far off the line to the eye.
const FACING_LIMIT_DEG: float = 15.0
## Left end of the labels and right end of the bars and the boost word.
const ROW_LEFT_X: float = -0.12
const ROW_RIGHT_X: float = 0.10
const ROWS: Array[String] = [StatusPanel.MELTDOWN_NAME, StatusPanel.HULL_LABEL_NAME,
	StatusPanel.SHIELD_LABEL_NAME, StatusPanel.ENERGY_LABEL_NAME, StatusPanel.WEAPON_NAME,
	StatusPanel.HOLD_NAME, StatusPanel.SPEED_NAME, StatusPanel.PRESET_NAME]
const FRAME: float = 1.0 / 72.0


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	PanelCorner.current = PanelCorner.CENTRE


func _at(corner: String) -> Transform3D:
	PanelCorner.current = corner
	var at: Transform3D = StatusPanel.rig_transform(Transform3D.IDENTITY)
	PanelCorner.current = PanelCorner.CENTRE
	return at


func test_each_corner_has_its_own_place_and_the_default_is_unchanged() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	var before: Transform3D = Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(float(look["tilt_deg"]))),
		look["position_m"] as Vector3)
	if not _at(PanelCorner.CENTRE).is_equal_approx(before):
		return "the default place moved: %s, was %s" % [_at(PanelCorner.CENTRE), before]
	if PanelCorner.new(PATH).corner() != PanelCorner.CENTRE:
		return "a new store does not start in the default place"
	var seen: Array[Transform3D] = [before]
	for corner: String in StatusPanelLook.CORNER_NAMES:
		var at: Transform3D = _at(corner)
		for other: Transform3D in seen:
			if at.origin.distance_to(other.origin) < 0.05:
				return "%s is within 5 cm of another place" % corner
		seen.append(at)
	var top_left: Vector3 = _at("top_left").origin
	var bottom_right: Vector3 = _at("bottom_right").origin
	if top_left.x >= 0.0 or top_left.y <= 0.0 or bottom_right.x <= 0.0 or bottom_right.y >= 0.0:
		return "the corners are not where their names say: %s, %s" % [top_left, bottom_right]
	return ""


func test_every_corner_keeps_every_row_in_view_and_faced_at_the_eye() -> String:
	var half_glyph: float = StatusPanel.SMALL_FONT * StatusPanel.PIXEL_SIZE * 0.5
	var panel: StatusPanel = StatusPanel.new()
	var message: String = ""
	for corner: String in StatusPanelLook.CORNER_NAMES:
		var at: Transform3D = _at(corner)
		for row: String in ROWS:
			var y: float = (panel.get_node(row) as Node3D).position.y
			for x: float in [ROW_LEFT_X, ROW_RIGHT_X]:
				for dy: float in [-half_glyph, half_glyph]:
					var angle: float = rad_to_deg((at * Vector3(x, y + dy, 0.0)).angle_to(Vector3.FORWARD))
					if angle > VIEW_LIMIT_DEG and message == "":
						message = "%s: row %s reaches %.1f degrees off ahead" % [corner, row, angle]
		var facing_off: float = rad_to_deg(at.basis.z.angle_to(-at.origin))
		if facing_off > FACING_LIMIT_DEG and message == "":
			message = "%s: the panel faces %.1f degrees off the eye" % [corner, facing_off]
		if absf(at.basis.x.y) > 0.001 and message == "":
			message = "%s: the rows are not level" % corner
	panel.free()
	return message


func test_the_choice_is_saved_and_a_new_store_reads_it_back() -> String:
	_clean()
	var store: PanelCorner = PanelCorner.new(PATH)
	var taken: bool = store.choose("top_right")
	var moved: bool = PanelCorner.current == "top_right"
	var again: PanelCorner = PanelCorner.new(PATH)
	PanelCorner.current = PanelCorner.CENTRE
	again.load_saved()
	var read_back: String = again.corner()
	var current: String = PanelCorner.current
	_clean()
	if not taken or not moved:
		return "choosing top_right was not taken"
	if read_back != "top_right" or current != "top_right":
		return "a new store read back %s (in use %s)" % [read_back, current]
	return ""


func test_a_missing_or_broken_file_gives_the_default() -> String:
	_clean()
	var missing: PanelCorner = PanelCorner.new(PATH)
	missing.load_saved()
	if missing.corner() != PanelCorner.CENTRE or not missing.warnings.is_empty():
		return "a missing file gave %s with %s" % [missing.corner(), missing.warnings]
	for text: String in ["not json", "[\"top_left\"]", "{\"corner\": \"middle\"}",
			"{\"corner\": 3}", "{\"corner\": \"top_left\", \"preset\": 2}", "{}"]:
		var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		PanelCorner.current = "top_left"
		var store: PanelCorner = PanelCorner.new(PATH)
		store.load_saved()
		var current: String = PanelCorner.current
		_clean()
		if store.corner() != PanelCorner.CENTRE or current != PanelCorner.CENTRE:
			return "%s gave %s" % [text, store.corner()]
		if store.warnings.size() != 1:
			return "%s gave %d warnings, expected 1" % [text, store.warnings.size()]
	return ""


func test_the_panel_switch_selects_and_saves_a_corner() -> String:
	_clean()
	var store: PanelCorner = PanelCorner.new(PATH)
	store.apply_switch(PackedStringArray(["--panel=top_left"]), "")
	var saved: PanelCorner = PanelCorner.new(PATH)
	saved.load_saved()
	var message: String = ""
	if store.corner() != "top_left" or saved.corner() != "top_left" or PanelCorner.current != "top_left":
		message = "--panel=top_left gave %s, saved %s" % [store.corner(), saved.corner()]
	store.apply_switch(PackedStringArray(["--panel=middle"]), "")
	if message == "" and (store.corner() != "top_left" or PanelCorner.current != "top_left"):
		message = "--panel=middle changed the corner to %s" % store.corner()
	if message == "" and (store.warnings.size() != 1 or not store.warnings[0].contains("\"middle\"")):
		message = "--panel=middle logged %s" % [store.warnings]
	store.apply_switch(PackedStringArray(), "bottom_left")
	if message == "" and store.corner() != "bottom_left":
		message = "the intent extra gave %s" % store.corner()
	store.apply_switch(PackedStringArray(["--panel=top_left", "--panel=bottom_right"]), "top_right")
	if message == "" and store.corner() != "bottom_right":
		message = "the last argument over the extra gave %s" % store.corner()
	store.apply_switch(PackedStringArray(["--level=g2"]), "")
	if message == "" and store.corner() != "bottom_right":
		message = "no switch changed the corner to %s" % store.corner()
	_clean()
	return message


func test_changing_the_corner_leaves_the_simulation_alone() -> String:
	_clean()
	var hashes: Array[int] = []
	var moved: bool = false
	for change: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.call("attach_status_panel")
		var panel: StatusPanel = main.get("status_panel")
		var store: PanelCorner = PanelCorner.new(PATH)
		var before: Transform3D = Transform3D.IDENTITY
		for frame: int in 60:
			if change and frame == 20:
				before = panel.transform
				store.choose("top_left")
			var values: Dictionary = ControllerSampler.idle_values()
			values["buttons"] = {"right_button_lower": frame < 30}
			main.call("apply_controls", values)
			main.call("advance_frame", FRAME)
		if change:
			moved = not panel.transform.is_equal_approx(before)
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
		_clean()
	if not moved:
		return "the panel did not move to the chosen corner"
	if hashes[0] != hashes[1]:
		return "the corner changed the simulation: %s" % [hashes]
	return ""


func test_the_look_names_a_bad_corners_value() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE))
	var parsed: Dictionary = StatusPanelLook.parse(JSON.stringify(shipped))
	if parsed.has("error") or parsed["corners"] != StatusPanelLook.FALLBACK["corners"]:
		return "the shipped corners differ from the fallback: %s" % parsed
	var cases: Dictionary = {
		"must be an object": [1, 2, 3],
		"missing corner \"bottom_right\"": {"top_left": [-0.1, 0.1, -0.5], "top_right": [0.1, 0.1, -0.5],
			"bottom_left": [-0.1, -0.1, -0.5]},
		"unknown corner \"middle\"": {"middle": [0.0, 0.0, -0.5]},
		"corners.top_left\" is 0.05 m": {"top_left": [0.0, 0.0, -0.05], "top_right": [0.1, 0.1, -0.5],
			"bottom_left": [-0.1, -0.1, -0.5], "bottom_right": [0.1, -0.1, -0.5]},
		"corners.top_right\" must lie": {"top_left": [-0.1, 0.1, -0.5], "top_right": [0.3, 0.3, 0.0],
			"bottom_left": [-0.1, -0.1, -0.5], "bottom_right": [0.1, -0.1, -0.5]},
		"corners.bottom_left\" must be three": {"top_left": [-0.1, 0.1, -0.5], "top_right": [0.1, 0.1, -0.5],
			"bottom_left": [-0.1, -0.1], "bottom_right": [0.1, -0.1, -0.5]},
	}
	for expected: String in cases:
		var data: Dictionary = shipped.duplicate(true)
		data["corners"] = cases[expected]
		var result: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
		if not str(result.get("error", "")).contains(expected):
			return "expected an error with '%s', got %s" % [expected, result.get("error", "none")]
	shipped.erase("corners")
	if StatusPanelLook.parse(JSON.stringify(shipped)).has("error"):
		return "a look without corners was rejected"
	return ""
