class_name DevMenuChecklist
extends DevMenuEntry

## The dev menu's Test checklist entry (#1325, DEV-6): choosing it closes the
## menu and opens the checklist page (`ChecklistWiring.open`). The row shows
## only once a checklist is attached, which a release build never does, so a
## player's menu never offers it. One of `DevMenuWiring`'s entry helpers.

## Opens the page; unset (a release build, or no valid checklist file), the row hides.
var open_page: Callable = Callable()


func _init() -> void:
	super([DevMenuSpec.KIND_CHECKLIST], [DevMenuModel.CHECKLIST], true)


func show_on(model: DevMenuModel) -> void:
	model.checklist_shown = open_page.is_valid()


func choose(_result: String) -> void:
	if open_page.is_valid():
		open_page.call()
