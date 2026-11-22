extends RefCounted

## The status panel after the owner's headset session (#605, CMF-1, CMB-1,
## SLV-1, RUN-2): every row within a glance down on every preset, the panel
## faced at the eye, the rows in the order a pilot needs them, the weapon row,
## the build line off the prime rows, and the pickup and slot messages.

## The panel's face may point this far off the line to the eye.
const FACING_LIMIT_DEG: float = 15.0
## Rows closer than this would put glyphs on top of each other.
const MIN_ROW_GAP: float = 0.025
## Top to bottom, as #605 asks: countdown, hull, shield, energy, the weapon
## slots (#1210), hold, then the rest.
const ROW_ORDER: Array[String] = [StatusPanel.MELTDOWN_NAME, StatusPanel.HULL_LABEL_NAME,
	StatusPanel.SHIELD_LABEL_NAME, StatusPanel.ENERGY_LABEL_NAME, StatusPanel.WEAPON_NAME, "Weapon2",
	StatusPanel.HOLD_NAME, StatusPanel.SPEED_NAME, StatusPanel.PRESET_NAME]


static func _y(panel: StatusPanel, node_name: String) -> float:
	return (panel.get_node(node_name) as Node3D).position.y


## Degrees below the eye line of `point`, in the space of the eye at the origin.
static func _below(point: Vector3) -> float:
	return -CockpitGeometry.yaw_pitch(point).y


## Every row the panel draws. Speed and the preset have not drawn since #1207
## (the dev menu shows them); with a row per weapon slot (#1210) they sit
## below the glance, which `test_the_shipped_rows_leave_out_speed_and_preset`
## keeps true.
func test_every_row_is_within_a_glance_down_on_every_preset() -> String:
	var limit: float = float(StatusPanelLook.load_file()["max_row_angle_deg"])
	for number: int in [1, 2, 3, 4]:
		var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.for_preset(ComfortPresetFiles.load_number(number)))
		var panel: StatusPanel = StatusPanel.new()
		var recentre: HeadRecentre = HeadRecentre.new()
		# A recentre off the floor origin: the panel must follow the head point.
		recentre.offset = Transform3D(Basis.IDENTITY, Vector3(0.1, -1.2, 0.3))
		RigViews.place(recentre, frame, panel)
		var eye: Transform3D = frame.transform.affine_inverse()
		var angles: Array[float] = []
		for row: String in ROW_ORDER:
			if (panel.get_node(row) as VisualInstance3D).layers != 0:
				angles.append(_below(eye * panel.transform * Vector3(0.0, _y(panel, row), 0.0)))
		var facing: Vector3 = (eye.basis * panel.transform.basis).z
		var to_eye: Vector3 = -(eye * panel.transform.origin).normalized()
		var facing_off: float = rad_to_deg(facing.angle_to(to_eye))
		panel.free()
		frame.free()
		if angles.back() > limit:
			return "preset %d: the bottom row is %.1f degrees down, over %.1f" % [number, angles.back(), limit]
		if angles.front() <= 0.0:
			return "preset %d: the top row is above the eye line" % number
		if facing_off > FACING_LIMIT_DEG:
			return "preset %d: the panel faces %.1f degrees off the eye" % [number, facing_off]
	return ""


func test_the_shipped_rows_leave_out_speed_and_preset() -> String:
	var rows: Array[String] = StatusPanelLook.load_file()["rows"]
	for row: String in ["meltdown", "hull", "shield", "energy", "weapon", "hold"]:
		if not rows.has(row):
			return "the shipped panel does not draw %s" % row
	if rows.has("speed") or rows.has("preset"):
		return "the shipped panel draws speed or preset below the glance: %s" % [rows]
	return ""


func test_the_shipped_look_keeps_the_limit_at_thirty_degrees() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	if not is_equal_approx(float(look["max_row_angle_deg"]), 30.0):
		return "the shipped limit is %s degrees" % look["max_row_angle_deg"]
	if (look["position_m"] as Vector3).length() >= 1.0:
		return "the panel is outside the ship's collision sphere"
	return ""


func test_rows_run_countdown_hull_shield_energy_weapon_hold_then_the_rest() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var heights: Array[float] = []
	for row: String in ROW_ORDER:
		heights.append(_y(panel, row))
	var bars: Array[float] = [_y(panel, StatusPanel.HULL_BAR_NAME), _y(panel, StatusPanel.SHIELD_BAR_NAME),
		_y(panel, StatusPanel.ENERGY_BAR_NAME)]
	panel.free()
	for index: int in range(1, heights.size()):
		if heights[index - 1] - heights[index] < MIN_ROW_GAP:
			return "%s at %.3f is not clear below %s at %.3f" % [ROW_ORDER[index], heights[index],
				ROW_ORDER[index - 1], heights[index - 1]]
	if not (is_equal_approx(bars[0], heights[1]) and is_equal_approx(bars[1], heights[2])
			and is_equal_approx(bars[2], heights[3])):
		return "the bars %s do not share rows with their labels" % [bars]
	return ""


func test_the_weapon_rows_name_each_slot_or_say_empty() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var unwired: String = panel.texts()[StatusPanel.WEAPON_NAME]
	panel.show_weapons(["Needle Gun", ""] as Array[String], 0)
	var armed: String = panel.texts()[StatusPanel.WEAPON_NAME]
	panel.show_weapons(["", ""] as Array[String], 0)
	var empty: String = panel.texts()[StatusPanel.WEAPON_NAME]
	panel.free()
	var none: String = StatusPanelWeaponRows.row_text(0, "", true)
	if unwired != none or empty != none:
		return "an empty slot reads %s, then %s" % [unwired, empty]
	if armed != "> 1 Needle Gun":
		return "the weapon row reads %s" % armed
	return ""


