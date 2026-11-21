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
##
## Components picked up on a level are carried until the ship escapes it, when
## `advance` hands them over to be banked into the profile, or until the ship is
## lost, when they are gone (CRF-2, RUN-7, #977). What an earlier escape banked
## is never taken back.

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
## Components picked up on the current level and not banked yet, by kind id.
var carried: Dictionary[String, int] = {}
## Components this run has handed over for banking, summed over escaped levels.
var banked: Dictionary[String, int] = {}
## The known component kinds; null leaves kind ids unchecked.
var components: ComponentList = null
## Why the last `carry` or `advance` refused; empty after one that worked.
var error: String = ""


func _init(p_plan: RunPlan, p_shafts: ShaftOffer = null, p_components: ComponentList = null) -> void:
	plan = p_plan
	shafts = p_shafts
	components = p_components
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


## Replaces what the ship carries on the current level with `collected` (the
## sim's `collected` counts). Returns "" or the reason it refused, changing
## nothing: the run is over, or a count is malformed or names an unknown kind.
func carry(collected: Dictionary) -> String:
	if is_over():
		return _refuse("the run is over")
	var problem: String = _check_counts(collected)
	if problem != "":
		return _refuse(problem)
	carried = _positive(collected)
	error = ""
	return ""


## Called after the ship escapes the current level with `collected` picked up on
## it: moves to the next level, or wins the run after the last one. Returns the
## counts to bank (the carry, which is then empty); an empty `collected` banks
## what `carry` last set. Refuses, changing nothing, once the run is over, while
## a shaft choice is due, or for counts `carry` would refuse: it then returns
## an empty dictionary with `error` set.
func advance(collected: Dictionary = {}) -> Dictionary[String, int]:
	var none: Dictionary[String, int] = {}
	if is_over():
		_refuse("the run is over")
		return none
	if needs_choice():
		_refuse("a shaft choice is due")
		return none
	var problem: String = _check_counts(collected)
	if problem != "":
		_refuse(problem)
		return none
	var to_bank: Dictionary[String, int] = _positive(collected) if not collected.is_empty() else carried.duplicate()
	for id: String in to_bank:
		banked[id] = banked.get(id, 0) + to_bank[id]
	carried = {}
	if level_index + 1 >= plan.level_count():
		won = true
	else:
		level_index += 1
	error = ""
	return to_bank


## True between levels, when a run may be suspended (#949): it has escaped at
## least once, is not over, and carries nothing, so a save loses no component.
func can_suspend() -> bool:
	return not is_over() and level_index > 0 and carried.is_empty()


## The shafts chosen so far, in order from the one into depth 2, for a save
## (RUN-8, #1029). It stops at the first level without a choice: the current
## level while its choice is due, or every level of a run resumed from a save
## that kept no choices, which then stays a run without recorded choices.
func chosen_so_far() -> Array[String]:
	var kinds: Array[String] = []
	for index: int in range(1, mini(level_index + 1, chosen.size())):
		if chosen[index] == "":
			break
		kinds.append(chosen[index])
	return kinds


## A run rebuilt from a save (RUN-8, #1029): it stands at depth `next_level`
## with `p_chosen` as the shafts into depths 2, 3, ... in order, so its current
## level, seed, shaft, risk and reward equal those of a run that got there by
## `advance` and `choose`. `p_chosen` holds either one shaft per level before
## the current one (its choice still due) or one more (chosen into it); an
## empty list is a run without recorded choices. Nothing carried or banked is
## restored: a save is only made with nothing carried, and what was banked is
## already in the profile. A refusal returns a state at the first level with
## `error` naming the reason.
static func resumed(p_plan: RunPlan, p_shafts: ShaftOffer, p_components: ComponentList,
		next_level: int, p_chosen: Array[String]) -> RunState:
	var state: RunState = RunState.new(p_plan, p_shafts, p_components)
	var count: int = p_plan.level_count()
	if next_level < 1 or next_level > count:
		state.error = "next level %d is outside the plan's levels 1 to %d" % [next_level, count]
		return state
	var index: int = next_level - 1
	if not p_chosen.is_empty():
		if p_shafts == null:
			state.error = "%d shafts were chosen in a run without a shaft offer" % p_chosen.size()
			return state
		if p_chosen.size() != index and p_chosen.size() != index - 1:
			state.error = "%d shafts chosen do not fit depth %d: it takes %d, or %d before its choice" % [
				p_chosen.size(), next_level, index, index - 1]
			return state
	for i: int in p_chosen.size():
		var offered: Array[String] = p_plan.offer_after(i, p_shafts)
		if not offered.has(p_chosen[i]):
			state.error = "shaft \"%s\" into depth %d was not in the offer %s" % [p_chosen[i], i + 2, offered]
			return state
	for i: int in p_chosen.size():
		state.chosen[i + 1] = p_chosen[i]
	state.level_index = index
	return state


## Called when the ship is destroyed: the run ends lost and the current level's
## carry is dropped; nothing is banked, and what earlier escapes banked stays
## (RUN-7). Returns false, changing nothing, once the run is over.
func lose() -> bool:
	if is_over():
		return false
	carried = {}
	lost = true
	return true


## A run that never carried a component hashes exactly as before components were
## added, so existing pinned hashes stand.
func state_hash() -> int:
	var parts: Array = [plan.plan_hash(), level_index, won, lost, chosen]
	if not carried.is_empty() or not banked.is_empty():
		parts.append(_sorted_pairs(carried))
		parts.append(_sorted_pairs(banked))
	return hash(parts)


func _refuse(reason: String) -> String:
	error = reason
	return reason


## Empty when every key is a known kind id and every count a whole number of
## zero or more; otherwise names the first bad entry.
func _check_counts(counts: Dictionary) -> String:
	var ids: Array = counts.keys()
	ids.sort()
	for id: Variant in ids:
		if typeof(id) != TYPE_STRING or String(id).is_empty():
			return "component id %s must be a non-empty string" % var_to_str(id)
		if components != null and not components.has_kind(id):
			return "unknown component id \"%s\"" % id
		if typeof(counts[id]) != TYPE_INT or int(counts[id]) < 0:
			return "count of \"%s\" must be a whole number of 0 or more" % id
	return ""


static func _positive(counts: Dictionary) -> Dictionary[String, int]:
	var kept: Dictionary[String, int] = {}
	for id: Variant in counts:
		if int(counts[id]) > 0:
			kept[String(id)] = int(counts[id])
	return kept


## Insertion order must not change the hash.
static func _sorted_pairs(counts: Dictionary[String, int]) -> Array:
	var ids: Array[String] = []
	ids.assign(counts.keys())
	ids.sort()
	var pairs: Array = []
	for id: String in ids:
		pairs.append([id, counts[id]])
	return pairs
