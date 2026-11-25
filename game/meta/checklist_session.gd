class_name ChecklistSession
extends RefCounted

## The marks made on one checklist in the headset (#1325, DEV-6): per step
## pass, fail or skip, an optional canned remark, and what the game was doing
## when it was marked (the comfort preset and the level or seed flying), with
## the time. `results()` is what `ChecklistStore` saves for a PC script to pull;
## `restore` takes a saved one back, so a killed app keeps its marks. No nodes,
## and nothing here reads or writes the simulation (ARC-3).

const PASS: String = "pass"
const FAIL: String = "fail"
const SKIP: String = "skip"
const MARKS: Array[String] = [PASS, FAIL, SKIP]
## Bumped when the results file changes shape, so the PC script can tell.
const FORMAT: int = 1

var checklist: Checklist
## Each marked step's record by step id: mark, remark, time, preset, source.
var marks: Dictionary[String, Dictionary] = {}
## The step to show next: the first unmarked one after the last marked, or the last step.
var current: int = 0
## When the first mark was made, as an ISO time; "" before.
var started: String = ""
## When the latest mark was made, as an ISO time; "" before.
var updated: String = ""


func _init(p_checklist: Checklist) -> void:
	checklist = p_checklist


## Marks step `index` with `mark` (one of `MARKS`) and `remark` ("" for none),
## with `context` (`preset` and `source`) and the ISO `time`. Moves `current`
## on. Returns why it was refused, or "".
func mark(index: int, p_mark: String, remark: String, context: Dictionary, time: String) -> String:
	if index < 0 or index >= checklist.steps.size():
		return "no step %d" % index
	if not MARKS.has(p_mark):
		return "unknown mark \"%s\"" % p_mark
	var step: ChecklistStep = checklist.steps[index]
	if remark != "" and not step.remarks.has(remark):
		return "step %s offers no remark \"%s\"" % [step.id, remark]
	marks[step.id] = {
		"mark": p_mark,
		"remark": remark,
		"time": time,
		"preset": int(context.get("preset", 0)),
		"source": str(context.get("source", "")),
	}
	if started == "":
		started = time
	updated = time
	current = next_unmarked(index)
	return ""


## The mark on step `index`, or "" while unmarked.
func mark_of(index: int) -> String:
	var record: Dictionary = marks.get(checklist.steps[index].id, {})
	return str(record.get("mark", ""))


## The remark on step `index`, or "".
func remark_of(index: int) -> String:
	var record: Dictionary = marks.get(checklist.steps[index].id, {})
	return str(record.get("remark", ""))


## The first unmarked step after `index`, wrapping; the step after `index`
## (the last one at most) when every step is marked.
func next_unmarked(index: int) -> int:
	var count: int = checklist.steps.size()
	for offset: int in range(1, count + 1):
		var at: int = (index + offset) % count
		if not marks.has(checklist.steps[at].id):
			return at
	return mini(index + 1, count - 1)


## How many steps carry each mark, and how many are still open.
func counts() -> Dictionary:
	var tally: Dictionary = {PASS: 0, FAIL: 0, SKIP: 0, "open": 0}
	for step: ChecklistStep in checklist.steps:
		var record: Dictionary = marks.get(step.id, {})
		var key: String = str(record.get("mark", "open"))
		tally[key] = int(tally[key]) + 1
	return tally


## The results file's contents: the checklist, the build `commit`, and every
## step in order with its mark or null.
func results(commit: String) -> Dictionary:
	var listed: Array[Dictionary] = []
	for step: ChecklistStep in checklist.steps:
		var entry: Dictionary = {"id": step.id, "part": checklist.parts[step.part], "do": step.do_text}
		var record: Dictionary = marks.get(step.id, {})
		entry["mark"] = record["mark"] if not record.is_empty() else null
		for key: String in ["remark", "time", "preset", "source"]:
			if not record.is_empty():
				entry[key] = record[key]
		listed.append(entry)
	return {
		"format": FORMAT,
		"checklist": checklist.id,
		"title": checklist.title,
		"issue": checklist.issue,
		"build": commit,
		"started": started,
		"updated": updated,
		"counts": counts(),
		"steps": listed,
	}


## Takes back the marks in `saved` (a `results` dictionary) for steps this
## checklist still has; a file from another checklist is ignored. Returns how
## many marks came back.
func restore(saved: Dictionary) -> int:
	if str(saved.get("checklist", "")) != checklist.id or typeof(saved.get("steps")) != TYPE_ARRAY:
		return 0
	var taken: int = 0
	var last: int = -1
	for item: Variant in saved["steps"]:
		if typeof(item) != TYPE_DICTIONARY or not MARKS.has(str((item as Dictionary).get("mark"))):
			continue
		var entry: Dictionary = item
		var step: ChecklistStep = checklist.step(str(entry.get("id", "")))
		if step == null:
			continue
		var remark: String = str(entry.get("remark", ""))
		marks[step.id] = {
			"mark": str(entry["mark"]),
			"remark": remark if step.remarks.has(remark) else "",
			"time": str(entry.get("time", "")),
			"preset": int(entry.get("preset", 0)),
			"source": str(entry.get("source", "")),
		}
		last = maxi(last, checklist.steps.find(step))
		taken += 1
	started = str(saved.get("started", ""))
	updated = str(saved.get("updated", ""))
	current = next_unmarked(last) if last >= 0 else 0
	return taken