func test_active_weapon_is_the_selected_primary_slots_id() -> String:
	var ship: ShipState = ShipState.new()
	var none: String = CombatWiring.active_weapon(ship)
	ship.primary_slots[1] = WeaponDef.new()
	ship.primary_ids[1] = "arc_lance"
	var other_slot: String = CombatWiring.active_weapon(ship)
	ship.selected_primary = 1
	var selected: String = CombatWiring.active_weapon(ship)
	if none != "" or other_slot != "":
		return "an empty selected slot names %s, %s" % [none, other_slot]
	if selected != "arc_lance":
		return "the selected slot names %s" % selected
	return ""


func test_the_build_line_costs_no_row_and_shows_with_the_large_preset() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var build: Label3D = panel.get_node(StatusPanel.BUILD_NAME) as Label3D
	var before: bool = build.visible
	panel.show_values(2, "Guided", 0.0, 1.0, "", "abc1234, built 2026-11-19 12:00 UTC")
	var with_large: bool = build.visible
	panel.advance(StatusPanel.PRESET_LARGE_SECONDS + 0.1)
	var after: bool = build.visible
	var above: bool = build.position.y > _y(panel, StatusPanel.PRESET_LARGE_NAME)
	var smaller: bool = build.font_size < StatusPanel.SMALL_FONT
	panel.free()
	if before or after:
		return "the build line shows while the large preset does not"
	if not with_large:
		return "the build line does not show with the large preset"
	if not above or not smaller:
		return "the build line is not small and above the large preset"
	return ""


func test_a_hold_message_shows_for_the_look_time_then_the_hold_returns() -> String:
	var seconds: float = float(StatusPanelLook.load_file()["message_seconds"])
	var panel: StatusPanel = StatusPanel.new()
	panel.show_hold("needle_gun")
	panel.show_hold_message(HoldMessages.PICKED_UP % "needle_gun")
	var shown: Array[String] = []
	var frames: int = roundi(seconds * 90.0)
	for frame: int in frames + 2:
		panel.show_hold("needle_gun")
		shown.append(String(panel.texts()[StatusPanel.HOLD_NAME]))
		panel.advance(1.0 / 90.0)
	var changes: int = panel.hold_text_changes
	panel.free()
	if shown[0] != "Picked up: needle_gun" or shown[frames - 2] != shown[0]:
		return "the message reads %s, then %s before %.1f s" % [shown[0], shown[frames - 2], seconds]
	if shown.back() != "Hold needle_gun":
		return "after %.1f s the hold row reads %s" % [seconds, shown.back()]
	if changes != 3:
		return "the label changed %d times, not hold, message, hold" % changes
	return ""


func test_hold_messages_say_pickups_and_slottings_only() -> String:
	var messages: HoldMessages = HoldMessages.new()
	var steps: Array = [
		[[], ["pulse_cannon", ""], ""],
		[[], ["pulse_cannon", ""], ""],
		[["needle_gun"], ["pulse_cannon", ""], "Picked up: needle_gun"],
		[["needle_gun"], ["pulse_cannon", ""], ""],
		[[], ["pulse_cannon", "needle_gun"], "Slotted needle_gun"],
		[["arc_lance"], ["pulse_cannon", "needle_gun"], "Picked up: arc_lance"],
		[[], ["arc_lance", "needle_gun"], "Slotted arc_lance, dropped pulse_cannon"],
		[["slug_thrower"], ["arc_lance", "needle_gun"], "Picked up: slug_thrower"],
		# A restart empties the hold without slotting: nothing to say.
		[[], ["", ""], ""],
	]
	for index: int in steps.size():
		var hold: Array[String] = []
		hold.assign(steps[index][0])
		var ids: Array[String] = []
		ids.assign(steps[index][1])
		var said: String = messages.update(hold, ids)
		if said != steps[index][2]:
			return "step %d says '%s', not '%s'" % [index, said, steps[index][2]]
	return ""


func test_a_full_hold_at_the_start_says_nothing() -> String:
	var said: String = HoldMessages.new().update(["needle_gun"] as Array[String], ["", ""] as Array[String])
	if said != "":
		return "the first frame says %s" % said
	return ""


func test_the_look_rejects_a_panel_outside_the_ship_or_a_bad_tilt() -> String:
	var base: String = '{"escaped_color": [0, 1, 0], "position_m": %s, "tilt_deg": %s, ' \
		+ '"max_row_angle_deg": 30, "message_seconds": 2}'
	var bad: Dictionary = {
		base % ["[0, -0.6, -0.8]", "20"]: "position_m",
		base % ["[0, -0.2]", "20"]: "position_m",
		base % ["[0, -0.2, -0.5]", "95"]: "tilt_deg",
		base % ["[0, -0.2, -0.5]", "true"]: "tilt_deg",
	}
	for text: String in bad:
		var result: Dictionary = StatusPanelLook.parse(text)
		if not result.has("error") or not String(result["error"]).contains(bad[text]):
			return "%s gives %s, not an error naming %s" % [text, result, bad[text]]
	return ""
