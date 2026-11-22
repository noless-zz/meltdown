extends RefCounted

## Where and how the run sweep's lost runs ended (#1195, RUN-1, CRW-3, DEV-6).
## The owner said most bot losses are on level 1 and that a level too hard for
## him too is a balance fix (Status #1, 22 Nov); a balance fix needs to know on
## which level runs are lost and whether the ship was destroyed, ran out of
## time, or met a level that could not be flown. Kept apart from
## `bot_run_sweep.gd` so the sweep stays under its size limit.
##
## The summary line gains
## `,"lost_by_level":[l1,l2,...],"lost_by_outcome":{"destroyed":D,"timed_out":T,"not_flown":N}`
## before its closing brace. `lost_by_level` is as long as the deepest level a
## run was lost on, so a sweep with no loss writes `[]`. Every run that is not
## completed is lost on exactly one level, so both add up to runs - completed.

const DESTROYED: String = "destroyed"
const TIMED_OUT: String = "timed_out"
const NOT_FLOWN: String = "not_flown"
## The order the outcome counts are written in.
const OUTCOMES: Array[String] = [DESTROYED, TIMED_OUT, NOT_FLOWN]


## How the level `flown` ended, for a level that was not escaped: the ship
## destroyed; never flown at all (no level or no reactor, `EscapeSweep.fly`'s
## "NO_LEVEL" and "NO_REACTOR"); otherwise timed out, which is the countdown run
## out or the bot still flying at the tick limit.
static func outcome_of(flown_outcome: String, destroyed: bool) -> String:
	if flown_outcome.begins_with("NO_"):
		return NOT_FLOWN
	if destroyed:
		return DESTROYED
	return TIMED_OUT


## The empty tally a sweep result starts with.
static func empty() -> Dictionary:
	var by_outcome: Dictionary[String, int] = {}
	for outcome: String in OUTCOMES:
		by_outcome[outcome] = 0
	return {"lost_by_level": [] as Array[int], "lost_by_outcome": by_outcome}


## Counts one run lost on level number `level` (1 for the first) in `tally`.
static func add(tally: Dictionary, level: int, outcome: String) -> void:
	var by_level: Array[int] = tally["lost_by_level"]
	while by_level.size() < level:
		by_level.append(0)
	by_level[level - 1] += 1
	tally["lost_by_outcome"][outcome] += 1


## The fields the summary line gains, starting with a comma.
static func summary_fields(tally: Dictionary) -> String:
	var levels: PackedStringArray = []
	for count: int in tally["lost_by_level"]:
		levels.append(str(count))
	var outcomes: PackedStringArray = []
	for outcome: String in OUTCOMES:
		outcomes.append('"%s":%d' % [outcome, tally["lost_by_outcome"][outcome]])
	return ',"lost_by_level":[%s],"lost_by_outcome":{%s}' % [",".join(levels), ",".join(outcomes)]
