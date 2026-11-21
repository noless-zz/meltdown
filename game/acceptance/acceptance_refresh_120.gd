class_name AcceptanceRefresh120
extends RefCounted

## A step's `refresh_120` (#851, PRF-1, PRF-2, CMF-1): fly the step with the
## pilot's 120 Hz option (#838, `RefreshChoice`) on, for that step only. The
## scene's `RefreshRate` is handed a choice made here, never one loaded from or
## saved to user storage, so the pilot's saved choice is neither read for the
## step nor written; when the step ends the choice the scene had before comes
## back and its rate is asked for again.
##
## Where the runtime offers no 120 Hz rate (Monado, the desktop build) the
## step's refresh_rate and frame_budget checks are skipped with the offered
## rates named, never passed (decision record 0005): a 90 Hz pass there says
## nothing about 120.
##
## In a suite: `"preset": 4, "refresh_120": true`, with a refresh_rate or
## frame_budget check.

const KEY: String = "refresh_120"
## Where the step's choice came from, as `RefreshChoice.describe` shows it.
const SOURCE: String = "acceptance step"

## The choice the scene had before the step, put back by `restore`.
var _before: RefreshChoice = null


## Reads `refresh_120` from a step's JSON into `step`; "" or the problem, with
## the field named. Runs after the step's preset and checks are read.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has(KEY):
		return ""
	var where: String = "%s.%s" % [field, KEY]
	if typeof(data[KEY]) != TYPE_BOOL:
		return "%s: must be true or false" % where
	if not step.has_check(AcceptanceStep.CHECK_REFRESH_RATE) and not step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET):
		return "%s: only used by the refresh_rate or frame_budget check, which the step does not list" % where
	if bool(data[KEY]) and step.preset == AcceptanceStep.NO_PRESET:
		return "%s: needs a numbered preset that allows 120 Hz" % where
	step.refresh_120 = data[KEY]
	return ""


## Turns the 120 Hz option on in `main` for `step`, after its preset is set.
## Returns what `restore` needs when the step ends, or null when the step
## does not ask for 120 Hz.
static func apply(main: Node, step: AcceptanceStep) -> AcceptanceRefresh120:
	var rate: RefreshRate = main.get("refresh_rate") as RefreshRate
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	if not step.refresh_120 or rate == null or comfort == null:
		return null
	var held: AcceptanceRefresh120 = AcceptanceRefresh120.new()
	held._before = rate.choice
	var choice: RefreshChoice = RefreshChoice.new()
	choice.on = true
	choice.source = SOURCE
	rate.choice = choice
	rate.apply(comfort.preset)
	return held


## Puts back the choice `main` had before the step and asks for its rate.
func restore(main: Node) -> void:
	var rate: RefreshRate = main.get("refresh_rate") as RefreshRate
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	if rate == null:
		return
	# A scene whose session began during the step never loaded the launch's
	# choice (`RefreshRate.begin` keeps one already set), so load it now.
	rate.choice = _before if _before != null else RefreshChoice.from_launch()
	if comfort != null:
		rate.apply(comfort.preset)


## Whether the runtime offered a 120 Hz rate at the last choice.
static func offered(rate: RefreshRate) -> bool:
	for value: float in rate.offered:
		if absf(value - RefreshChoice.HIGH_HZ) < RefreshRate.SAME_RATE_HZ:
			return true
	return false


## Why a 120 Hz step's check is not judged here, or "" when it can be.
static func not_offered_reason(rate: RefreshRate) -> String:
	return "" if offered(rate) else "the runtime does not offer 120 Hz; offered %s" % [rate.offered]
