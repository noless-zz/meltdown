extends RefCounted

## Hull, shield and energy as lit instruments on the console (#1461, GFX-2,
## CMF-8, PLT-5, ARC-3, ARC-4): the bar values and the low state, the slow
## pulse, the nodes the frame builds, the same place on all four presets, the
## contrast from the materials' colours, the text size against the status
## panel's, and room for the dash, the panel and the map.

const DIR: String = "res://xr/cockpits/"
const GAUGES: Array[String] = [ShipGauges.HULL, ShipGauges.SHIELD, ShipGauges.ENERGY]
## WCAG's least contrast for graphics and for text.
const GRAPHIC_CONTRAST: float = 3.0
const TEXT_CONTRAST: float = 4.5


static func _specs() -> Array[CockpitSpec]:
	var specs: Array[CockpitSpec] = []
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		specs.append(CockpitSpec.for_preset(ComfortPresetFiles.load_number(number)))
	return specs


static func _for_gauge(spec: CockpitSpec, gauge: String) -> CockpitInstrument:
	for instrument: CockpitInstrument in spec.instruments:
		if instrument.gauge == gauge:
			return instrument
	return null


## The yaw/pitch box an instrument's face covers, degrees.
static func _seen(instrument: CockpitInstrument) -> Rect2:
	var half: Vector2 = Vector2(rad_to_deg(atan(instrument.size_m.x * 0.5 / instrument.distance_m)),
		rad_to_deg(atan(instrument.size_m.y * 0.5 / instrument.distance_m)))
	return Rect2(Vector2(instrument.yaw_deg, instrument.pitch_deg) - half, half * 2.0)


func test_fill_clamps_and_reads_a_bad_value_as_empty() -> String:
	var instrument: CockpitInstrument = CockpitInstrument.new()
	var cases: Dictionary = {0.4: 0.4, -0.2: 0.0, 1.7: 1.0, NAN: 0.0, INF: 0.0}
	for value: float in cases:
		if not is_equal_approx(instrument.fill(value), cases[value]):
			return "fill(%s) is %s" % [value, instrument.fill(value)]
	return ""


func test_the_low_state_starts_below_the_files_threshold() -> String:
	var instrument: CockpitInstrument = CockpitInstrument.new()
	instrument.low_below = 0.3
	if instrument.is_low(0.3) or not instrument.is_low(0.29) or not instrument.is_low(0.0):
		return "low at 0.3 / 0.29 / 0: %s %s %s" % [instrument.is_low(0.3), instrument.is_low(0.29), instrument.is_low(0.0)]
	if instrument.bar_color(0.5, 0.0) != instrument.color:
		return "a normal bar is drawn %s" % instrument.bar_color(0.5, 0.0)
	if instrument.bar_color(0.1, 0.0) != instrument.low_color:
		return "a low bar starts at %s, not the low colour" % instrument.bar_color(0.1, 0.0)
	return ""


func test_the_low_pulse_is_slow_and_never_dark() -> String:
	for spec: CockpitSpec in _specs():
		for instrument: CockpitInstrument in spec.instruments:
			if instrument.low_pulse_s < 1.0:
				return "%s pulses every %s s, faster than once a second" % [instrument.id, instrument.low_pulse_s]
			var dimmest: float = 1.0
			var steps: int = 120
			for step: int in steps:
				dimmest = minf(dimmest, instrument.brightness(instrument.low_pulse_s * step / steps, true))
			if not is_equal_approx(dimmest, instrument.low_pulse_min) or dimmest < 0.5:
				return "%s dims to %s over a pulse" % [instrument.id, dimmest]
			var half: float = instrument.brightness(instrument.low_pulse_s * 0.5, true)
			if not is_equal_approx(half, instrument.low_pulse_min) \
					or not is_equal_approx(instrument.brightness(instrument.low_pulse_s, true), 1.0):
				return "%s's pulse is not one slow wave per %s s" % [instrument.id, instrument.low_pulse_s]
			if instrument.brightness(0.37, false) != 1.0:
				return "%s pulses while not low" % instrument.id
	return ""


func test_every_preset_has_hull_shield_and_energy_in_the_same_place() -> String:
	var specs: Array[CockpitSpec] = _specs()
	for gauge: String in GAUGES:
		var first: CockpitInstrument = _for_gauge(specs[0], gauge)
		if first == null:
			return "preset 1 has no %s instrument" % gauge
		for index: int in specs.size():
			if specs[index].error != "":
				return specs[index].error
			var instrument: CockpitInstrument = _for_gauge(specs[index], gauge)
			if instrument == null:
				return "preset %d has no %s instrument" % [index + 1, gauge]
			var a: Rect2 = _seen(first)
			var b: Rect2 = _seen(instrument)
			if a.position.distance_to(b.position) > 0.1 or a.size.distance_to(b.size) > 0.1:
				return "preset %d's %s covers %s, preset 1's %s" % [index + 1, gauge, b, a]
			if instrument.low_below != first.low_below or instrument.label != first.label \
					or instrument.color != first.color or instrument.low_color != first.low_color:
				return "preset %d's %s looks unlike preset 1's" % [index + 1, gauge]
	return ""


