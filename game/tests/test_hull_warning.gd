extends RefCounted

## The low-hull warning's beat (#1456, AUD-1, CMB-2, MP-2): silent above the
## threshold, a tone on the frame the hull reaches it and then every interval,
## faster in the low band, and silent again when the hull rises, when the caller
## silences it (run end, end screens) and after a reset. The speaker sits on the
## dash in front of the head point.

const DT: float = 1.0 / 60.0
const TABLE: String = "{\"threshold\": 0.25, \"interval_s\": 1.0, \"fast_threshold\": 0.1, \"fast_interval_s\": 0.5, \"sound\": \"res://data/audio/hull_warning.wav\", \"volume_db\": -12.0}"


func _warning() -> HullWarning:
	var warning: HullWarning = HullWarning.new(HullWarningTable.parse(TABLE))
	warning.enabled = false
	return warning


## The frames, from 0, on which a tone was asked for over `frames` frames.
func _beats(warning: HullWarning, hull: float, frames: int, silenced: bool = false) -> Array[int]:
	var at: Array[int] = []
	for frame: int in frames:
		if warning.update(hull, DT, silenced, Transform3D.IDENTITY):
			at.append(frame)
	return at


func test_silent_above_the_threshold() -> String:
	var warning: HullWarning = _warning()
	var at: Array[int] = _beats(warning, 0.26, 300)
	return "" if at.is_empty() and warning.requested == 0 else "tones above the threshold on frames %s" % [at]


func test_a_tone_at_once_then_every_interval() -> String:
	var warning: HullWarning = _warning()
	var at: Array[int] = _beats(warning, 0.2, 181)
	if at != [0, 60, 120, 180]:
		return "tones at 1 s should fall on frames 0, 60, 120, 180, not %s" % [at]
	if warning.requested != 4 or warning.beat_hulls != [0.2, 0.2, 0.2, 0.2]:
		return "the log holds %d tones at %s" % [warning.requested, warning.beat_hulls]
	return ""


func test_faster_in_the_low_band() -> String:
	var warning: HullWarning = _warning()
	_beats(warning, 0.2, 10)  # Tone on frame 0; the next was 50 frames off.
	var at: Array[int] = _beats(warning, 0.05, 91)
	if at.is_empty() or at[0] > 30:
		return "falling into the low band did not bring the next tone within 0.5 s: %s" % [at]
	for i: int in range(1, at.size()):
		if at[i] - at[i - 1] != 30:
			return "low-band tones should be 30 frames apart: %s" % [at]
	return ""


func test_stops_when_the_hull_rises_and_starts_again_when_it_falls() -> String:
	var warning: HullWarning = _warning()
	_beats(warning, 0.2, 30)
	if not _beats(warning, 0.6, 300).is_empty():
		return "tones after the hull rose above the threshold"
	if _beats(warning, 0.2, 1) != [0]:
		return "falling to the threshold again did not sound at once"
	return ""


func test_silenced_at_run_end_whatever_the_hull() -> String:
	var warning: HullWarning = _warning()
	_beats(warning, 0.2, 30)
	var before: int = warning.requested
	if not _beats(warning, 0.0, 300, true).is_empty() or warning.requested != before:
		return "tones while silenced"
	return ""


func test_reset_clears_the_log_and_the_beat() -> String:
	var warning: HullWarning = _warning()
	_beats(warning, 0.2, 30)
	warning.reset()
	if warning.requested != 0 or not warning.beat_hulls.is_empty():
		return "reset left %d tones in the log" % warning.requested
	if _beats(warning, 0.2, 1) != [0]:
		return "the first low frame after a reset did not sound"
	return ""


func test_a_rejected_table_stays_silent() -> String:
	var warning: HullWarning = HullWarning.new(HullWarningTable.parse("{\"interval_s\": -1}"))
	warning.enabled = false
	var at: Array[int] = _beats(warning, 0.0, 120)
	return "" if at.is_empty() else "a rejected table sounded on frames %s" % [at]


func test_the_speaker_sits_on_the_dash_ahead_of_the_head() -> String:
	var rig: Node3D = Node3D.new()
	var warning: HullWarning = _warning()
	warning.attach(rig)
	warning.attach(rig)
	var problem: String = ""
	if rig.get_child_count() != 1 or warning.player == null:
		problem = "attach twice made %d speakers" % rig.get_child_count()
	else:
		var head: Transform3D = Transform3D(Basis(), Vector3(0.0, 1.6, 0.0))
		warning.update(1.0, DT, false, head)
		var spot: Vector3 = warning.player.position
		if spot.y >= 1.6 or spot.z >= 0.0:
			problem = "the speaker at %s is not below and ahead of the head at %s" % [spot, head.origin]
		elif AudioServer.get_bus_index(RoomReverb.BUS) >= 0 and warning.player.bus != RoomReverb.BUS:
			problem = "the speaker plays on %s, not %s" % [warning.player.bus, RoomReverb.BUS]
	rig.free()
	return problem


func test_the_destroyed_wiring_carries_the_warning_and_resets_it() -> String:
	var wiring: DestroyedWiring = DestroyedWiring.new()
	if wiring.hull_warning == null or wiring.hull_warning.table.error != "":
		return "the wiring has no working warning"
	wiring.hull_warning.enabled = false
	wiring.hull_warning.update(0.1, DT, false, Transform3D.IDENTITY)
	wiring.reset()
	return "" if wiring.hull_warning.requested == 0 else "the wiring's reset kept the warning's log"
