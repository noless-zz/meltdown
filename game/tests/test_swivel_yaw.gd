extends RefCounted

## Swivel-chair yaw (CMF-7, CMF-3, ARC-3): off by default, nothing inside the
## dead zone, a growing value of the right sign past it up to the cap, a
## recentre resets the reference, preset 1 still turns only by snaps, and the
## settings come from the comfort preset, a bad one reported naming the field.

## One headset frame at 90 Hz.
const FRAME_S: float = 1.0 / 90.0


func _valid_data() -> Dictionary:
	return {
		"enabled": true, "dead_zone_deg": 30.0, "gain_per_deg": 0.03,
		"max_input": 0.8, "follow_deg_per_s": 0.0,
	}


## A swivel built from a copy of preset 2 with the swivel rows from `data`,
## whose keys drop the preset fields' `swivel_` prefix.
func _swivel(data: Dictionary = _valid_data()) -> SwivelYaw:
	return SwivelYaw.from_preset(_preset(data))


func _preset(data: Dictionary) -> ComfortPreset:
	var preset: ComfortPreset = ComfortPresetFiles.load_number(2).duplicate() as ComfortPreset
	for key: String in data:
		preset.set("swivel_" + key, data[key])
	return preset


func test_shipped_presets_are_off() -> String:
	for number: int in [1, 2, 3, 4]:
		var swivel: SwivelYaw = SwivelYaw.from_preset(ComfortPresetFiles.load_number(number))
		if swivel.error != "":
			return "preset %d rejected: %s" % [number, swivel.error]
		if swivel.enabled:
			return "swivel must be off on preset %d" % number
		if swivel.update(deg_to_rad(120.0), FRAME_S) != 0.0:
			return "off swivel on preset %d gave input" % number
	return ""


func test_takes_every_setting_from_the_preset() -> String:
	var swivel: SwivelYaw = _swivel({
		"enabled": true, "dead_zone_deg": 20.0, "gain_per_deg": 0.05,
		"max_input": 0.6, "follow_deg_per_s": 12.0,
	})
	if swivel.error != "":
		return "valid preset rejected: %s" % swivel.error
	var got: Array = [swivel.enabled, swivel.dead_zone_deg, swivel.gain_per_deg,
		swivel.max_input, swivel.follow_deg_per_s]
	if got != [true, 20.0, 0.05, 0.6, 12.0]:
		return "settings read as %s" % str(got)
	return ""


func test_off_gives_zero() -> String:
	var data: Dictionary = _valid_data()
	data["enabled"] = false
	var swivel: SwivelYaw = _swivel(data)
	for degrees: float in [-170.0, -60.0, 0.0, 45.0, 90.0]:
		if swivel.update(deg_to_rad(degrees), FRAME_S) != 0.0:
			return "off gave input at %s degrees" % degrees
	return ""


func test_inside_dead_zone_gives_zero() -> String:
	var swivel: SwivelYaw = _swivel()
	for degrees: float in [-30.0, -29.0, -10.0, 0.0, 15.0, 29.9, 30.0]:
		var value: float = swivel.update(deg_to_rad(degrees), FRAME_S)
		if value != 0.0:
			return "head at %s degrees gave %s inside the dead zone" % [degrees, value]
	return ""


func test_beyond_dead_zone_signs_grows_and_caps() -> String:
	var swivel: SwivelYaw = _swivel()
	var last: float = 0.0
	for degrees: float in [35.0, 40.0, 50.0, 55.0]:
		# Head turned left (+ about +Y): nose left, negative stick yaw.
		var left: float = swivel.update(deg_to_rad(degrees), FRAME_S)
		var right: float = swivel.update(deg_to_rad(-degrees), FRAME_S)
		if not left < 0.0 or not right > 0.0:
			return "at %s degrees: left %s, right %s have the wrong sign" % [degrees, left, right]
		if not is_equal_approx(left, -right):
			return "at %s degrees left and right differ: %s, %s" % [degrees, left, right]
		if not absf(left) > last:
			return "at %s degrees value %s did not grow past %s" % [degrees, left, last]
		last = absf(left)
	for degrees: float in [80.0, 120.0, 179.0]:
		var capped: float = swivel.update(deg_to_rad(-degrees), FRAME_S)
		if not is_equal_approx(capped, 0.8):
			return "at %s degrees value %s is not the cap 0.8" % [degrees, capped]
	return ""


func test_recentre_resets_reference() -> String:
	var swivel: SwivelYaw = _swivel()
	var turned: float = deg_to_rad(-70.0)
	if not swivel.update(turned, FRAME_S) > 0.0:
		return "turned body gave no input before the recentre"
	swivel.recentre(turned)
	if swivel.update(turned, FRAME_S) != 0.0:
		return "recentre did not make the new heading forward"
	swivel.recentre()
	if not swivel.update(turned, FRAME_S) > 0.0:
		return "recentre to 0 did not restore the forward heading"
	return ""


