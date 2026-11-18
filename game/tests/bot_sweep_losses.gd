extends RefCounted

## When and against how many awake robots the bot sweep's lost flights died
## (#534, DEV-6, CMB-3, GEN-3). Robot density can only be tuned on evidence:
## early losses near the start point at ambushes, late ones at attrition. Kept
## apart from `bot_escape_sweep.gd` so the sweep stays one job per file.
##
## A lost seed is one whose ship was destroyed before its reactor. Each is kept
## as `{"seed": S, "tick": T, "awake": A}` and printed, one per line, as
## `MELTDOWN_BOT_LOST {"seed":S,"seconds":X,"awake":A}`, so the nightly combine
## step can take the median over every shard's lost seeds.

const LOST_TAG: String = "MELTDOWN_BOT_LOST"
## Bucket edges in ticks, so a loss on exactly 10 s or 60 s lands the same way
## on every machine: under 10 s is `tick < EARLY_TICKS`, over 60 s is
## `tick > LATE_TICKS`, the rest is 10 to 60 s.
const EARLY_TICKS: int = 10 * ShipState.TICK_RATE
const LATE_TICKS: int = 60 * ShipState.TICK_RATE


## Robots alive and awake in `sim` right now; read only (MP-2).
static func awake_robots(sim: Sim) -> int:
	var awake: int = 0
	for robot: RobotState in sim.robots:
		if robot.is_alive() and robot.awake:
			awake += 1
	return awake


## "lost_under_10_s", "lost_10_to_60_s" or "lost_over_60_s" for a loss at `tick`.
static func bucket(tick: int) -> String:
	if tick < EARLY_TICKS:
		return "lost_under_10_s"
	if tick > LATE_TICKS:
		return "lost_over_60_s"
	return "lost_10_to_60_s"


## The three bucket counts over `lost`, every key present.
static func buckets(lost: Array[Dictionary]) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {"lost_under_10_s": 0, "lost_10_to_60_s": 0,
			"lost_over_60_s": 0}
	for entry: Dictionary in lost:
		counts[bucket(entry["tick"])] += 1
	return counts


## The median awake count over `lost`: the middle value, or the mean of the
## two middle values for an even count. -1.0 when nothing was lost.
static func awake_median(lost: Array[Dictionary]) -> float:
	if lost.is_empty():
		return -1.0
	var values: Array[int] = []
	for entry: Dictionary in lost:
		values.append(entry["awake"])
	values.sort()
	var middle: int = values.size() / 2
	if values.size() % 2 == 1:
		return float(values[middle])
	return (values[middle - 1] + values[middle]) / 2.0


## The fields a robot summary line gains, starting with a comma; the median is
## `null` when nothing was lost, since 0 would read as "no robots awake".
static func summary_fields(lost: Array[Dictionary]) -> String:
	var counts: Dictionary[String, int] = buckets(lost)
	var median: float = awake_median(lost)
	return ',"lost_under_10_s":%d,"lost_10_to_60_s":%d,"lost_over_60_s":%d,"lost_awake_median":%s' % [
			counts["lost_under_10_s"], counts["lost_10_to_60_s"], counts["lost_over_60_s"],
			"null" if median < 0.0 else "%.1f" % median]


## One `MELTDOWN_BOT_LOST` line per lost seed, in the order given.
static func lines(lost: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in lost:
		out.append('%s {"seed":%d,"seconds":%.2f,"awake":%d}' % [LOST_TAG, entry["seed"],
				entry["tick"] * ShipState.TICK_DT, entry["awake"]])
	return out
