class_name MinerChecks
extends RefCounted

## The `miners_reachable` check of `LevelValidator` (#938, SLV-3, GEN-3): every
## trapped miner sits inside a box the start reaches, so it can be rescued. A
## level with no miners passes. Worked in whole millimetres, like `RobotChecks`,
## so a miner placed on a box face by `MinerPlan` is not failed by a rounding.

const CHECK: String = "miners_reachable"


## The failures, one per miner at most, in miner order. `unreached` holds the
## boxes the start cannot reach.
static func failures(level: LevelDef, start_box: int, unreached: Array[int]) -> Array[String]:
	var found: Array[String] = []
	var boxes: Array[BoxBounds] = level.union.boxes
	for index: int in level.miners.size():
		var miner: Vector3i = level.miners[index]
		var holding: int = -1
		var reached: bool = false
		for box: int in boxes.size():
			if RobotChecks.holds_mm(boxes[box], miner, 0):
				if holding < 0:
					holding = box
				if not unreached.has(box):
					reached = true
					break
		if holding < 0:
			found.append("%s: miner %d at %s is not inside any box"
					% [CHECK, index, Vector3(miner) / float(RobotSpawn.SCALE)])
		elif not reached:
			found.append("%s: miner %d is in box %d, which cannot be reached from start box %d"
					% [CHECK, index, holding, start_box])
	return found
