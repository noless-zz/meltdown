class_name StatusPanelWeaponRows
extends RefCounted

## The status panel's weapon rows (#1210, SLV-1, CMB-1, PLT-2): one row per
## primary slot, "1 Pulse Cannon" or "2 empty", with a mark before the slot
## that fires. The owner slotted a gun into the empty second slot and could
## not find it on a panel that showed only the firing slot; every slot now has
## its row, so a part shows the moment it is slotted.
##
## How many rows there are comes from the ship's slot list each frame, not a
## constant: a ship with more slots gets more rows, and the panel moves the
## rows below them down (`place_all`). Presentation only: it is
## handed names and an index and writes nothing back (ARC-3, MP-2).

## The first row keeps the name the single weapon row had, so the row list
## (`StatusPanelRowList`) and the corner and order checks still find it.
const FIRST_NAME: String = "Weapon"
## Rows after the first are "Weapon2", "Weapon3", ...
const NAME_FORMAT: String = "Weapon%d"
## The firing slot's row starts with this mark; the others with the same width
## of space, so the slot numbers line up.
const FIRE_MARK: String = "> "
const IDLE_MARK: String = "   "
## Slot number, then the weapon's name or `EMPTY`.
const ROW_FORMAT: String = "%s%d %s"
const EMPTY: String = "empty"
## Slots that do not fire are dimmer than the one that does, so the mark is
## read by brightness too, not only by the small glyph.
const IDLE_COLOR: Color = Color(0.55, 0.62, 0.66)
## Rows under the weapon rows, by how many rows below the last one they sit.
const HOLD_BELOW: int = 1
const SPEED_BELOW: int = 2
const PRESET_BELOW: int = 3

## The labels, slot order; the first exists from the start.
var labels: Array[Label3D] = []
## How many times any row's text was replaced; read by tests only.
var text_changes: int = 0

var _panel: Node3D


## Adds the rows under `panel`, the first at `at`: until the first ship
## arrives, as many empty slots as a new ship has, the first marked, so an
## unwired panel already says what it will show.
func _init(panel: Node3D, at: Vector3) -> void:
	_panel = panel
	labels.append(StatusPanelLabels.make(panel, FIRST_NAME, at, StatusPanel.SMALL_FONT))
	var empty: Array[String] = []
	empty.resize(ShipState.new().primary_slots.size())
	empty.fill("")
	show_slots(empty, 0)


## The row's name for slot `slot` (0-based).
static func node_name(slot: int) -> String:
	return FIRST_NAME if slot == 0 else NAME_FORMAT % (slot + 1)


## What slot `slot`'s row reads for weapon `weapon_name` ("" for empty).
static func row_text(slot: int, weapon_name: String, fires: bool) -> String:
	return ROW_FORMAT % [FIRE_MARK if fires else IDLE_MARK, slot + 1,
		EMPTY if weapon_name.is_empty() else weapon_name]


## Shows one row per entry of `names` (a slot's weapon name, "" when empty)
## with the mark on `selected`. Rows are added when the ship has more slots
## and hidden when it has fewer. Returns whether the number of rows changed,
## so the panel can move the rows below. Safe to call every frame: a label is
## rebuilt only when its text changes.
func show_slots(names: Array[String], selected: int) -> bool:
	var count: int = maxi(names.size(), 1)
	var changed: bool = count != shown_count()
	while labels.size() < count:
		var label: Label3D = StatusPanelLabels.make(_panel, node_name(labels.size()),
			labels[0].position, StatusPanel.SMALL_FONT)
		label.layers = labels[0].layers  # Drawn only if the weapon row is (#1207).
		labels.append(label)
	for slot: int in labels.size():
		labels[slot].visible = slot < count
		if slot >= count:
			continue
		var weapon: String = names[slot] if slot < names.size() else ""
		var fires: bool = slot == selected
		if StatusPanelLabels.set_text(labels[slot], row_text(slot, weapon, fires)):
			text_changes += 1
		labels[slot].modulate = StatusPanel.TEXT_COLOR if fires else IDLE_COLOR
	return changed


## How many rows show.
func shown_count() -> int:
	var count: int = 0
	for label: Label3D in labels:
		if label.visible:
			count += 1
	return count


## Height on the panel of a row `below` rows under the last of `slots` weapon rows.
static func row_below(below: int, slots: int) -> float:
	return StatusPanel.WEAPON_Y - float(maxi(slots, 1) - 1 + below) * StatusPanel.ROW_PITCH


## Puts the weapon rows one under another from `StatusPanel.WEAPON_Y`, and the
## hold, speed, preset and level rows of `panel` under the last shown one.
## Only heights change; x and depth stay.
func place_all(panel: Node3D) -> void:
	var slots: int = shown_count()
	for slot: int in labels.size():
		labels[slot].position.y = StatusPanel.WEAPON_Y - float(slot) * StatusPanel.ROW_PITCH
	var heights: Dictionary = {
		StatusPanel.HOLD_NAME: row_below(HOLD_BELOW, slots),
		StatusPanel.SPEED_NAME: row_below(SPEED_BELOW, slots),
		StatusPanel.BOOST_NAME: row_below(SPEED_BELOW, slots),
		StatusPanel.PRESET_NAME: row_below(PRESET_BELOW, slots),
		StatusPanel.LEVEL_NAME: row_below(PRESET_BELOW, slots),
	}
	for node_name: String in heights:
		(panel.get_node(node_name) as Node3D).position.y = float(heights[node_name])


## Draws every row on `layers`, as the row list gives the first.
func set_layers(layers: int) -> void:
	for label: Label3D in labels:
		label.layers = layers
