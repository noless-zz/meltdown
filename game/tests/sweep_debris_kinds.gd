extends RefCounted

## The seed sweep's meltdown debris counted by kind (#887, GEN-3, RUN-4), so the
## nightly line and gate G3 show what each kind adds and how often
## `DebrisRouteGuard` holds it. `seed_sweep.gd` keeps the totals; this file
## splits them.
##
## The kind is read from the entry, which is where `DebrisPlan` already tells
## its sections apart: its rocks are spheres, `DebrisDoors` adds boxes, and
## `DebrisFires` adds entries with fire damage. Nothing new is stored in `core/`
## or the replay, so no state or level hash moves.

## Every kind the summary line prints, in this order. A kind a level's plan does
## not place still prints 0, so a new kind needs only its name here and a rule
## in `kind_of`.
const KINDS: Array[String] = ["rocks", "doors", "fires"]
## The keys each kind's count holds.
const PLACED: String = "placed"
const HELD: String = "held"


## The kind of `debris`'s entry `index`, one of `KINDS`.
static func kind_of(debris: MeltdownDebris, index: int) -> String:
	if debris.is_fire(index):
		return "fires"
	if debris.is_box(index):
		return "doors"
	return "rocks"


## Every kind with nothing placed and nothing held.
static func empty() -> Dictionary:
	var by_kind: Dictionary = {}
	for kind: String in KINDS:
		by_kind[kind] = {PLACED: 0, HELD: 0}
	return by_kind


## Adds one level's `debris` to `by_kind`. `held_flags` holds, per entry, whether
## the guard held it back; an entry past its end was not held.
static func add(by_kind: Dictionary, debris: MeltdownDebris, held_flags: Array[bool]) -> void:
	for index: int in debris.size():
		var counts: Dictionary = by_kind[kind_of(debris, index)]
		counts[PLACED] += 1
		if index < held_flags.size() and held_flags[index]:
			counts[HELD] += 1


## The summary line's part for `by_kind`, as ", rocks 3, rocks_held 1, doors 0,
## doors_held 0, ...": two words a field, as the fields before it, so the
## nightly job and anything splitting the line on ", " read it the same way.
static func summary_part(by_kind: Dictionary) -> String:
	var part: String = ""
	for kind: String in KINDS:
		var counts: Dictionary = by_kind.get(kind, {})
		part += ", %s %d, %s_held %d" % [kind, counts.get(PLACED, 0), kind, counts.get(HELD, 0)]
	return part
