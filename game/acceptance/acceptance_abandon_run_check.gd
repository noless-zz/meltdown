class_name AcceptanceAbandonRunCheck
extends RefCounted

## The `abandon_run` check of a run step (#1246, RUN-1, RUN-7, CRF-2, DEV-7,
## decision record 0005). In a suite:
##
##     {"id": "abandon_run", "run": 12345, "replay": "res://...",
##      "checks": ["final_hash", "outcome", "no_script_errors", "abandon_run"],
##      "expected_banked": {"cell_salts": 1}}
##
## The step flies its run's first level with component drops on, as the
## components_bank check does. After the replay escapes, the check presses on
## as the escape screen's restart does, which banks the level and flies level
## 2; a suspended-run save is left in a scratch store, as the shaft panel's
## suspend row leaves one. On level 2 it makes the call the menu's "Return to
## base" row makes on its black frame (`RunAbandon.abandon`) and judges the
## profile: still exactly `expected_banked`, one lost run more, the save gone,
## the hub open and the new run's first level loaded behind it. The confirm
## step and the fade are the unit tests' (`test_return_to_base.gd`); the feel
## of it is the headset's. Like run_advances it swaps the scene's session, so
## it is the step's last check; it closes the hub it opened.

const SCRATCH_PATH: String = "user://acceptance_abandon_run.json"


## [result, message]; `measurements` gets the banked counts and statistics.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	var result: Array = _run(step, main, flown, measurements)
	RunSaveStore.new(SCRATCH_PATH).discard()
	var hub: HubWiring = main.get("hub") as HubWiring
	if hub != null:
		hub.close()
	return result


static func _run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or destroyed == null or hub == null or not RunAbandon.flying_run(level_start):
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var ended: LocalSession = main.get("session")
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's level ended %s, not escaped" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome())]
	var run: RunWiring = level_start.run
	main.call("restart_level")
	if run.error != "" or not RunAbandon.flying_run(level_start) or run.state.level_index != 1:
		return [AcceptanceReport.RESULT_FAIL, "the escape did not move the run to level 2: '%s'" % run.error]
	run.saves = RunSaveStore.new(SCRATCH_PATH)
	if not run.saves.save(_suspended(step.run_seed)):
		return [AcceptanceReport.RESULT_FAIL, "the scratch save was not written: %s" % run.saves.message]
	var played: RunState = run.state
	var lost: int = run.profile.stats.runs_lost
	if not RunAbandon.abandon(level_start, hub, destroyed, Callable(main, "restart_level")):
		return [AcceptanceReport.RESULT_FAIL, "the menu row's call did not abandon the run"]
	var banked: Dictionary[String, int] = run.profile.banked
	measurements["banked"] = JSON.stringify(banked, "", true)
	measurements["stats"] = JSON.stringify(run.profile.stats.to_dict(), "", true)
	measurements["next_level_source"] = level_start.source
	if banked != step.expected_banked:
		return [AcceptanceReport.RESULT_FAIL, "banked %s after abandoning, expected %s" % [measurements["banked"],
			JSON.stringify(step.expected_banked, "", true)]]
	if run.profile.stats.runs_lost != lost + 1 or run.ended != played or not played.lost:
		return [AcceptanceReport.RESULT_FAIL, "the abandoned run is not counted as lost: %s" % measurements["stats"]]
	if run.saves.has_save():
		return [AcceptanceReport.RESULT_FAIL, "the suspended-run save is still there"]
	if not hub.is_open() or not run.active() or run.state.level_index != 0 \
			or level_start.source != run.level_source():
		return [AcceptanceReport.RESULT_FAIL, "the hub is not open on a new run's first level (%s)" %
			level_start.source]
	return [AcceptanceReport.RESULT_PASS, "abandoned on level 2: banked %s kept, the loss counted, hub open" %
		measurements["banked"]]


## A save as the shaft panel's suspend row leaves one for run `run_seed`.
static func _suspended(run_seed: int) -> RunSave:
	var save: RunSave = RunSave.new()
	save.run_seed = run_seed
	save.next_level = 2
	save.ship = "default_ship"
	save.loadout = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}
	return save
