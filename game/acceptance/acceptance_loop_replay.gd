class_name AcceptanceLoopReplay
extends RefCounted

## The `loop_replay` step field (#788, PRF-3, DEV-6): a short recorded flight
## flown again and again, so the frame_budget check can measure a run as long
## as PRF-3 names (25 minutes) without a 25-minute replay file. Kept out of
## `AcceptanceSuite` and `AcceptanceRunner` so those files stay short.
##
## The inputs start again from the replay's first tick each time it ends
## (`ReplayInputSource`); the ship flies on from wherever it is, so the state
## after the first pass is not the recorded one. That is why a looping step
## may not list final_hash. The loop lasts as long as the frame_budget check
## is measuring (its `settle_seconds` plus `measure_seconds`). Where nothing
## measures frames (off the headset, where the check is skipped) the replay
## flies once, so the simulator and CI do not spend the soak's length on it.

const KEY: String = "loop_replay"


## Reads `loop_replay` from one suite step. Returns the problem, or "".
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has(KEY):
		return ""
	if typeof(data[KEY]) != TYPE_BOOL:
		return "%s.%s: must be true or false" % [field, KEY]
	step.loop_replay = data[KEY]
	if not step.loop_replay:
		return ""
	if step.replay_path == "":
		return "%s.%s: step '%s' lists no replay to loop" % [field, KEY, step.id]
	if step.has_check(AcceptanceStep.CHECK_FINAL_HASH):
		return "%s.%s: step '%s' loops its replay, so it has no final hash; drop final_hash" % [
			field, KEY, step.id]
	if not step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET):
		return "%s.%s: step '%s' needs the frame_budget check, whose seconds set how long it loops" % [
			field, KEY, step.id]
	return ""


## Whether the runner flies on past the replay's end: only a looping step,
## and only while its frames are still being measured.
static func keeps_flying(step: AcceptanceStep, frames: AcceptanceFrameBudgetCheck) -> bool:
	return step.loop_replay and frames != null and not frames.done()
