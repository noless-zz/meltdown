class_name DevMenuWalk
extends RefCounted

## Test helper (#1301): highlights a menu entry by pressing through the menu as
## the pilot would, out of the section shown with its Back row, into the
## entry's section with its section row, then down to the entry. With no
## sections in the spec it only presses down, as the tests did before.

## More presses than any shipped list needs; a walk past it has lost its way.
const MAX_PRESSES: int = 64
const FRAME: float = 1.0 / 72.0
## Seconds from one press to the next in `select_wired`.
const PRESS_GAP: float = 0.1
## The right stick pushes that step the highlight and the value.
const STICK: Dictionary = {DevMenuModel.UP: Vector2(0.0, 1.0), DevMenuModel.DOWN: Vector2(0.0, -1.0),
	DevMenuModel.LEFT: Vector2(-1.0, 0.0), DevMenuModel.RIGHT: Vector2(1.0, 0.0)}


## Presses `action` once on `model`: down for a frame, then up.
static func tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


## Highlights entry `kind`, pressing each action through `press` (an action
## name in, anything out); without one it taps `model` directly. Returns
## whether the entry is highlighted.
static func select(model: DevMenuModel, kind: String, press: Callable = Callable()) -> bool:
	var act: Callable = press if press.is_valid() else func(action: String) -> void: tap(model, action)
	var target: int = -1
	for index: int in model.spec.entries.size():
		if str(model.spec.entries[index]["kind"]) == kind:
			target = index
	if target == -1:
		return false
	var section: int = section_of_kind(model.spec, kind)
	if model.rows.section != DevMenuRows.TOP and model.rows.section != section:
		if not _press_until(act, DevMenuModel.UP, func() -> bool: return model.selected == DevMenuRows.BACK):
			return false
		act.call(DevMenuModel.CONFIRM)
	if section != -1 and model.rows.section != section:
		var opener: int = DevMenuRows.section_row(section)
		if not _press_until(act, DevMenuModel.DOWN, func() -> bool: return model.selected == opener):
			return false
		act.call(DevMenuModel.CONFIRM)
	return _press_until(act, DevMenuModel.DOWN, func() -> bool: return model.selected == target)


## Highlights `kind` on the open menu of `wiring` with the right stick and A,
## each press a frame held and then released, `PRESS_GAP` apart from `at`.
## Returns the clock after the last press.
static func select_wired(wiring: DevMenuWiring, kind: String, at: float) -> float:
	var clock: Array[float] = [at]
	select(wiring.menu.model, kind, func(action: String) -> void:
		clock[0] = press_wired(wiring, action, clock[0]))
	return clock[0]


## Presses menu `action` once through `wiring` at `at`; returns the next press's time.
static func press_wired(wiring: DevMenuWiring, action: String, at: float) -> float:
	wiring.read(controls(action), at)
	wiring.read(controls(""), at + FRAME)
	return at + PRESS_GAP


## Idle controller values with menu `action` held: a stick push, or A to confirm.
static func controls(action: String) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = {"right_button_lower": true} if action == DevMenuModel.CONFIRM else {}
	if STICK.has(action):
		values["right_stick"] = STICK[action]
	return values


## The words entry `kind`'s row shows when highlighted, without the "> " mark,
## wherever the menu is: its label, the value between `<` and `>` and any note.
static func entry_line(model: DevMenuModel, kind: String) -> String:
	for index: int in model.spec.entries.size():
		if str(model.spec.entries[index]["kind"]) == kind:
			return DevMenu.row_text(model, index, true)
	return ""


## Back to the top list from a section by its Back row; nothing on the top list.
static func to_top(model: DevMenuModel, press: Callable = Callable()) -> bool:
	var act: Callable = press if press.is_valid() else func(action: String) -> void: tap(model, action)
	if model.rows.section == DevMenuRows.TOP:
		return true
	if not _press_until(act, DevMenuModel.UP, func() -> bool: return model.selected == DevMenuRows.BACK):
		return false
	act.call(DevMenuModel.CONFIRM)
	return model.rows.section == DevMenuRows.TOP


## The index in `spec.sections` of the section holding `kind`, or -1 for the top list.
static func section_of_kind(spec: DevMenuSpec, kind: String) -> int:
	for index: int in spec.sections.size():
		if (spec.sections[index]["kinds"] as Array).has(kind):
			return index
	return -1


static func _press_until(act: Callable, action: String, done: Callable) -> bool:
	for step: int in MAX_PRESSES:
		if bool(done.call()):
			return true
		act.call(action)
	return bool(done.call())