func test_the_instruments_sit_a_small_look_down() -> String:
	for spec: CockpitSpec in _specs():
		for instrument: CockpitInstrument in spec.instruments:
			var seen: Rect2 = _seen(instrument)
			if seen.end.y > -20.0 or seen.position.y < -45.0 or absf(seen.get_center().x) > 30.0:
				return "%s covers %s, not a small look down" % [instrument.id, seen]
	return ""


func test_the_contrast_against_the_dash_holds_from_the_colours() -> String:
	for spec: CockpitSpec in _specs():
		var bezel_dash: float = ConsoleGauges.contrast(ConsoleGauges.BEZEL_COLOR, spec.structure_color)
		if bezel_dash < GRAPHIC_CONTRAST:
			return "the bezel against the dash is %.2f:1" % bezel_dash
		var label: float = ConsoleGauges.contrast(ConsoleGauges.LABEL_COLOR, ConsoleGauges.BEZEL_COLOR)
		if label < TEXT_CONTRAST:
			return "the labels against the bezel are %.2f:1" % label
		for instrument: CockpitInstrument in spec.instruments:
			for low: bool in [false, true]:
				var base: Color = instrument.low_color if low else instrument.color
				var dim: float = instrument.low_pulse_min if low else 1.0
				var bar: Color = Color(base.r * dim, base.g * dim, base.b * dim)
				var track: Color = base * ConsoleGauges.TRACK_SHARE
				var on_bezel: float = ConsoleGauges.contrast(bar, ConsoleGauges.BEZEL_COLOR)
				var on_track: float = ConsoleGauges.contrast(bar, Color(track.r, track.g, track.b))
				if on_bezel < GRAPHIC_CONTRAST or on_track < GRAPHIC_CONTRAST:
					return "%s's %s bar at its dimmest is %.2f:1 on the bezel, %.2f:1 on its track" % [
						instrument.id, "low" if low else "normal", on_bezel, on_track]
	return ""


func test_the_contrast_formula_matches_wcag() -> String:
	var white_black: float = ConsoleGauges.contrast(Color.WHITE, Color.BLACK)
	if not is_equal_approx(white_black, 21.0) or not is_equal_approx(ConsoleGauges.contrast(Color.RED, Color.RED), 1.0):
		return "white on black is %s" % white_black
	return ""


func test_label_text_is_no_smaller_than_the_status_panels() -> String:
	var height: float = float(StatusPanel.SMALL_FONT) * StatusPanel.PIXEL_SIZE
	var panel_deg: float = 0.0
	var corners: Dictionary = StatusPanelLook.shared()["corners"]
	for corner: String in corners:
		var placed: Transform3D = StatusPanelLook.placement(StatusPanelLook.shared(), corner)
		panel_deg = maxf(panel_deg, rad_to_deg(2.0 * atan(height * 0.5 / placed.origin.length())))
	if panel_deg <= 0.0:
		return "no status panel text size to compare with"
	for spec: CockpitSpec in _specs():
		for instrument: CockpitInstrument in spec.instruments:
			if instrument.label == "":
				return "%s has no label" % instrument.id
			var deg: float = ConsoleGauges.label_angle_deg(instrument)
			if deg < panel_deg:
				return "%s's label is %.2f degrees tall, the panel's text %.2f" % [instrument.id, deg, panel_deg]
	return ""


func test_the_instruments_clear_the_dash_the_panel_and_the_map() -> String:
	for spec: CockpitSpec in _specs():
		var seen: Array[Rect2] = []
		for instrument: CockpitInstrument in spec.instruments:
			var rect: Rect2 = _seen(instrument)
			for other: Rect2 in seen:
				if rect.intersects(other):
					return "%s overlaps another instrument" % instrument.id
			seen.append(rect)
			if instrument.distance_m + ConsoleGauges.BEZEL_DEPTH_M >= spec.frame_distance_m:
				return "%s reaches the shell" % instrument.id
			for piece: CockpitDashPiece in spec.dash:
				var piece_rect: Rect2 = Rect2()
				var corners: Array[Vector3] = CockpitGeometry.corners(piece.placed(), true)
				for k: int in corners.size():
					var at: Vector2 = CockpitGeometry.yaw_pitch(corners[k])
					piece_rect = Rect2(at, Vector2.ZERO) if k == 0 else piece_rect.expand(at)
				if rect.intersects(piece_rect):
					return "%s overlaps a dash piece at yaw %s, pitch %s" % [instrument.id, piece.yaw_deg, piece.pitch_deg]
			for corner: String in StatusPanelLook.shared()["corners"]:
				if rect.intersects(MapPanelClearance.panel_rect(corner)):
					return "%s overlaps the status panel in %s" % [instrument.id, corner]
		for corner: String in StatusPanelLook.shared()["corners"]:
			var map: String = MapPanelClearance.mount_problem(spec, corner)
			if map != "":
				return "with the panel in %s: %s" % [corner, map]
	return ""


