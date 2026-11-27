extends RefCounted

## Suspending a run at the shaft choice and resuming it (#1107, RUN-8, RUN-7,
## CRF-2, ARC-2): run 12345 suspended after level 1 into a scratch store and
## resumed by a fresh run wiring flies the same level 2 as the uninterrupted
## run; a save killed before its rename leaves the earlier save (or none)
## whole; a save is taken once only; quitting at the choice or losing the ship
## leaves no save; the shaft panel offers the suspend row only with a store.

const RUN_SEED: int = 12345
const OTHER_SEED: int = 4242
const SAVE_PATH: String = "user://t1107_run.json"
const LOADOUT: Dictionary = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}


func _clean() -> void:
	for each: String in [SAVE_PATH, SafeFileWrite.temp_path(SAVE_PATH)]:
		if FileAccess.file_exists(each):
			DirAccess.remove_absolute(each)


## A run with the shipped run and shaft files and an in-memory profile; with
## `saving`, a scratch save store.
func _run(run_seed: int = RUN_SEED, saving: bool = true) -> RunWiring:
	var run: RunWiring = RunWiring.new(run_seed, null, func() -> int: return OTHER_SEED)
	if saving:
		run.saves = RunSaveStore.new(SAVE_PATH)
	return run


## A run of `RUN_SEED` suspended at the choice after its first level.
func _suspended() -> RunWiring:
	_clean()
	var run: RunWiring = _run()
	run.escape_for_choice({}, 0)
	run.suspend()
	return run


## Level 2's source when level 1 is escaped and no shaft is chosen: the first
## offered one is taken, as the restart without a choice takes it.
func _uninterrupted_level_two() -> String:
	var run: RunWiring = _run(RUN_SEED, false)
	run.escape_for_choice({}, 0)
	return run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 0)


func test_suspend_then_resume_flies_the_uninterrupted_level_two() -> String:
	var run: RunWiring = _suspended()
	if run.active() or not run.suspended or not run.saves.has_save():
		_clean()
		return "after suspending: active %s, suspended %s, saved %s, error '%s'" % [run.active(),
			run.suspended, run.saves.has_save(), run.error]
	var fresh: RunWiring = _run(OTHER_SEED)
	var saved: RunSave = fresh.saves.take()
	var resumed: bool = saved != null and fresh.resume(saved)
	_clean()
	if not resumed:
		return "the fresh run did not resume: '%s'" % fresh.error
	var want: String = _uninterrupted_level_two()
	if fresh.state.plan.run_seed != RUN_SEED or fresh.state.current_depth() != 2:
		return "resumed run %d on depth %d" % [fresh.state.plan.run_seed, fresh.state.current_depth()]
	if fresh.level_source() != want:
		return "resumed level 2 flies %s, the uninterrupted run %s" % [fresh.level_source(), want]
	var flown: LevelDef = LevelSwitch.load_level(fresh.level_source())
	var plain: LevelDef = LevelSwitch.load_level(want)
	if flown == null or plain == null or flown.box_modules != plain.box_modules:
		return "the resumed level's module plan differs from the uninterrupted run's"
	return ""


func test_a_save_killed_before_its_rename_leaves_the_earlier_one() -> String:
	_suspended()
	var killed: RunSaveStore = RunSaveStore.new(SAVE_PATH)
	killed.stop_before_rename = true
	var later: RunSave = RunResume.to_save(_advanced_twice(), "default_ship", LOADOUT)
	killed.save(later)
	var waiting: RunSave = HubOpening.waiting_save(killed)
	_clean()
	if later.error != "":
		return "the later save was refused: %s" % later.error
	if waiting == null or waiting.run_seed != RUN_SEED or waiting.next_level != 2:
		return "the hub would offer %s, expected run %d level 2" % [
			"nothing" if waiting == null else "run %d level %d" % [waiting.run_seed, waiting.next_level], RUN_SEED]
	return ""


