extends RefCounted

## Foveation keep-or-revert (#1523, part 4 of #734; CMF-8, PRF-1, ARC-3): a
## change made in the dev menu reverts by itself when the timer ends unless A
## is held long enough; a short press does not confirm, nor does the press that
## chose it; closing the menu or losing focus reverts; a second change while
## waiting reverts to the setting from before the first. The interface is
## `fake_foveation_runtime.gd` and the clock is the `now` each frame is given.

const FakeRuntime: GDScript = preload("res://tests/fake_foveation_runtime.gd")
const FRAME: float = 1.0 / 72.0
var NONE: PackedStringArray = PackedStringArray()


## A keep on a switch running on a fake interface at `level` / `dynamic`. Returns [keep, runtime].
func _keep(level: int = 0, dynamic: bool = false) -> Array:
	var runtime: RefCounted = FakeRuntime.new(level, dynamic)
	var chosen: FoveationSwitch = FoveationSwitch.parse(NONE, "", "")
	chosen.begin(runtime)
	return [FoveationKeep.new(chosen, FoveationKeepSpec.built_in()), runtime]


## Frames from `from` to `to` seconds with A held or not, menu open.
static func _run(keep: FoveationKeep, held: bool, from: float, to: float) -> void:
	var now: float = from
	while now < to - 0.0001:
		keep.update(held, true, now)
		now += FRAME
	keep.update(held, true, to)


static func _in_use(runtime: RefCounted) -> Vector2i:
	return Vector2i(int(runtime.get("foveation_level")), int(bool(runtime.get("foveation_dynamic"))))


func test_without_a_confirm_the_previous_setting_returns_when_the_timer_ends() -> String:
	var made: Array = _keep()
	var keep: FoveationKeep = made[0]
	keep.choose(3, true)
	if _in_use(made[1]) != Vector2i(3, 1):
		return "the change was not applied at once: %s" % _in_use(made[1])
	keep.update(true, true, 0.0)  # The press of A that chose it, still down.
	_run(keep, false, 0.1, 14.9)
	if not keep.is_waiting() or _in_use(made[1]) != Vector2i(3, 1):
		return "it reverted before the 15 s timer"
	_run(keep, false, 14.9, 15.0)
	if keep.is_waiting() or _in_use(made[1]) != Vector2i(0, 0):
		return "after the timer the interface holds %s" % _in_use(made[1])
	var line: String = keep.switch.lines[-1]
	if line != FoveationSwitch.format_line(0, false, FoveationSwitch.SOURCE_REVERT):
		return "the last line was %s" % line
	return "" if keep.cues == ["start", "reverted"] else "cues were %s" % [keep.cues]


func test_a_long_press_of_a_keeps_the_new_setting() -> String:
	var made: Array = _keep(1, false)
	var keep: FoveationKeep = made[0]
	keep.choose(2, true)
	keep.update(true, true, 0.0)
	_run(keep, false, 0.1, 1.0)
	_run(keep, true, 1.0, 2.4)
	if not keep.is_waiting():
		return "a 1.4 s hold kept it; the hold is 1.5 s"
	_run(keep, true, 2.4, 2.6)
	if keep.is_waiting():
		return "a 1.6 s hold did not keep it"
	_run(keep, false, 2.6, 40.0)
	if _in_use(made[1]) != Vector2i(2, 1):
		return "the kept setting reverted to %s" % _in_use(made[1])
	return "" if keep.cues == ["start", "kept"] else "cues were %s" % [keep.cues]


func test_a_short_press_and_the_choosing_press_do_not_confirm() -> String:
	var made: Array = _keep()
	var keep: FoveationKeep = made[0]
	keep.choose(3, false)
	_run(keep, true, 0.0, 3.0)  # The choosing press held on: never counts.
	if not keep.is_waiting():
		return "holding on from the choosing press kept the setting"
	_run(keep, false, 3.0, 4.0)
	_run(keep, true, 4.0, 5.0)  # A one-second press.
	_run(keep, false, 5.0, 6.0)
	_run(keep, true, 6.0, 7.0)  # And another: they do not add up.
	_run(keep, false, 7.0, 15.0)
	if keep.is_waiting() or _in_use(made[1]) != Vector2i(0, 0):
		return "short presses kept %s" % _in_use(made[1])
	return ""


