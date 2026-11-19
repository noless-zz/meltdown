extends RefCounted

## One timer for the map hold and the label click (#335, MAP-1, PLT-5, CMF-8):
## while the label button also shows the map, `ComfortWiring.read_label_button`
## and `MapHologram` both answer from one `ClickHold`, so every press either
## shows the map or flips the labels, never both and never neither.

## The clock starts here rather than at 0, as a steady clock does in play.
const ORIGIN_MS: int = 1_000_000
## Frames after the release that are still watched.
const TAIL_MS: int = 200


## A clock the test moves by hand.
class StepClock:
	var now: float = 0.0

	func read() -> float:
		return now


## What one press did: frames the map showed on, label flips, and the time in
## ms after the press of the first and last frame the map showed.
class PressResult:
	var map_frames: int = 0
	var flips: int = 0
	var flip_at_ms: int = -1
	var first_map_ms: int = -1
	var last_map_ms: int = -1


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
	var delta: float = 0.0
	while t_ms <= press_ms + TAIL_MS:
		clock.now = float(ORIGIN_MS + t_ms) / 1000.0
		var buttons: Dictionary = {"left_stick_click": t_ms < press_ms}
		if wiring.read_label_button(buttons):
			result.flips += 1
			result.flip_at_ms = t_ms
		map.read(map_mapping, buttons, delta, wiring.shared_click_hold())
		if map.visible:
			result.map_frames += 1
			result.last_map_ms = t_ms
			if result.first_map_ms < 0:
				result.first_map_ms = t_ms
		var step: int = _step(pattern, t_ms)
		delta = float(step) / 1000.0
		t_ms += step
	map.free()
	return result


func test_presses_at_the_edge_do_exactly_one_thing() -> String:
	# 400 ms is the threshold; the frame at 400 ms already sees the release.
	var expected: Dictionary[int, String] = {390: "labels", 400: "labels", 410: "map"}
	for press_ms: int in expected:
		var result: PressResult = _press(press_ms, "5ms")
		var did: String = "map" if result.map_frames > 0 else "labels"
		if (result.map_frames > 0) == (result.flips > 0) or result.flips > 1:
			return "a %d ms press showed the map on %d frames and flipped %d times" % [
				press_ms, result.map_frames, result.flips]
		if did != expected[press_ms]:
			return "a %d ms press did %s, want %s" % [press_ms, did, expected[press_ms]]
	return ""


func test_a_hold_shows_the_map_until_release_and_never_flips() -> String:
	var result: PressResult = _press(1000, "5ms")
	if result.flips != 0:
		return "a 1 s hold flipped the labels %d times" % result.flips
	var threshold_ms: int = roundi(MapHologram.HOLD_SECONDS * 1000.0)
	if result.first_map_ms != threshold_ms:
		return "the map first showed at %d ms, want %d" % [result.first_map_ms, threshold_ms]
	if result.last_map_ms != 995:
		return "the map last showed at %d ms, want 995 (the frame before release)" % result.last_map_ms
	if result.map_frames != (995 - threshold_ms) / 5 + 1:
		return "the map showed on %d frames, so it blinked during the hold" % result.map_frames
	return ""


func test_a_quick_click_flips_once_on_release() -> String:
	var result: PressResult = _press(100, "5ms")
	if result.flips != 1 or result.flip_at_ms != 100:
		return "a 100 ms click flipped %d times, last at %d ms" % [result.flips, result.flip_at_ms]
	if result.map_frames != 0:
		return "a 100 ms click showed the map"
	return ""


func test_uneven_frames_give_the_same_answers() -> String:
	for pattern: String in ["5ms", "50ms", "50ms_then_5ms", "5ms_then_50ms"]:
		for press_ms: int in [390, 400, 410]:
			var result: PressResult = _press(press_ms, pattern)
			var map: bool = result.map_frames > 0
			if map == (result.flips == 1) or result.flips > 1:
				return "%s frames: a %d ms press showed the map on %d frames and flipped %d times" % [
					pattern, press_ms, result.map_frames, result.flips]
			if map != (press_ms == 410):
				return "%s frames: a %d ms press %s the map" % [
					pattern, press_ms, "showed" if map else "did not show"]
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
	# The map keeps timing its own control with frame deltas.
	var map: MapHologram = MapHologram.new()
	for i: int in 50:
		map.read(mapping, {"left_button_upper": true}, 0.01, wiring.shared_click_hold())
	var shown: bool = map.visible
	map.free()
	if not shown:
		return "holding Y for 0.5 s did not show the remapped map"
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
			if hold.is_long_hold():
				long_frames += 1
			if hold.short_click_released():
				clicks += 1
			now += rng.randf_range(0.002, 0.06)
		if (long_frames > 0) == (clicks == 1) or clicks > 1:
			return "a %.3f s press gave %d long frames and %d clicks" % [press_s, long_frames, clicks]
	return ""
