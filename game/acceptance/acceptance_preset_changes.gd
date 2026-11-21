class_name AcceptancePresetChanges
extends RefCounted

## A step's `preset_changes` (#777, CMF-4, CMF-6): comfort presets the runner
## switches to while the replay flies, the way a player changes preset mid-run.
## Each change goes through the scene's own `set_comfort_preset`, as the
## step's starting `preset` does, so the step shows that the simulation does
## not notice (its final hash) and that the view does not swing when the
## preset changes (`comfort_motion`, judged against the preset in force).
##
## In a suite: `"preset_changes": [{"tick": 600, "preset": 1}, ...]`, ticks
## rising, each inside the replay. The change is made when the simulation
## reaches that tick, before the frame that flies it.

const KEY: String = "preset_changes"
const ENTRY_KEYS: Array[String] = ["tick", "preset"]

var _step: AcceptanceStep = null
var _next: int = 0


func _init(p_step: AcceptanceStep) -> void:
	_step = p_step


## The changes of `step`, or null when it lists none.
static func for_step(step: AcceptanceStep) -> AcceptancePresetChanges:
	return AcceptancePresetChanges.new(step) if not step.preset_change_ticks.is_empty() else null


## Makes every change due at `tick` on `main`, and tells `comfort` (may be
## null) so it judges the frames from here on against the new preset.
func apply(main: Node, tick: int, comfort: AcceptanceComfortCheck) -> void:
	while _next < _step.preset_change_ticks.size() and _step.preset_change_ticks[_next] <= tick:
		var number: int = _step.preset_change_presets[_next]
		_next += 1
		main.call("set_comfort_preset", number)
		if comfort != null:
			var wiring: ComfortWiring = main.get("comfort") as ComfortWiring
			comfort.change_preset(number, wiring.preset if wiring != null else null)


## Reads `preset_changes` from a step's JSON into `step`; "" or the problem,
## with the field named. The replay is read to check that every tick is flown:
## a change after the last tick would never be made and the step would pass
## without it.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has(KEY):
		return ""
	var where: String = "%s.%s" % [field, KEY]
	if typeof(data[KEY]) != TYPE_ARRAY or (data[KEY] as Array).is_empty():
		return "%s: must be a list of at least one {\"tick\", \"preset\"}" % where
	if step.replay_path == "":
		return "%s: only used with a replay, which the step does not list" % where
	var entries: Array = data[KEY]
	for index: int in entries.size():
		var problem: String = _parse_entry(entries[index], "%s[%d]" % [where, index], step)
		if problem != "":
			return problem
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return "%s: cannot read the replay to check the ticks: %s" % [where, replay.error]
	var last: int = step.preset_change_ticks[step.preset_change_ticks.size() - 1]
	if last >= replay.frames.size():
		return "%s: tick %d is past the replay, which flies ticks 0..%d" % [where, last, replay.frames.size() - 1]
	return ""


static func _parse_entry(raw: Variant, field: String, step: AcceptanceStep) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "%s: must be a JSON object with tick and preset" % field
	var entry: Dictionary = raw
	for key: Variant in entry:
		if typeof(key) != TYPE_STRING or not ENTRY_KEYS.has(key):
			return "%s.%s: unknown key" % [field, str(key)]
	for key: String in ENTRY_KEYS:
		if not entry.has(key) or not AcceptanceSuite._is_whole(entry[key]):
			return "%s.%s: must be a whole number" % [field, key]
	var tick: int = int(entry["tick"])
	var number: int = int(entry["preset"])
	if number < AcceptanceStep.MIN_PRESET or number > AcceptanceStep.MAX_PRESET:
		return "%s.preset: %d is outside %d..%d" % [field, number, AcceptanceStep.MIN_PRESET, AcceptanceStep.MAX_PRESET]
	if tick < 0:
		return "%s.tick: must be 0 or more" % field
	if not step.preset_change_ticks.is_empty() and tick <= step.preset_change_ticks[step.preset_change_ticks.size() - 1]:
		return "%s.tick: %d does not come after the change before it" % [field, tick]
	step.preset_change_ticks.append(tick)
	step.preset_change_presets.append(number)
	return ""