func test_a_second_change_while_waiting_reverts_to_the_setting_before_the_first() -> String:
	var made: Array = _keep(1, false)
	var keep: FoveationKeep = made[0]
	keep.choose(2, false)
	_run(keep, false, 0.0, 5.0)
	keep.choose(3, true)
	_run(keep, false, 5.0, 19.9)
	if not keep.is_waiting() or _in_use(made[1]) != Vector2i(3, 1):
		return "the second change did not restart the timer"
	keep.choose(3, true)  # A again on the same setting: not a change.
	_run(keep, false, 19.9, 20.0)
	if keep.is_waiting() or _in_use(made[1]) != Vector2i(1, 0):
		return "it reverted to %s, not the setting before the first change" % _in_use(made[1])
	var back: Array = _keep(1, false)
	(back[0] as FoveationKeep).choose(2, false)
	(back[0] as FoveationKeep).choose(1, false)  # Chosen back by hand: nothing to keep.
	if (back[0] as FoveationKeep).is_waiting():
		return "choosing the earlier setting again still waits"
	return "" if keep.cues == ["start", "start", "reverted"] else "cues were %s" % [keep.cues]


func test_closing_the_menu_or_losing_focus_counts_as_no_confirm() -> String:
	var closed: Array = _keep()
	var keep: FoveationKeep = closed[0]
	keep.choose(3, true)
	_run(keep, false, 0.0, 2.0)
	keep.update(false, false, 2.1)
	if keep.is_waiting() or _in_use(closed[1]) != Vector2i(0, 0):
		return "closing the menu left %s" % _in_use(closed[1])
	var lost: Array = _keep()
	(lost[0] as FoveationKeep).choose(2, false)
	_run(lost[0], true, 0.0, 1.0)
	(lost[0] as FoveationKeep).cancel()
	if (lost[0] as FoveationKeep).is_waiting() or _in_use(lost[1]) != Vector2i(0, 0):
		return "a focus loss left %s" % _in_use(lost[1])
	(lost[0] as FoveationKeep).cancel()  # Nothing waiting: nothing happens.
	return "" if (lost[0] as FoveationKeep).cues == ["start", "reverted"] else "cues were %s" % [(lost[0] as FoveationKeep).cues]


func test_the_file_holds_the_times_and_a_bad_file_keeps_the_built_in_values() -> String:
	var shipped: FoveationKeepSpec = FoveationKeepSpec.load_file()
	if shipped.error != "" or shipped.keep_seconds != 15.0 or shipped.hold_seconds != 1.5:
		return "the shipped file read %s / %s (%s)" % [shipped.keep_seconds, shipped.hold_seconds, shipped.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FoveationKeepSpec.DEFAULT_FILE))
	data["keep_seconds"] = 8
	var short: FoveationKeepSpec = FoveationKeepSpec.parse(JSON.stringify(data))
	if short.error != "" or short.keep_seconds != 8.0:
		return "keep_seconds 8 read %s (%s)" % [short.keep_seconds, short.error]
	var bad: Array[Array] = [["keep_seconds", 31], ["hold_seconds", "long"], ["tones", []]]
	for pair: Array in bad:
		var edited: Dictionary = data.duplicate(true)
		edited[pair[0]] = pair[1]
		var spec: FoveationKeepSpec = FoveationKeepSpec.parse(JSON.stringify(edited))
		if not spec.error.contains(pair[0]) or spec.keep_seconds != 15.0:
			return "%s = %s gave \"%s\" and %s s" % [pair[0], pair[1], spec.error, spec.keep_seconds]
	var no_pulse: Dictionary = data.duplicate(true)
	no_pulse["pulses"]["kept"].erase("amplitude")
	if not FoveationKeepSpec.parse(JSON.stringify(no_pulse)).error.contains("pulses.kept.amplitude"):
		return "a missing pulse amplitude was accepted"
	return "" if FoveationKeepSpec.load_file("res://none.json").hold_seconds == 1.5 else "a missing file has no hold"


