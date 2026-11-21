extends RefCounted

## The seed sweep counts meltdown debris placed and held by kind (#887, GEN-3,
## RUN-4): rocks, doors and fires each get a placed and a held count that sum to
## the totals, a kind the plan does not place prints 0, and the summary line
## keeps every field the nightly job reads.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DebrisKinds := preload("res://tests/sweep_debris_kinds.gd")
const SEEDS: int = 50


## The per-kind counts in `result` summed: [placed, held].
func _sums(result: Dictionary) -> Array[int]:
	var sums: Array[int] = [0, 0]
	for kind: String in DebrisKinds.KINDS:
		sums[0] += result["debris_by_kind"][kind][DebrisKinds.PLACED]
		sums[1] += result["debris_by_kind"][kind][DebrisKinds.HELD]
	return sums


## The summary line's two-word fields before the by-check part, by name.
func _fields(line: String) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for part: String in line.get_slice(";", 0).split(", "):
		var words: PackedStringArray = part.split(" ")
		if words.size() == 2 and words[1].is_valid_int():
			counts[words[0]] = words[1].to_int()
	return counts


## `debris.json` without its `doors` section, as `SeedLevel.load_inputs` takes
## an override.
func _no_doors() -> Dictionary:
	var parsed: Variant = JSON.parse_string(SeedLevel.read_text(SeedLevel.DEBRIS_FILE))
	var data: Dictionary = parsed
	data.erase(DebrisPlan.DOORS_KEY)
	return {SeedLevel.DEBRIS_FILE: JSON.stringify(data)}


func test_kind_is_read_from_the_entry() -> String:
	var debris: MeltdownDebris = MeltdownDebris.new()
	for index: int in 3:
		debris.positions_mm.append(Vector3i.ZERO)
		debris.after_ticks.append(1)
	debris.radii_mm.append_array([1000, 0, 2000])
	debris.sizes_mm.append_array([Vector3i.ZERO, Vector3i(4000, 4000, 500)])
	debris.fire_milli_dps.append_array([0, 0, 5000])
	var kinds: Array[String] = []
	for index: int in debris.size():
		kinds.append(DebrisKinds.kind_of(debris, index))
	return "" if kinds == ["rocks", "doors", "fires"] else "kinds read as %s" % [kinds]


func test_seeds_0_to_49_per_kind_sums_equal_the_totals() -> String:
	var result: Dictionary = SeedSweep.run(0, SEEDS)
	var sums: Array[int] = _sums(result)
	if sums != [result["debris"], result["debris_held"]]:
		return "kinds sum to %s, totals %d placed and %d held" % [sums, result["debris"],
				result["debris_held"]]
	for kind: String in ["rocks", "doors"]:
		if result["debris_by_kind"][kind][DebrisKinds.PLACED] == 0:
			return "no %s on seeds 0..%d: the sums prove little" % [kind, SEEDS - 1]
	var fields: Dictionary[String, int] = _fields(SeedSweep.summary(result))
	for kind: String in DebrisKinds.KINDS:
		var counts: Dictionary = result["debris_by_kind"][kind]
		if fields.get(kind, -1) != counts[DebrisKinds.PLACED] \
				or fields.get(kind + "_held", -1) != counts[DebrisKinds.HELD]:
			return "%s reads %s from \"%s\"" % [kind, counts, SeedSweep.summary(result)]
	return ""


func test_a_plan_with_no_doors_prints_doors_0() -> String:
	var result: Dictionary = SeedSweep.run(0, SEEDS, SeedSweep.MODULE_COUNT,
			SeedSweep.KEPT_FAILURES, _no_doors())
	if result["debris"] == 0:
		return "no debris placed without doors: %s" % SeedSweep.summary(result)
	var line: String = SeedSweep.summary(result)
	if not line.contains(", doors 0, doors_held 0, "):
		return "doors not 0: \"%s\"" % line
	return "" if _sums(result) == [result["debris"], result["debris_held"]] \
			else "kinds sum to %s without doors: \"%s\"" % [_sums(result), line]


func test_a_kind_with_nothing_placed_prints_0() -> String:
	var part: String = DebrisKinds.summary_part(DebrisKinds.empty())
	var expected: String = ", rocks 0, rocks_held 0, doors 0, doors_held 0, fires 0, fires_held 0"
	return "" if part == expected else "got \"%s\"" % part


## The nightly job greps for the prefix, and the totals and the by-check part
## stay where they were, so the per-kind fields only add.
func test_the_old_fields_stay_put() -> String:
	var by_kind: Dictionary = DebrisKinds.empty()
	by_kind["rocks"] = {DebrisKinds.PLACED: 5, DebrisKinds.HELD: 2}
	by_kind["fires"] = {DebrisKinds.PLACED: 2, DebrisKinds.HELD: 0}
	var line: String = SeedSweep.summary({"seeds": 3, "passed": 2, "failed": 1, "short": 0,
			"ms": 12, "debris": 7, "debris_held": 2, "debris_by_kind": by_kind,
			"by_check": {"reactor": 0, "debris_route": 1}})
	var expected: String = "level validator: 3 seeds, 2 passed, 1 failed, 0 stopped short, 12 ms," \
			+ " debris 7, debris_held 2, rocks 5, rocks_held 2, doors 0, doors_held 0," \
			+ " fires 2, fires_held 0; failing seeds by check: reactor 0, debris_route 1"
	return "" if line == expected else "got \"%s\"" % line
