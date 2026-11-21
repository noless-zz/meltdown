class_name StatusPanelLevelRow
extends RefCounted

## The status panel's level row (#747, DEV-6): what this launch flies, "Seed
## 31" for a generated mine, the level's name for a level file, "Test tunnel"
## otherwise, so every recording and screenshot says which mine it shows.
## Small and dim, right-aligned on the preset row, so it never competes with
## hull, shield and energy; it never moves or animates (CMF-3). Words, size
## and colour come from the panel's look file (ARC-4).

## Stands for the seed number in `level_seed_text`.
const SEED_TAG: String = "{seed}"
## Stands for the level's name in `level_file_text`.
const NAME_TAG: String = "{name}"

## How many times the label's text was replaced; read by tests only.
var text_changes: int = 0

var _label: Label3D
var _look: Dictionary
## The values last shown, joined; the tunnel's to start with.
var _shown: String = "/"


## Adds the row's label under `panel`, drawn as `look` says.
func _init(panel: Node3D, look: Dictionary) -> void:
	_look = look
	_label = StatusPanelLabels.make(panel, StatusPanel.LEVEL_NAME,
		Vector3(-StatusPanel.LABEL_X, StatusPanel.PRESET_Y, 0.0), int(look["level_font"]))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.modulate = look["level_color"]
	_label.text = text_for("", "", look)  # The tunnel until told otherwise, never blank.


## Shows the row for seed `level_seed` (digits, "" for none) or else the
## level named `level_name` ("" for none), or else the test tunnel. Safe to
## call every frame: the text is replaced only when a value changes.
func show_level(level_seed: String, level_name: String) -> void:
	var key: String = level_seed + "/" + level_name
	if key == _shown:
		return
	_shown = key
	if StatusPanelLabels.set_text(_label, text_for(level_seed, level_name, _look)):
		text_changes += 1


## The row's words with `look`'s templates.
static func text_for(level_seed: String, level_name: String, look: Dictionary) -> String:
	if level_seed != "":
		return (look["level_seed_text"] as String).replace(SEED_TAG, level_seed)
	if level_name != "":
		return (look["level_file_text"] as String).replace(NAME_TAG, level_name)
	return look["level_tunnel_text"]