func test_a_first_save_killed_before_its_rename_offers_none() -> String:
	_clean()
	var killed: RunSaveStore = RunSaveStore.new(SAVE_PATH)
	killed.stop_before_rename = true
	killed.save(RunResume.to_save(_advanced_twice(), "default_ship", LOADOUT))
	var waiting: RunSave = HubOpening.waiting_save(killed)
	var has: bool = killed.has_save()
	_clean()
	return "" if waiting == null and not has else "a killed first save is offered"


func test_a_resumed_run_cannot_be_resumed_again() -> String:
	var run: RunWiring = _suspended()
	var first: RunSave = run.saves.take()
	var second: RunSave = run.saves.take()
	var waiting: RunSave = HubOpening.waiting_save(run.saves)
	_clean()
	if first == null:
		return "the save was not taken: %s" % run.saves.message
	return "" if second == null and waiting == null else "the save was handed out twice"


func test_quitting_at_the_choice_or_losing_leaves_no_save() -> String:
	_clean()
	var run: RunWiring = _run()
	run.escape_for_choice({}, 0)
	if run.saves.has_save():
		_clean()
		return "the shaft choice wrote a save before suspend was chosen"
	run.choose(run.state.offer()[0])
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 0)
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, {}, 0)
	var has: bool = run.saves.has_save()
	_clean()
	return "" if not has else "a lost ship left a save"


func test_suspend_is_refused_away_from_the_choice() -> String:
	_clean()
	var run: RunWiring = _run()
	var refused: bool = not run.suspend()
	var has: bool = run.saves.has_save()
	var still: bool = run.active()
	_clean()
	if not refused or has or not still:
		return "suspending in level 1: refused %s, saved %s, still flying %s" % [refused, has, still]
	var unsaved: RunWiring = _run(RUN_SEED, false)
	unsaved.escape_for_choice({}, 0)
	return "" if not unsaved.suspend() and unsaved.active() else "a run without a store suspended"


func test_the_shaft_panel_offers_suspend_only_with_a_store() -> String:
	_clean()
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	var plain: RunWiring = _run(RUN_SEED, false)
	choice.open(plain, {})
	if choice.model.kinds != plain.state.offer():
		return "without a store the panel lists %s" % [choice.model.kinds]
	var run: RunWiring = _run()
	choice.open(run, {})
	var last: int = choice.model.kinds.size() - 1
	if choice.model.kinds[last] != RunSuspend.ROW_KIND or choice.model.labels[last] != "Suspend run":
		return "the last row is %s '%s'" % [choice.model.kinds[last], choice.model.labels[last]]
	choice.model.highlight = last
	choice.set("_actions", {DevMenuModel.CONFIRM: false})
	choice.update(run, false, Transform3D.IDENTITY, false)
	choice.set("_actions", {DevMenuModel.CONFIRM: true})
	var answered: bool = choice.update(run, false, Transform3D.IDENTITY, false)
	var has: bool = run.saves.has_save()
	_clean()
	if not answered or choice.is_open() or not run.suspended or not has:
		return "confirming suspend: answered %s, open %s, suspended %s, saved %s" % [answered,
			choice.is_open(), run.suspended, has]
	return ""


func test_the_suspend_words_come_from_data() -> String:
	var shipped: Dictionary = RunSuspend.words()
	if shipped != RunSuspend.FALLBACK:
		return "the shipped words %s differ from the built-in ones" % shipped
	var mine: Dictionary = RunSuspend.words("{\"row_text\": \"Park it\", \"detail_text\": \"later\"}")
	if mine["row_text"] != "Park it":
		return "the row reads '%s'" % mine["row_text"]
	return "" if RunSuspend.words("{\"row_text\": \"\"}") == RunSuspend.FALLBACK else "a rejected file was used"


## Run 12345 standing at depth 3 with its choices taken, so its save differs from level 2's.
func _advanced_twice() -> RunState:
	var state: RunState = RunState.new(RunPlan.build(RUN_SEED, FileAccess.get_file_as_string(RunWiring.RUN_FILE)),
		ShaftOffer.build(FileAccess.get_file_as_string(RunWiring.SHAFTS_FILE)))
	for i: int in 2:
		state.advance({})
		state.choose(state.offer()[0])
	return state
