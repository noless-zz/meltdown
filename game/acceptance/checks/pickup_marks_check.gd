extends RefCounted

## The `pickup_marks_shown` acceptance check (#1375, CRF-1, SLV-3, CMF-3,
## DEV-6), lane-b's file. In `suites/m6/effects.json` the `pickup_marks` step
## flies m4's `crew_joins` flight (as m6 `pickup_look` does), which takes cell
## salts heaps and rescues a miner. After the flight it reads the main scene's
## component and miner views and passes when:
##
## - every heap the ship took left a mark, each where that heap was drawn,
##   each drawn on some frame, and none drawn past its look's fade time;
## - every rescued miner started boarding where its marker was drawn, on the
##   frame of its `MINER_RESCUED`, and none was drawn past its leave time;
## - nothing is still drawn once the flight has ended.
##
## The step pins `crew_joins`'s hash, so drawing them changes no simulation
## state (MP-2). The step lists `crew_joins` too, which flies the level with
## drops and rescue on; it moves the scene on, so this read-only check is
## listed before it.

const CHECK: String = "pickup_marks_shown"
## A mark or boarding miner may start one frame from where it was drawn.
const PLACE_TOLERANCE_M: float = 0.01


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var combat: CombatWiring = runner.main.get("combat") as CombatWiring
	var session: LocalSession = runner.main.get("session") as LocalSession
	if combat == null or combat.component_view == null or session == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no component view or session"]
	var marks: PickupMarks = combat.component_view.marks
	var leave: MinerLeave = combat.miner_view.leave
	measurements["pickup_marks_started"] = marks.started_count
	measurements["pickup_marks_drawn"] = marks.drawn_count
	measurements["pickup_marks_longest_s"] = snappedf(marks.longest_drawn_seconds, 0.001)
	measurements["miner_leaves_started"] = leave.started_count
	measurements["miner_leave_longest_s"] = snappedf(leave.longest_drawn_seconds, 0.001)
	return judge(marks, leave, components_taken(session.sim), RunWiring.rescued_in(session.sim))


## Components the flight took, by count. A heap holds at least one, so the
## local ship took at most this many heaps.
static func components_taken(sim: Sim) -> int:
	var taken: int = 0
	for kind: Variant in sim.collected:
		taken += int(sim.collected[kind])
	return taken


## [result, why] for the views after a flight that took up to `collected`
## components and rescued `rescued` miners.
static func judge(marks: PickupMarks, leave: MinerLeave, collected: int, rescued: int) -> Array:
	if collected < 1 or rescued < 1:
		return [AcceptanceReport.RESULT_FAIL, "the flight must take components and rescue a miner; it took %d and rescued %d"
			% [collected, rescued]]
	if marks.started_count < 1 or marks.started_count > collected:
		return [AcceptanceReport.RESULT_FAIL, "%d marks for %d components taken" % [marks.started_count, collected]]
	if marks.drawn_count != marks.started_count:
		return [AcceptanceReport.RESULT_FAIL, "%d of %d marks were ever drawn" % [marks.drawn_count, marks.started_count]]
	if marks.largest_offset_m > PLACE_TOLERANCE_M:
		return [AcceptanceReport.RESULT_FAIL, "a mark started %.3f m from its heap" % marks.largest_offset_m]
	var fade: float = marks.look()["fade_seconds"]
	if marks.longest_drawn_seconds >= fade:
		return [AcceptanceReport.RESULT_FAIL, "a mark was drawn %.3f s after it started; it fades in %.2f s"
			% [marks.longest_drawn_seconds, fade]]
	if leave.started_count != rescued:
		return [AcceptanceReport.RESULT_FAIL, "%d miners boarded for %d rescued" % [leave.started_count, rescued]]
	if leave.largest_offset_m > PLACE_TOLERANCE_M:
		return [AcceptanceReport.RESULT_FAIL, "a miner boarded from %.3f m off its marker" % leave.largest_offset_m]
	var seconds: float = leave.look()["seconds"]
	if leave.longest_drawn_seconds >= seconds or leave.longest_drawn_seconds <= 0.0:
		return [AcceptanceReport.RESULT_FAIL, "a boarding miner was drawn for %.3f s; it takes %.2f s"
			% [leave.longest_drawn_seconds, seconds]]
	if marks.shown_count() != 0 or leave.shown_count() != 0:
		return [AcceptanceReport.RESULT_FAIL, "%d marks and %d boarding miners still drawn at the end"
			% [marks.shown_count(), leave.shown_count()]]
	return [AcceptanceReport.RESULT_PASS, "%d marks at their heaps, gone within %.2f s; %d miners boarded over %.2f s"
		% [marks.started_count, fade, leave.started_count, seconds]]