func test_the_frame_builds_the_console_and_rebuilds_it_with_the_preset() -> String:
	var specs: Array[CockpitSpec] = _specs()
	var frame: CockpitFrame = CockpitFrame.new(specs[0])
	var console: ConsoleGauges = ConsoleGauges.of_frame(frame)
	var problem: String = ""
	if console == null or console.get_parent() != frame:
		problem = "the frame has no console instruments as its child"
	elif console.instruments.size() != 3:
		problem = "%d instruments built" % console.instruments.size()
	else:
		var draws: int = 0
		for child: Node in console.get_children():
			if child is GeometryInstance3D:
				draws += 1
		if draws != 5:
			problem = "the console draws %d nodes, not 5" % draws
		for index: int in console.instruments.size():
			var seen: Vector2 = CockpitGeometry.yaw_pitch(console.place(index).origin)
			var want: CockpitInstrument = console.instruments[index]
			if problem == "" and seen.distance_to(Vector2(want.yaw_deg, want.pitch_deg)) > 0.01:
				problem = "%s is built at %s" % [want.id, seen]
	if problem == "":
		frame.set_spec(specs[1])
		if ConsoleGauges.of_frame(frame) == null or ConsoleGauges.of_frame(frame).updates != 0:
			problem = "a new preset did not rebuild the console"
	frame.free()
	return problem


func test_shown_values_follow_the_gauges_and_count_low_frames() -> String:
	var spec: CockpitSpec = _specs()[0]
	var console: ConsoleGauges = ConsoleGauges.new(spec.instruments)
	var hull: CockpitInstrument = _for_gauge(spec, ShipGauges.HULL)
	var energy: CockpitInstrument = _for_gauge(spec, ShipGauges.ENERGY)
	console.show_gauges(ShipGauges.of(0.8, 0.5, 0.6), 0.016)
	console.show_gauges(ShipGauges.of(0.1, 0.0, 0.6), 0.016)
	var problem: String = ""
	if not is_equal_approx(console.shown[hull.id], 0.1) or not is_equal_approx(console.shown[energy.id], 0.6):
		problem = "shown %s" % console.shown
	elif not console.is_low_shown(hull.id) or console.is_low_shown(energy.id):
		problem = "low hull %s, low energy %s" % [console.is_low_shown(hull.id), console.is_low_shown(energy.id)]
	elif console.low_frames[hull.id] != 1 or console.updates != 2:
		problem = "%d low frames of %d" % [console.low_frames[hull.id], console.updates]
	elif not is_equal_approx(console.time_s, 0.032):
		problem = "the pulse clock reads %s" % console.time_s
	else:
		var index: int = console.instruments.find(hull)
		var low: Color = console.bar_color(index)
		if not low.is_equal_approx(hull.bar_color(0.1, console.time_s)):
			problem = "the hull bar is drawn %s" % low
	console.free()
	return problem


func test_feeding_reads_the_gauges_and_writes_nothing_back() -> String:
	var ship: ShipState = ShipState.new()
	ship.hull = ship.max_hull * 0.2
	var before: Vector3 = Vector3(ship.hull, ship.shield, ship.energy)
	var gauges: ShipGauges = ShipGauges.take(ship, null)
	var frame: CockpitFrame = CockpitFrame.new(_specs()[2])
	ConsoleGauges.feed(frame, gauges, 0.1)
	ConsoleGauges.feed(null, gauges, 0.1)  # No frame: nothing to do, no error.
	var console: ConsoleGauges = ConsoleGauges.of_frame(frame)
	var problem: String = ""
	if console.updates != 1 or not is_equal_approx(console.shown["hull_bar"], 0.2):
		problem = "fed %d times, hull shown %s" % [console.updates, console.shown]
	elif Vector3(ship.hull, ship.shield, ship.energy) != before or not is_equal_approx(gauges.hull, 0.2):
		problem = "feeding changed the ship or the gauges"
	frame.free()
	return problem
