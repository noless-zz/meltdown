class_name StatusPanelTally
extends RefCounted

## What this level's flight carries, counted where the pilot can see it
## (#1356, CRF-1, CRF-2, SLV-3, PLT-2). The owner's G4 notes: "No indication
## of pick up or how many I have in hold", and a rescued miner was "gone but
## no notice". So the panel's tally row says which components this level has
## picked up, by kind, and how many miners are aboard; a second, quieter line
## says what the run has banked from earlier escapes. When a count rises, the
## hold row says so for a moment ("+2 Cell Salts", "Miner aboard") and the
## tally row shows the flash colour briefly.
##
## Like `HoldMessages`, it tells what happened from two frames of plain copies
## (the sim's `collected` counts, its rescued count and the run's banked
## counts), never from the simulation's own objects, so it writes nothing
## back (MP-2) and a frame split for a snap loses no pickup. Words and the
## flash come from the panel's look file (ARC-4).

const ITEMS_TAG: String = "{items}"
const MINERS_TAG: String = "{miners}"
const COUNT_TAG: String = "{count}"
const NAME_TAG: String = "{name}"
const COMPONENTS_DIR: String = "res://data/components"

## Components picked up on this level, by kind id, none at zero.
var carried: Dictionary[String, int] = {}
## Miners aboard from this level.
var miners: int = 0
## Components the run has banked, by kind id; empty outside a run.
var banked: Dictionary[String, int] = {}
## Whether the last frame flew a run, which has a banked line.
var in_run: bool = false
## How many component rises and rescued miners were confirmed; acceptance and
## tests read them.
var collected_confirmations: int = 0
var miner_confirmations: int = 0
## Seconds the flash colour has left; 0 when the row shows its own colour.
var flash_left: float = 0.0

var _look: Dictionary
var _names: Dictionary[String, String]
var _primed: bool = false


## `look` is the panel's look; `names` maps a component id to the name shown.
func _init(look: Dictionary, names: Dictionary[String, String] = {}) -> void:
	_look = look
	_names = names


## The shipped component kinds' names by id, or none when the folder is rejected.
static func shipped_names(dir: String = COMPONENTS_DIR) -> Dictionary[String, String]:
	var texts: Dictionary = {}
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			if file.ends_with(".json"):
				texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	var names: Dictionary[String, String] = {}
	var kinds: ComponentList = ComponentList.parse(texts)
	if kinds.error == "":
		for kind: ComponentDef in kinds.kinds:
			names[kind.id] = kind.display_name
	return names


## Takes this frame's copies: `collected` (component id to count, picked up on
## the level flown), `rescued` miners and, in a run, `run_banked`. Returns the
## message for what rose since the last call, or "". A rescue outranks a
## pickup, as the rarer moment. The first call only remembers, and a count
## that fell (a new level) says nothing.
func update(collected: Dictionary, rescued: int, run_banked: Dictionary, p_in_run: bool) -> String:
	var fresh: Dictionary[String, int] = counts_of(collected)
	var message: String = ""
	if _primed:
		for kind: String in sorted_ids(fresh):
			var rise: int = fresh[kind] - carried.get(kind, 0)
			if rise > 0:
				collected_confirmations += 1
				if message == "":
					message = (_look["tally_collected_text"] as String).replace(COUNT_TAG, str(rise)) \
						.replace(NAME_TAG, name_of(kind))
		if rescued > miners:
			miner_confirmations += rescued - miners
			message = _look["tally_miner_text"]
	if message != "":
		flash_left = float(_look["tally_flash_seconds"])
	_primed = true
	carried = fresh
	miners = maxi(rescued, 0)
	banked = counts_of(run_banked)
	in_run = p_in_run
	return message


## Runs the flash down by `delta` seconds.
func advance(delta: float) -> void:
	flash_left = maxf(flash_left - maxf(delta, 0.0), 0.0)


## The carried line, as the look's `tally_text` words it.
func row_text() -> String:
	return (_look["tally_text"] as String).replace(ITEMS_TAG, items_text(carried)) \
		.replace(MINERS_TAG, str(miners))


## The banked line; "" outside a run, so nothing is drawn there.
func banked_text() -> String:
	if not in_run:
		return ""
	return (_look["tally_banked_text"] as String).replace(ITEMS_TAG, items_text(banked))


## "3 Cell Salts, 1 Core Glass" in id order, or the look's `tally_none_text`.
func items_text(counts: Dictionary[String, int]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for kind: String in sorted_ids(counts):
		parts.append("%d %s" % [counts[kind], name_of(kind)])
	return _look["tally_none_text"] if parts.is_empty() else ", ".join(parts)


## The kind's shown name; its id when the kinds folder does not name it.
func name_of(kind: String) -> String:
	return _names.get(kind, kind)


## `counts` as typed counts above zero.
static func counts_of(counts: Dictionary) -> Dictionary[String, int]:
	var typed: Dictionary[String, int] = {}
	for kind: Variant in counts:
		if int(counts[kind]) > 0:
			typed[str(kind)] = int(counts[kind])
	return typed


static func sorted_ids(counts: Dictionary[String, int]) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(counts.keys())
	ids.sort()
	return ids
