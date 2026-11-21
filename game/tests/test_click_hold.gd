extends RefCounted

## One timer for the map click and the label hold (#335, #914, MAP-1, PLT-5,
## CMF-8): while the label button also toggles the map, `ComfortWiring.read_label_button`
## and `MapHologram` both answer from one `ClickHold`, so every press either
## toggles the map or flips the labels, never both and never neither.

## The clock starts here rather than at 0, as a steady clock does in play.
const ORIGIN_MS: int = 1_000_000
## Frames after the release that are still watched.
const TAIL_MS: int = 200


## A clock the test moves by hand.
class StepClock:
	var now: float = 0.0

	func read() -> float:
		return now


## What one press did: frames the map showed on, label flips, the time in ms
## after the press of the last flip and of the first frame the map showed, and
## whether the map was open at the end.
class PressResult:
	var map_frames: int = 0
	var flips: int = 0
	var flip_at_ms: int = -1
	var first_map_ms: int = -1
	var open_at_end: bool = false


## Frame length in ms at `t_ms` after the press for each frame pattern.
static func _step(pattern: String, t_ms: int) -> int:
	match pattern:
		"5ms":
			return 5
		"50ms":
			return 50
		"50ms_then_5ms":
			return 50 if t_ms < 350 else 5
		"5ms_then_50ms":
			return 5 if t_ms < 200 else 50
	return 11


## Presses the left stick click (the label button, which also shows the map by
## default) for `press_ms` on frames of `pattern`, through the wiring and the
## map as the main scene will drive them.
func _press(press_ms: int, pattern: String, mapping: ThumbstickMapping = null) -> PressResult:
	var map_mapping: ThumbstickMapping = mapping if mapping != null else ThumbstickMapping.new()
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), map_mapping)
	var clock: StepClock = StepClock.new()
	wiring.clock = clock.read
	var map: MapHologram = MapHologram.new()
	var result: PressResult = PressResult.new()
	var t_ms: int = 0
	while t_ms <= press_ms + TAIL_MS:
		clock.now = float(ORIGIN_MS + t_ms) / 1000.0
		var buttons: Dictionary = {"left_stick_click": t_ms < press_ms}
		if wiring.read_label_button(buttons):
			result.flips += 1
			result.flip_at_ms = t_ms
		map.read(map_mapping, buttons, wiring.shared_click_hold())
		if map.visible:
			result.map_frames += 1
			if result.first_map_ms < 0:
				result.first_map_ms = t_ms
		t_ms += _step(pattern, t_ms)
	result.open_at_end = map.visible
	map.free()
	return result


func test_presses_at_the_edge_do_exactly_one_thing() -> String:
	# 400 ms is the threshold; the frame at 400 ms already sees the release.
	var expected: Dictionary[int, String] = {390: "map", 400: "map", 410: "labels"}
	for press_ms: int in expected:
		var result: PressResult = _press(press_ms, "5ms")
		var did: String = "map" if result.open_at_end else "labels"
		if result.open_at_end == (result.flips > 0) or result.flips > 1:
			return "a %d ms press left the map %s and flipped %d times" % [
				press_ms, "open" if result.open_at_end else "closed", result.flips]
		if did != expected[press_ms]:
			return "a %d ms press did %s, want %s" % [press_ms, did, expected[press_ms]]
	return ""


func test_a_hold_flips_once_at_the_threshold_and_never_shows_the_map() -> String:
	var result: PressResult = _press(1000, "5ms")
	var threshold_ms: int = roundi(MapHologram.HOLD_SECONDS * 1000.0)
	if result.flips != 1 or result.flip_at_ms != threshold_ms:
		return "a 1 s hold flipped %d times, last at %d ms; want once at %d ms" % [
			result.flips, result.flip_at_ms, threshold_ms]
	if result.map_frames != 0:
		return "a 1 s hold showed the map on %d frames" % result.map_frames
	return ""


func test_a_click_opens_the_map_on_release_and_it_stays_open() -> String:
	var result: PressResult = _press(100, "5ms")
	if result.flips != 0:
		return "a 100 ms click flipped the labels %d times" % result.flips
	if result.first_map_ms != 100:
		return "the map first showed at %d ms, want 100 (the release)" % result.first_map_ms
	if not result.open_at_end or result.map_frames != TAIL_MS / 5 + 1:
		return "the map closed again with the button released (%d frames)" % result.map_frames
	return ""


