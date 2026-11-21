class_name DevMenuBreak
extends DevMenuEntry

## The dev menu's Break reminder entry (#821, CMF-10). Split from
## `DevMenuWiring` (#892).
##
## A choice goes through `BreakPromptWiring.set_enabled`, which saves it in
## `BreakChoice` and hides a showing prompt; the entry opens on the reminder's
## state, so a launch switch shows. Only the view's prompt changes, never the
## simulation (CMF-6).

## The break prompt the entry shows and switches; null in tests without one.
var break_prompt: BreakPromptWiring = null


func _init(p_break_prompt: BreakPromptWiring) -> void:
	super([DevMenuSpec.KIND_BREAK], [DevMenuModel.BREAK_PREFIX])
	break_prompt = p_break_prompt


## Whether the entry opens on On: the reminder's own state.
func shown() -> bool:
	return break_prompt == null or break_prompt.reminder == null or break_prompt.reminder.is_enabled()


func choose(result: String) -> void:
	if break_prompt != null:
		break_prompt.set_enabled(result == DevMenuModel.BREAK_PREFIX + DevMenuModel.BREAK_ON)
