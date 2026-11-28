extends RefCounted

## The `hull_warning` check (#1456, AUD-1, CMB-2, DEV-6, decision record 0005),
## lane-b's file under `acceptance/checks/`. In `suites/m6/sound.json`:
##
##     {"id": "hull_warning",
##      "replay": "res://acceptance/replays/low_hull_test_tunnel.replay",
##      "checks": ["final_hash", "outcome", "hull_warning"], "expected_outcome": "LOST"}
##
## The replay flies through the scene's own frames, so the tone is driven by the
## real wiring (`DestroyedWiring.hull_warning`). The replay is the m2
## `ship_destroyed_test_tunnel` flight with the ship's `max_hull` doubled to 200
## and 148 idle ticks added: with 100 the ship is lost 10 ticks after crossing
## the threshold, too soon for a second tone; with 200 the hull stays low for
## about 1.8 s before the robots finish it on tick 459. The check passes when
## the tone was asked for at least twice, every time while the ship still had
## hull, and not once more over a few further seconds of the end screen. Whether it is noticeable and
## not annoying in a fight stays a headset check.

const CHECK: String = "hull_warning"
const LEAST_BEATS: int = 2
## Frames flown after the replay, under the end screen: longer than any interval.
const AFTER_FRAMES: int = 180


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if destroyed == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no destroyed wiring"]
	var warning: HullWarning = destroyed.hull_warning
	if warning.table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the hull warning file was refused: %s" % warning.table.error]
	var heard: Array[float] = warning.beat_hulls.duplicate()
	var during: int = warning.requested
	for i: int in AFTER_FRAMES:
		main.call("apply_controls", ControllerSampler.idle_values())
		main.call("advance_frame", ShipState.TICK_DT)
	var after: int = warning.requested - during
	measurements["hull_warning_beats"] = during
	measurements["hull_warning_after_end"] = after
	return judge_beats(heard, during, after, warning.table.threshold)


## Pass or fail for `during` tones at hull fractions `heard` (the newest kept)
## while the replay flew and `after` more once it had ended.
static func judge_beats(heard: Array[float], during: int, after: int, threshold: float) -> Array:
	if during < LEAST_BEATS:
		return [AcceptanceReport.RESULT_FAIL, "the tone was asked for %d times, not at least %d" % [during, LEAST_BEATS]]
	for hull: float in heard:
		if hull <= 0.0 or hull > threshold:
			return [AcceptanceReport.RESULT_FAIL, "a tone sounded at hull %.3f, outside (0, %.2f]" % [hull, threshold]]
	if after > 0:
		return [AcceptanceReport.RESULT_FAIL, "the tone was asked for %d more times after the run ended" % after]
	return [AcceptanceReport.RESULT_PASS, "%d tones while the hull was low (lowest %.3f), none after the run ended"
		% [during, heard.min()]]