func test_reference_follows_the_body() -> String:
	var data: Dictionary = _valid_data()
	data["follow_deg_per_s"] = 20.0
	var swivel: SwivelYaw = _swivel(data)
	var turned: float = deg_to_rad(-60.0)
	var first: float = swivel.update(turned, FRAME_S)
	var value: float = first
	for i: int in 90 * 5:
		value = swivel.update(turned, FRAME_S)
	if not first > 0.0 or value != 0.0:
		return "held turn gave %s then %s; the reference must follow into the dead zone" % [first, value]
	return ""


func test_added_to_stick_keeps_thrust_and_full_rate() -> String:
	var full: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
	var input: ShipInput = ShipInput.new(Vector3i(100, -200, -900), Vector3i(50, 0, 30), true)
	var out: ShipInput = SwivelYaw.added_to(input, 0.5)
	var half: int = roundi(ThumbstickMapping.MAX_YAW_RATE * 0.5 * ShipInput.SCALE)
	if out.turn_q != Vector3i(50, -half, 30):
		return "half right swivel gave turn %s" % out.turn_q
	if out.thrust_q != input.thrust_q or out.afterburner != input.afterburner:
		return "thrust or afterburner changed"
	var stacked: ShipInput = SwivelYaw.added_to(ShipInput.new(Vector3i.ZERO, Vector3i(0, -full, 0)), 1.0)
	if stacked.turn_q.y != -full:
		return "stick and swivel together went past full rate: %d" % stacked.turn_q.y
	if input.turn_q != Vector3i(50, 0, 30):
		return "added_to changed its input"
	return ""


func test_preset_one_gives_only_snaps() -> String:
	var swivel: SwivelYaw = _swivel()
	var filter: ComfortInputFilter = ComfortInputFilter.new(ComfortPresetFiles.load_number(1))
	var snap: int = filter.snap_rate_q()
	var snaps: int = 0
	for i: int in 400:
		# The chair swings slowly from 90 degrees left to 90 degrees right and back.
		var degrees: float = 90.0 * cos(float(i) / 400.0 * TAU)
		var stick: float = swivel.update(deg_to_rad(degrees), FRAME_S)
		var out: ShipInput = filter.filter(SwivelYaw.added_to(ShipInput.new(), stick))
		if out.turn_q.y != 0 and absi(out.turn_q.y) != snap:
			return "tick %d: yaw %d is not 0 or one snap (%d)" % [i, out.turn_q.y, snap]
		if out.turn_q.y != 0:
			snaps += 1
	if snaps == 0:
		return "a full chair swing never snapped"
	return ""


func test_preset_two_cap_holds() -> String:
	var preset: ComfortPreset = ComfortPresetFiles.load_number(2)
	var cap: int = ComfortInputFilter.cap_q(preset.yaw_rate_cap_deg_per_s)
	if cap < 0:
		return ""
	var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
	var swivel: SwivelYaw = _swivel()
	var full: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
	var input: ShipInput = ShipInput.new(Vector3i.ZERO, Vector3i(0, -full, 0))
	var out: ShipInput = filter.filter(SwivelYaw.added_to(input, swivel.update(deg_to_rad(-90.0), FRAME_S)))
	if absi(out.turn_q.y) > cap:
		return "yaw %d is past preset 2's cap %d" % [out.turn_q.y, cap]
	return ""


func test_bad_preset_names_the_field_and_stays_off() -> String:
	var cases: Array = [
		["dead_zone_deg", -1.0],
		["gain_per_deg", 2.0],
		["max_input", 1.5],
		["follow_deg_per_s", 500.0],
		["dead_zone_deg", NAN],
	]
	for entry: Array in cases:
		var data: Dictionary = _valid_data()
		data[entry[0]] = entry[1]
		var swivel: SwivelYaw = _swivel(data)
		if swivel.error.find("swivel_%s" % entry[0]) < 0:
			return "%s = %s: error \"%s\" does not name the field" % [entry[0], entry[1], swivel.error]
		if swivel.enabled:
			return "%s = %s: a rejected preset left swivel on" % [entry[0], entry[1]]
	var missing: SwivelYaw = SwivelYaw.from_preset(null)
	if missing.error == "" or missing.enabled:
		return "a missing preset was accepted"
	return ""


func test_no_swivel_data_file_is_left() -> String:
	if FileAccess.file_exists("res://xr/swivel.json"):
		return "res://xr/swivel.json still exists; the preset holds the swivel settings"
	var source: String = FileAccess.get_file_as_string("res://xr/swivel_yaw.gd")
	if source.contains(".json"):
		return "swivel_yaw.gd still reads a data file"
	return ""


func test_writes_no_simulation_state() -> String:
	var source: String = FileAccess.get_file_as_string("res://xr/swivel_yaw.gd")
	for forbidden: String in ["ShipState", "World", ".step("]:
		if source.find(forbidden) >= 0:
			return "swivel_yaw.gd mentions %s; it may only produce input" % forbidden
	return ""
