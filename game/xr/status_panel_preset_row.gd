class_name StatusPanelPresetRow
extends RefCounted

## The status panel's preset row (#146): "Preset <n> <name>" in the small
## row, shown large for `StatusPanel.PRESET_LARGE_SECONDS` after each change,
## with the build line above the large label while it shows. Split out of
## `StatusPanel` (#747) so the panel stays under 300 lines.
##
## While the active preset has swivel-chair mode on, a short tag from the
## look file follows the name, so a turn from the chair never reads as a
## fault (CMF-7, #792). It is text only: it never moves or animates (CMF-3).

## The large preset label is centred here, above the rows.
const LARGE_Y: float = 0.13
## The build line only needs to be findable, so it costs no row: it shows above
## the large preset label, while that label shows (at start and on each preset
## change), in a smaller font.
const BUILD_Y: float = 0.165

## Seconds the large label has left; 0 when it is hidden.
var seconds_left: float = 0.0
## True while the active preset has swivel-chair mode on; set by `show_swivel`.
var swivel: bool = false
## The tag shown after the name while `swivel` is on, from the look file.
var swivel_text: String = ""

## The preset number last shown; 0 before the first values, so the preset the
## game starts on is also shown large once.
var _shown_preset: int = 0
var _small: Label3D
var _large: Label3D
var _build: Label3D


## Adds the small preset label under `panel`. The large label and the build
## line come from `add_large`, later, so the panel's labels keep their order.
func _init(panel: Node3D, look: Dictionary = StatusPanelLook.shared()) -> void:
	swivel_text = str(look.get("preset_swivel_text", StatusPanelLook.FALLBACK["preset_swivel_text"]))
	_small = StatusPanelLabels.make(panel, StatusPanel.PRESET_NAME,
		Vector3(StatusPanel.LABEL_X, StatusPanel.PRESET_Y, 0.0), StatusPanel.SMALL_FONT)


## Adds the build line, in a smaller font, and the large centred label.
func add_large(panel: Node3D) -> void:
	_build = StatusPanelLabels.make(panel, StatusPanel.BUILD_NAME, Vector3(0.0, BUILD_Y, 0.0),
		StatusPanel.SMALL_FONT * 3 / 4)
	_build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build.visible = false
	_large = StatusPanelLabels.make(panel, StatusPanel.PRESET_LARGE_NAME,
		Vector3(0.0, LARGE_Y, 0.0), StatusPanel.LARGE_FONT)
	_large.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_large.visible = false


## Shows preset `number` named `preset_name` and the build line's text. A
## number different from the last one starts the large label's time.
func show(number: int, preset_name: String, build_text: String) -> void:
	var text: String = text_for(number, preset_name, swivel_text if swivel else "")
	if number != _shown_preset:
		_shown_preset = number
		seconds_left = StatusPanel.PRESET_LARGE_SECONDS
	StatusPanelLabels.set_text(_small, text)
	StatusPanelLabels.set_text(_large, text)
	StatusPanelLabels.set_text(_build, build_text)
	_show_large(seconds_left > 0.0)


## Whether the active preset has swivel-chair mode on. The owner passes the
## preset's own switch, so the tag changes only when the preset does.
func show_swivel(on: bool) -> void:
	swivel = on


## The row's words: "Preset <n> <name>", then `tag` when it is not empty.
static func text_for(number: int, preset_name: String, tag: String) -> String:
	var text: String = "Preset %d %s" % [number, preset_name]
	return text if tag.is_empty() else "%s %s" % [text, tag]


func advance(delta: float) -> void:
	if seconds_left <= 0.0:
		return
	seconds_left = maxf(seconds_left - maxf(delta, 0.0), 0.0)
	_show_large(seconds_left > 0.0)


func large_visible() -> bool:
	return _large.visible


## Large and small never show together, so the preset is not read twice.
## The build line shows with the large label.
func _show_large(large: bool) -> void:
	_large.visible = large
	_small.visible = not large
	_build.visible = large
