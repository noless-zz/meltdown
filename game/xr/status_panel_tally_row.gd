class_name StatusPanelTallyRow
extends RefCounted

## The status panel's tally rows (#1356): the carried line on top of the
## panel, above the countdown, in the rows' own size, and the banked line above
## it, small and dim like the level row. On top because the rows under the hold
## pass the 30 degree glance limit on preset 1 with two weapon slots; above,
## they stay nearer the eye line than every other row. The words come from
## `StatusPanelTally`.
## The lines never move or blink: a rising count only tints the carried line
## for the look's `tally_flash_seconds` (CMF-3). Presentation only (MP-2).

const NAME: String = "Tally"
const BANKED_NAME: String = "TallyBanked"
## Heights on the panel: one row above the countdown, and the banked line,
## in its smaller font, one row above that.
const Y: float = StatusPanel.MELTDOWN_Y + StatusPanel.ROW_PITCH
const BANKED_Y: float = Y + StatusPanel.ROW_PITCH

## The counts and words the rows show.
var tally: StatusPanelTally
## How many times either line's text was replaced; read by tests only.
var text_changes: int = 0

var _label: Label3D
var _banked: Label3D
var _flash_color: Color


## Adds both lines under `panel`, drawn as `look` says.
func _init(panel: Node3D, look: Dictionary, names: Dictionary[String, String] = {}) -> void:
	tally = StatusPanelTally.new(look, names)
	_flash_color = look["tally_flash_color"]
	_label = StatusPanelLabels.make(panel, NAME, Vector3(StatusPanel.LABEL_X, Y, 0.0), StatusPanel.SMALL_FONT)
	_banked = StatusPanelLabels.make(panel, BANKED_NAME, Vector3(StatusPanel.LABEL_X, BANKED_Y, 0.0),
		int(look["level_font"]))
	_banked.modulate = look["level_color"]
	_refresh()


## Takes this frame's copies (see `StatusPanelTally.update`) and returns the
## message for the hold row, or "". Safe every frame.
func show_counts(collected: Dictionary, rescued: int, run_banked: Dictionary, in_run: bool) -> String:
	var message: String = tally.update(collected, rescued, run_banked, in_run)
	_refresh()
	return message


## Runs the flash down by `delta` seconds; `CombatWiring` calls it each frame.
func advance(delta: float) -> void:
	tally.advance(delta)
	_refresh()


## Whether the carried line shows the flash colour.
func flashing() -> bool:
	return _label.modulate == _flash_color


func _refresh() -> void:
	if StatusPanelLabels.set_text(_label, tally.row_text()):
		text_changes += 1
	if StatusPanelLabels.set_text(_banked, tally.banked_text()):
		text_changes += 1
	_label.modulate = _flash_color if tally.flash_left > 0.0 else StatusPanel.TEXT_COLOR
