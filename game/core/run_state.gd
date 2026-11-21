class_name RunState
extends RefCounted

## Where a run stands (RUN-1, RUN-7, #926): which level of its `RunPlan` the
## ship is in, and whether the run is won (escaped the last level) or lost (ship
## destroyed). Nothing in the game uses it yet; a later issue wires a run in.
##
## With a `ShaftOffer`, every level after the first is entered through a shaft
## the player chooses from the offer (RUN-1, CRF-7, #927): after `advance`, the
## run waits in `needs_choice` until `choose`, and the chosen shaft decides the
## level's seed and its risk and reward modifiers.

## The plan this run follows.
var plan: RunPlan
## 0-based index of the current level; after a win, the last level's index.
var level_index: int = 0
## Escaped the last level.
var won: bool = false
## The ship was destroyed; the run is over (RUN-7).
var lost: bool = false
## The shafts offered between levels; null for a run without a choice.
var shafts: ShaftOffer = null
## The shaft chosen into each level, by level index; "" for the first level and
## for levels not reached or not chosen yet.
var chosen: Array[String] = []


func _init(p_plan: RunPlan, p_shafts: ShaftOffer = null) -> void:
	plan = p_plan
	shafts = p_shafts
	chosen.resize(plan.level_count())
	chosen.fill("")


func is_over() -> bool:
	return won or lost


## 1-based depth of the current level.
func current_depth() -> int:
	return plan.depth(level_index)


## Generator seed of the current level: through the chosen shaft once there is
## one, otherwise the plan's seed.
func current_level_seed() -> int:
	var kind: String = current_shaft()
	if kind != "":
		return plan.level_seed_through(level_index, shafts, kind)
	return plan.level_seed(level_index)


## The shaft chosen into the current level; "" for none.
func current_shaft() -> String:
	if level_index >= chosen.size():
		return ""
	return chosen[level_index]


## Robot count and alarm multipliers of the current level's shaft; both 1.0
## without one.
func current_risk() -> Dictionary:
	var kind: String = current_shaft()
	if kind == "":
		return {"robot_count": 1.0, "alarm": 1.0}
	return shafts.risks[kind]


## Component tier 1..3 weights of the current level's shaft; empty without one.
func current_reward() -> Array[float]:
	var kind: String = current_shaft()
	if kind == "":
		return []
	return shafts.rewards[kind]


## The run has escaped into a level it has not yet chosen a shaft for.
func needs_choice() -> bool:
	return shafts != null and not is_over() and level_index > 0 and current_shaft() == ""


## The shafts to choose from now; empty unless `needs_choice`.
func offer() -> Array[String]:
	if not needs_choice():
		return []
	return plan.offer_after(level_index - 1, shafts)


## Takes the shaft `kind` into the current level. Returns false, changing
## nothing, when no choice is due or `kind` is not in the offer.
func choose(kind: String) -> bool:
	if not offer().has(kind):
		return false
	chosen[level_index] = kind
	return true


## Called after the ship escapes the current level: moves to the next level, or
## wins the run after the last one. Returns false, changing nothing, once the
## run is over or while a shaft choice is due.
func advance() -> bool:
	if is_over() or needs_choice():
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
	return hash([plan.plan_hash(), level_index, won, lost, chosen])