func test_a_second_click_closes_the_map() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), mapping)
	var clock: StepClock = StepClock.new()
	wiring.clock = clock.read
	var map: MapHologram = MapHologram.new()
	var seen: Array[bool] = []
	for pressed: bool in [true, false, false, true, false, true, false]:
		clock.now += 0.1
		var buttons: Dictionary = {"left_stick_click": pressed}
		wiring.read_label_button(buttons)
		map.read(mapping, buttons, wiring.shared_click_hold())
		seen.append(map.visible)
	map.free()
	# Each click acts on its release: open, closed, open again.
	if seen != [false, true, true, true, false, false, true]:
		return "three clicks left the map %s" % str(seen)
	return ""


func test_a_hold_leaves_an_open_map_open() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), mapping)
	var clock: StepClock = StepClock.new()
	wiring.clock = clock.read
	var map: MapHologram = MapHologram.new()
	var flips: int = 0
	for step: Array in [[true, 0.1], [false, 0.1], [true, 0.1], [true, 0.5], [true, 0.5], [false, 0.1]]:
		clock.now += float(step[1])
		var buttons: Dictionary = {"left_stick_click": step[0]}
		if wiring.read_label_button(buttons):
			flips += 1
		map.read(mapping, buttons, wiring.shared_click_hold())
	var open: bool = map.visible
	map.free()
	if not open or flips != 1:
		return "a hold with the map open left it %s and flipped %d times" % [
			"open" if open else "closed", flips]
	return ""


func test_uneven_frames_give_the_same_answers() -> String:
	for pattern: String in ["5ms", "50ms", "50ms_then_5ms", "5ms_then_50ms"]:
		for press_ms: int in [390, 400, 410]:
			var result: PressResult = _press(press_ms, pattern)
			var map: bool = result.open_at_end
			if map == (result.flips == 1) or result.flips > 1:
				return "%s frames: a %d ms press left the map %s and flipped %d times" % [
					pattern, press_ms, "open" if map else "closed", result.flips]
			if map != (press_ms != 410):
				return "%s frames: a %d ms press %s the map" % [
					pattern, press_ms, "opened" if map else "did not open"]
	return ""


func test_remapped_show_map_keeps_flip_on_press() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.layout["show_map"] = {"left_button_upper": 1.0}
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), mapping)
	if wiring.shared_click_hold() != null:
		return "with show_map on Y the map still shares the label click"
	var result: PressResult = _press(1000, "5ms", mapping)
	if result.flips != 1 or result.flip_at_ms != 0:
		return "a 1 s press flipped %d times, last at %d ms; want once on press" % [
			result.flips, result.flip_at_ms]
	if result.map_frames != 0:
		return "the stick click showed the map with show_map on Y"
	# Alone on its control, the map toggles on each press of it.
	var map: MapHologram = MapHologram.new()
	var seen: Array[bool] = []
	for pressed: bool in [true, true, false, true, false]:
		map.read(mapping, {"left_button_upper": pressed}, wiring.shared_click_hold())
		seen.append(map.visible)
	map.free()
	if seen != [true, true, true, false, false]:
		return "pressing Y twice left the remapped map %s" % str(seen)
	return ""


func test_one_press_never_gives_both_answers() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 335
	for trial: int in 300:
		var hold: ClickHold = ClickHold.new()
		var press_s: float = rng.randf_range(0.3, 0.5)
		var now: float = rng.randf_range(0.0, 5000.0)
		var start: float = now
		var long_frames: int = 0
		var clicks: int = 0
		while now - start < press_s + 0.2:
			hold.feed(now - start < press_s, now)
			if hold.long_hold_started():
				long_frames += 1
			if hold.short_click_released():
				clicks += 1
			now += rng.randf_range(0.002, 0.06)
		if (long_frames == 1) == (clicks == 1) or clicks > 1 or long_frames > 1:
			return "a %.3f s press gave %d long frames and %d clicks" % [press_s, long_frames, clicks]
	return ""
