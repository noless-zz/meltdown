extends RefCounted

## The `tally_counts` acceptance check (#1356, CRF-1, SLV-3, PLT-2, DEV-6): on
## a run step whose flight picks up components and rescues a miner, the status
## panel's tally must have confirmed each pickup and each rescue on the hold
## row as it happened, and at the end show what the simulation holds: this
## level's components by kind and the miners aboard. It reads the scene's
## panel and session after the flight and changes nothing, so it may sit
## beside the moving checks (listed before them).

const CHECK: String = "tally_counts"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var panel: StatusPanel = runner.main.get("status_panel") as StatusPanel
	var session: LocalSession = runner.main.get("session") as LocalSession
	if panel == null or session == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no status panel or session"]
	var tally: StatusPanelTally = panel.tally_row.tally
	measurements["tally"] = String(panel.texts().get(StatusPanelTallyRow.NAME, ""))
	measurements["tally_collected_confirmations"] = tally.collected_confirmations
	measurements["tally_miner_confirmations"] = tally.miner_confirmations
	return judge(tally, measurements["tally"], session.sim.collected, RunWiring.rescued_in(session.sim))


## [result, why] for `tally` and the carried line `shown`, against the sim's
## final `collected` counts and `rescued` miners.
static func judge(tally: StatusPanelTally, shown: String, collected: Dictionary, rescued: int) -> Array:
	var counts: Dictionary[String, int] = StatusPanelTally.counts_of(collected)
	if counts.is_empty() or rescued < 1:
		return [AcceptanceReport.RESULT_FAIL, "the flight must pick up components and rescue a miner; it took %s and rescued %d"
			% [counts, rescued]]
	if tally.carried != counts or tally.miners != rescued:
		return [AcceptanceReport.RESULT_FAIL, "the tally counts %s and %d miners; the sim holds %s and %d"
			% [tally.carried, tally.miners, counts, rescued]]
	if shown != tally.row_text():
		return [AcceptanceReport.RESULT_FAIL, "the panel shows \"%s\", not \"%s\"" % [shown, tally.row_text()]]
	if tally.collected_confirmations < 1:
		return [AcceptanceReport.RESULT_FAIL, "no pickup was confirmed on the panel"]
	if tally.miner_confirmations != rescued:
		return [AcceptanceReport.RESULT_FAIL, "%d rescues confirmed for %d miners aboard"
			% [tally.miner_confirmations, rescued]]
	return [AcceptanceReport.RESULT_PASS, "\"%s\"; %d pickups and %d rescues confirmed"
		% [shown, tally.collected_confirmations, tally.miner_confirmations]]
