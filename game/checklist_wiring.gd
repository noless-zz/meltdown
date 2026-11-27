class_name ChecklistWiring
extends RefCounted

## The in-headset test checklist (#1325, DEV-6, DEV-7): the owner works
## through a gate's checks without taking the headset off. Development builds
## only: a release build attaches nothing, so the dev menu never offers it.
##
## The dev menu's Test checklist entry (`DevMenuChecklist`) opens the page on
## the step to do next. While open it takes the controls as the dev menu does
## (decision record 0009): the right stick moves between steps and choices,
## A confirms, B and Y step the remark, and the ship gets idle input with the
## solo session paused under its own reason. A mark is saved at once with the
## build commit, the time, the comfort preset and the level or seed flying
## (`ChecklistStore`), so a killed app keeps it and a PC script can pull it.
##
## A step's action is turned into the dev menu's own choice and applied
## through `DevMenuWiring.apply`, so setting a preset or flying a seed takes
## exactly the menu's path, fade included (ARC-3, CMF-8); the page then pins
## itself small so the pilot sees what changed and flies on. Pinned, it shows
## the next step and takes no input; the menu entry opens it again. Nothing
## here writes simulation state (MP-2). It sits beside `main.gd` because it
## joins the `meta/` checklist to the `xr/` page, the dev menu and the hub.
##
## At the home base the dev menu ignores the tap (decision record 0009), so a
## tap there opens the pinned page instead, and pins an open one (#1408); with
## no page pinned it still does nothing. The open page pauses the session the
## hub waits on, which keeps the stations from the stick and the aim. A
## `station` action takes the station into use with the stick's own presses
## (`HubStationSelect`); away from the base it does nothing and says so.

const LOG_PREFIX: String = "Meltdown: checklist"
## The solo session's pause reason while the page is open (`LocalSession.set_paused`).
const PAUSE_REASON: String = "checklist"

## Whether this build may show the checklist; tests set it.
var available: bool = OS.is_debug_build()
var checklist: Checklist = null
var session: ChecklistSession = null
var model: ChecklistPageModel = null
var page: ChecklistPage = null
var store: ChecklistStore = ChecklistStore.new()
## The build's commit, written with every result.
var commit: String = BuildInfo.UNKNOWN
## Applies a dev menu choice (`DevMenuWiring.apply`); tests inject one.
var apply_choice: Callable = Callable()
## Why the last save failed, or "".
var save_error: String = ""
## What the page used when it closed, kept from the ship until released (#1206).
var release: DevMenuRelease = DevMenuRelease.new()
## The hub, whose stations a `station` action uses; null in tests without one.
var hub: HubWiring = null

var _dev_menu: DevMenuWiring = null
var _comfort: ComfortWiring = null
var _level_start: LevelStart = null
var _session_of: Callable = Callable()


## The checklist a build shows: the last file in name order under `Checklist.DIR`, or "".
static func default_path() -> String:
	var found: Array[String] = Checklist.files()
	return found[-1] if not found.is_empty() else ""


## Loads the checklist at `path` (`default_path()` when ""), takes back any
## saved marks, hangs the page under `rig` and offers it in `dev_menu`.
## Nothing happens in a release build or for a rejected file. `session_of`
## returns the session flying now, which the open page pauses.
func attach(rig: Node3D, dev_menu: DevMenuWiring, comfort: ComfortWiring, level_start: LevelStart,
		session_of: Callable = Callable(), p_commit: String = BuildInfo.UNKNOWN, path: String = "",
		p_hub: HubWiring = null) -> void:
	if page != null or not available:
		return
	var file: String = path if path != "" else default_path()
	var read: Checklist = Checklist.load_file(file) if file != "" else null
	if read == null or not read.is_valid():
		push_warning("%s not offered; %s: %s" % [LOG_PREFIX, file, read.error if read != null else "no file"])
		return
	checklist = read
	session = ChecklistSession.new(checklist)
	var restored: int = store.load_into(session)
	print("%s %s: %d steps, %d already marked" % [LOG_PREFIX, checklist.id, checklist.steps.size(), restored])
	model = ChecklistPageModel.new(session)
	page = ChecklistPage.new()
	if rig != null:
		rig.add_child(page)
	_dev_menu = dev_menu
	_comfort = comfort
	_level_start = level_start
	_session_of = session_of
	commit = p_commit
	hub = p_hub
	if dev_menu != null:
		if not apply_choice.is_valid():
			apply_choice = dev_menu.apply
		var entry: DevMenuChecklist = dev_menu.entry_for(DevMenuSpec.KIND_CHECKLIST) as DevMenuChecklist
		if entry != null:
			entry.open_page = open


func is_open() -> bool:
	return page != null and page.visible and not page.pinned