func test_the_tones_are_low_rising_and_falling_and_sound_from_the_head() -> String:
	var spec: FoveationKeepSpec = FoveationKeepSpec.load_file()
	var start: Dictionary = spec.tones["start"]
	var kept: Dictionary = spec.tones["kept"]
	var reverted: Dictionary = spec.tones["reverted"]
	if start["from_hz"] != start["to_hz"] or kept["to_hz"] <= kept["from_hz"] \
			or reverted["to_hz"] >= reverted["from_hz"] or start["from_hz"] > kept["from_hz"]:
		return "the tones are not low, rising and falling: %s" % [spec.tones]
	var wav: AudioStreamWAV = FoveationKeepCue.sweep(440.0, 880.0, 0.3)
	if wav.data.size() != int(0.3 * FoveationKeepCue.MIX_RATE) * 2 or wav.stereo:
		return "a 0.3 s tone has %d bytes" % wav.data.size()
	if absi(wav.data.decode_s16(0)) > 100 or absi(wav.data.decode_s16(wav.data.size() - 2)) > 2000:
		return "the tone starts or ends with a click"
	var rig: Node3D = (load("res://xr/xr_rig.tscn") as PackedScene).instantiate()
	var keep: FoveationKeep = _keep()[0]
	var cue: FoveationKeepCue = FoveationKeepCue.attach_to(rig, keep)
	cue.enabled = false
	keep.choose(1, false)
	keep.cancel()
	var parent: String = str(cue.get_parent().name)
	var hands: bool = cue.left_controller != null and cue.right_controller != null
	var played: Array[String] = cue.played
	rig.free()
	if parent != "Camera" or not hands:
		return "the cue hangs under %s, hands found: %s" % [parent, hands]
	return "" if played == ["start", "reverted"] else "the cue played %s" % [played]


func test_through_the_menu_a_change_reverts_and_a_held_a_keeps_it() -> String:
	var runtime: RefCounted = FakeRuntime.new(0, false)
	var chosen: FoveationSwitch = FoveationSwitch.parse(NONE, "", "")
	chosen.begin(runtime)
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), null, null, null, chosen)
	wiring.attach(null, null, null, Callable(), null, null)
	var now: float = _open(wiring, 10.0)
	now = DevMenuWalk.select_wired(wiring, DevMenuSpec.KIND_FOVEATION, now)
	now = DevMenuWalk.press_wired(wiring, DevMenuModel.RIGHT, now)
	now = DevMenuWalk.press_wired(wiring, DevMenuModel.CONFIRM, now)
	var applied: Vector2i = _in_use(runtime)
	for i: int in 16 * 72:
		now += FRAME
		wiring.read(DevMenuWalk.controls(""), now)
	var reverted: Vector2i = _in_use(runtime)
	var shown: Vector2i = wiring.menu.model.foveation
	now = DevMenuWalk.press_wired(wiring, DevMenuModel.RIGHT, now)
	now = DevMenuWalk.press_wired(wiring, DevMenuModel.CONFIRM, now)
	for i: int in 2 * 72:  # A down again and held two seconds.
		now += FRAME
		wiring.read(DevMenuWalk.controls(DevMenuModel.CONFIRM), now)
	for i: int in 20 * 72:
		now += FRAME
		wiring.read(DevMenuWalk.controls(""), now)
	var kept: Vector2i = _in_use(runtime)
	wiring.menu.free()
	if applied != Vector2i(1, 0) or reverted != Vector2i(0, 0) or shown != Vector2i(0, 0):
		return "chose %s, then the interface held %s and the menu showed %s" % [applied, reverted, shown]
	return "" if kept == Vector2i(1, 0) else "after a held A the interface holds %s" % kept


static func _open(wiring: DevMenuWiring, at: float) -> float:
	var tap: Dictionary = ControllerSampler.idle_values()
	tap["buttons"] = {ControllerSampler.MENU_BUTTON: true}
	wiring.read(tap, at)
	wiring.read(DevMenuWalk.controls(""), at + 0.2)
	return at + 0.4
