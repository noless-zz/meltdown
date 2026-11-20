class_name FlightTestSession
extends RefCounted

## Runs the first-launch flight test (CMF-4) through a `FlightTestPlan`: each
## segment flies for its `duration_s`, then waits for the pilot's answer, and
## the answers pick a preset through `PresetRecommender`.
##
## It is handed the time that passed and the answers; it reads no clock, node
## or input device, and holds no simulation state, so it cannot change what the
## simulation decides (ARC-3, CMF-6). The caller applies `preset_now()` to the
## comfort layer and, once `finished()`, `recommended()`.

## Preset given when the pilot skips the test or the plan was rejected: the
## safest, as `PresetRecommender` gives for no `fine` answer.
const SKIP_PRESET: int = FlightTestPlan.MIN_PRESET

var _plan: FlightTestPlan
var _index: int = 0
var _elapsed_s: float = 0.0
var _answers: Array[String] = []
var _finished: bool = false
var _skipped: bool = false


func _init(plan: FlightTestPlan) -> void:
	_plan = plan
	# A rejected or empty plan cannot be flown: the test is over at once.
	_finished = plan == null or plan.error != "" or plan.segments.is_empty()


## Counts `seconds` of the current segment. Time stops counting while an
## answer is due and once the test is over.
func advance(seconds: float) -> void:
	if _finished or awaiting_answer() or seconds <= 0.0:
		return
	_elapsed_s = minf(_elapsed_s + seconds, current_segment().duration_s)


## True when the current segment has flown its full time and needs an answer.
func awaiting_answer() -> bool:
	return not _finished and _elapsed_s >= current_segment().duration_s


## Takes `answer` (`fine`, `uneasy` or `stop`) for the current segment. Returns
## "" when taken; otherwise why it was refused, and nothing changes. The first
## answer other than `fine` ends the test, as does a `fine` on the last segment.
func answer(given: String) -> String:
	if _finished:
		return "the test is over"
	if not PresetRecommender.ANSWERS.has(given):
		return "answer \"%s\" must be one of %s" % [given, ", ".join(PackedStringArray(PresetRecommender.ANSWERS))]
	if not awaiting_answer():
		return "segment \"%s\" has %.1f s left" % [current_segment().id, seconds_left()]
	_answers.append(given)
	_index += 1
	_elapsed_s = 0.0
	if given != PresetRecommender.FINE or _index >= _plan.segments.size():
		_finished = true
	return ""


## Ends the test without more answers; the pilot gets `SKIP_PRESET`.
func skip() -> void:
	_finished = true
	_skipped = true


func finished() -> bool:
	return _finished


func skipped() -> bool:
	return _skipped


## The segment being flown or awaiting its answer; null once the test is over.
func current_segment() -> FlightTestSegment:
	if _finished:
		return null
	return _plan.segments[_index]


## Index of the current segment, from 0; the segment count once over.
func segment_index() -> int:
	return _index


func segment_count() -> int:
	return 0 if _plan == null else _plan.segments.size()


## Seconds the current segment still flies; 0 while an answer is due or once over.
func seconds_left() -> float:
	if _finished:
		return 0.0
	return maxf(current_segment().duration_s - _elapsed_s, 0.0)


## The preset to fly with now: the current segment's, then the recommendation.
func preset_now() -> int:
	if _finished:
		return recommended()
	return current_segment().preset


## The preset the answers so far recommend, 1..4; `SKIP_PRESET` when skipped
## or the plan could not be flown.
func recommended() -> int:
	if _skipped:
		return SKIP_PRESET
	var preset: int = PresetRecommender.recommend(_plan, _answers)
	return SKIP_PRESET if preset == PresetRecommender.INVALID else preset


## A copy of the answers taken so far.
func answers() -> Array[String]:
	return _answers.duplicate()