func is_pinned() -> bool:
	return page != null and page.visible and page.pinned


## True while the hub is open: the pilot sits in the home base.
func at_base() -> bool:
	return hub != null and hub.is_open()


## Shows the whole page on the step to do next, in front of the head.
func open() -> void:
	if page == null:
		return
	model.open()
	page.show_full(model.page_lines(), _head())


## Shrinks the page to the next step's line.
func pin() -> void:
	if page != null:
		page.show_pinned(model.pinned_line(), _head())


func close() -> void:
	if page != null:
		page.hide_page()


## Once per frame, after the dev menu, with the values it passed on. Returns
## them while the page is not open, idle but for the menu button while it is.
func read(values: Dictionary) -> Dictionary:
	if page == null:
		return values
	if _dev_menu != null and _dev_menu.ignored_tap and at_base():
		if is_pinned():
			open()
		elif is_open():
			pin()
	if is_open() and _dev_menu != null and _dev_menu.is_open():
		pin()  # A tap opened the menu over the page; the page makes way.
	var was_open: bool = is_open()
	if was_open:
		act(model.press(DevMenuWiring.actions(values)))
		if is_open():
			page.refresh(model.page_lines())
	_pause(is_open())
	if not is_open() and not was_open:
		return release.filter(values)
	if not is_open():
		release.hold(values)  # A still down from Close or Pin is not the afterburner.
	return DevMenuWiring.neutral(values)


## Acts on a result of `ChecklistPageModel.press`.
func act(result: String) -> void:
	if result.begins_with(ChecklistPageModel.MARK_PREFIX):
		mark(result.substr(ChecklistPageModel.MARK_PREFIX.length()))
	elif result == ChecklistPageModel.DO:
		do_action(model.current_step())
	elif result == ChecklistPageModel.PIN:
		pin()
	elif result == ChecklistPageModel.CLOSE:
		close()


## Marks the step shown with `p_mark` and the page's remark, saves the
## results and shows the next step. Returns why it was refused, or "".
func mark(p_mark: String) -> String:
	var problem: String = session.mark(model.step, p_mark, model.remark, context(),
		Time.get_datetime_string_from_system(true) + "Z")
	if problem == "":
		var step_id: String = checklist.steps[model.step].id
		save_error = store.save(session, commit)
		print("%s %s %s%s" % [LOG_PREFIX, step_id, p_mark, "; not saved: " + save_error if save_error != "" else ""])
		model.show_step(session.current)
	return problem


## Takes `step`'s action through the dev menu's own choice, or a station
## through the stick's presses, then pins the page.
func do_action(step: ChecklistStep) -> void:
	if step.action == ChecklistStep.ACTION_STATION:
		do_station(step)
		return
	var choice: String = menu_choice(step)
	if choice == "":
		return
	print("%s %s does %s" % [LOG_PREFIX, step.id, choice])
	pin()
	if apply_choice.is_valid():
		apply_choice.call(choice)


## Pins the page and takes `step`'s station into use; away from the base,
## or with no stations, leaves the page open saying so.
func do_station(step: ChecklistStep) -> void:
	if not at_base() or hub.stations == null:
		model.notice = "Only at the home base: %s" % step.action_text()
		print("%s %s: not at the base" % [LOG_PREFIX, step.id])
		return
	print("%s %s does station:%s" % [LOG_PREFIX, step.id, step.action_value])
	pin()
	HubStationSelect.select(hub.stations, step.action_value)


## The dev menu result that takes `step`'s action, or "" for none.
static func menu_choice(step: ChecklistStep) -> String:
	match step.action:
		ChecklistStep.ACTION_COMFORT:
			return DevMenuModel.COMFORT_PREFIX + step.action_value
		ChecklistStep.ACTION_SEED:
			return DevMenuModel.LEVEL_PREFIX + LevelSwitch.SEED_PREFIX + step.action_value
		ChecklistStep.ACTION_LEVEL:
			return DevMenuModel.LEVEL_PREFIX + step.action_value
		ChecklistStep.ACTION_TUNNEL:
			return DevMenuModel.LEVEL_PREFIX
	return ""


## What the game is doing now, saved with a mark: the comfort preset and the
## level source (a seed as `seed:<n>`, a level file, or "" for the tunnel).
func context() -> Dictionary:
	return {
		"preset": _comfort.number if _comfort != null else 0,
		"source": _level_start.source if _level_start != null else "",
	}


func _head() -> Transform3D:
	return _dev_menu.head() if _dev_menu != null else DevMenu.DEFAULT_HEAD


func _pause(held: bool) -> void:
	var flying: LocalSession = _session_of.call() as LocalSession if _session_of.is_valid() else null
	if flying != null and flying.paused_by(PAUSE_REASON) != held:
		flying.set_paused(PAUSE_REASON, held)
