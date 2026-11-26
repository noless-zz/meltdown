extends RefCounted

## The `end_screen_lists` acceptance check (#1376, CRF-2, RUN-7, SLV-3, PLT-2,
## DEV-6): on a run step whose flight picks up components, rescues a miner and
## escapes, the escape screen must list what the level banks, by kind, and the
## miners brought out, worded from the sim's final counts; and the prompt a
## press that ends the run shows must say "return to base", while this level,
## which does not end the run, keeps its own prompt. It reads the scene's end
## screens and session and changes nothing, so it sits before the moving
## `crew_joins` check.

const CHECK: String = "end_screen_lists"
## The criterion's words; the look file may say more around them.
const BASE_WORDS: String = "return to base"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var wiring: DestroyedWiring = runner.main.get("destroyed") as DestroyedWiring
	var session: LocalSession = runner.main.get("session") as LocalSession
	if wiring == null or session == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no end screens or session"]
	var end: EscapeEndWiring = wiring.escape
	if not end.sequence.line_shown():
		return [AcceptanceReport.RESULT_FAIL, "the escape screen is not shown"]
	var shown: String = end.screen.lists_text() if end.screen != null else end.lists_shown
	var base: String = end.lists.base_prompt(true)
	measurements["end_screen_lists"] = shown
	measurements["end_screen_base_prompt"] = base
	return judge(end.lists, shown, session.sim.collected, RunWiring.rescued_in(session.sim), base,
		wiring.ends_run(session), end.screen.prompt_text() if end.screen != null else "")


## [result, why] for the escape screen's `shown` lists against the sim's final
## `collected` counts and `rescued` miners, the `base` prompt, whether the
## press `ends_run`, and the escape screen's `prompt` ("" without a screen node).
static func judge(lists: EndScreenLists, shown: String, collected: Dictionary, rescued: int, base: String,
		ends_run: bool, prompt: String) -> Array:
	if StatusPanelTally.counts_of(collected).is_empty() or rescued < 1:
		return [AcceptanceReport.RESULT_FAIL, "the flight must pick up components and rescue a miner; it took %s and rescued %d"
			% [collected, rescued]]
	var expected: String = lists.escape_text(collected, rescued)
	if shown != expected:
		return [AcceptanceReport.RESULT_FAIL, "the escape screen lists \"%s\", not \"%s\"" % [shown, expected]]
	if lists.items(collected) == lists.look["none_text"] or not shown.contains(str(rescued)):
		return [AcceptanceReport.RESULT_FAIL, "the lists \"%s\" leave out the banked components or the miners" % shown]
	if not base.contains(BASE_WORDS):
		return [AcceptanceReport.RESULT_FAIL, "the end-of-run prompt reads \"%s\", not \"%s\"" % [base, BASE_WORDS]]
	if prompt != "" and (prompt == base) != ends_run:
		return [AcceptanceReport.RESULT_FAIL, "the escape prompt reads \"%s\" though the press %s the run"
			% [prompt, "ends" if ends_run else "does not end"]]
	return [AcceptanceReport.RESULT_PASS, "\"%s\"; at a run's end \"%s\"" % [shown.replace("\n", " / "), base]]
