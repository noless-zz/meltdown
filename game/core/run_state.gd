class_name RunState
extends RefCounted

## Where a run stands (RUN-1, RUN-7, #926): which level of its `RunPlan` the
## ship is in, and whether the run is won (escaped the last level) or lost (ship
## destroyed). Nothing in the game uses it yet; a later issue wires a run in.

## The plan this run follows.
var plan: RunPlan
## 0-based index of the current level; after a win, the last level's index.
var level_index: int = 0
## Escaped the last level.
var won: bool = false
## The ship was destroyed; the run is over (RUN-7).
var lost: bool = false


func _init(p_plan: RunPlan) -> void:
	plan = p_plan


func is_over() -> bool:
	return won or lost


## 1-based depth of the current level.
func current_depth() -> int:
	return plan.depth(level_index)


## Generator seed of the current level.
func current_level_seed() -> int:
	return plan.level_seed(level_index)


## Called after the ship escapes the current level: moves to the next level, or
## wins the run after the last one. Returns false, changing nothing, once the
## run is over.
func advance() -> bool:
	if is_over():
		return false
	if level_index + 1 >= plan.level_count():
		won = true
	else:
		level_index += 1
	return true


## Called when the ship is destroyed: the run ends lost (RUN-7). Returns false,
## changing nothing, once the run is over.
func lose() -> bool:
	if is_over():
		return false
	lost = true
	return true


func state_hash() -> int:
	return hash([plan.plan_hash(), level_index, won, lost])
