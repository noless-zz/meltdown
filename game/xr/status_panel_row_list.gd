class_name StatusPanelRowList
extends RefCounted

## Which of the status panel's rows draw (#1207, ARC-4). The owner asked for
## a panel that keeps only what a pilot needs in a fight; the development
## lines (speed, preset, level, build) moved to the dev menu's Info section
## (`DevMenuInfo`). The list is the `rows` key of the panel's look file, so a
## row can be brought back without code.
##
## A row left out keeps its nodes and keeps taking its values, so the Info
## section can read them as the panel would have shown them; it is only
## never drawn. It is put on no render layer rather than hidden, because the
## rows hide and show themselves (the countdown, the outcome, the large
## preset label) and must not undo the list. Presentation only (ARC-3, CMF-6).

## Each row's name in the look file and the panel nodes it draws.
const NODES: Dictionary = {
	"meltdown": ["Meltdown"],
	"hull": ["HullLabel", "HullBar", "HullTrack"],
	"shield": ["ShieldLabel", "ShieldBar", "ShieldTrack"],
	"energy": ["EnergyLabel", "EnergyBar", "EnergyTrack"],
	"weapon": ["Weapon"],
	"hold": ["Hold"],
	"outcome": ["Outcome"],
	"speed": ["Speed", "Boost"],
	"preset": ["Preset"],
	"preset_large": ["PresetLarge"],
	"build": ["Build"],
	"level": ["Level"],
}
## What a pilot needs in a fight: the panel's rows when the file names none.
const FIGHT: Array[String] = ["meltdown", "hull", "shield", "energy", "weapon", "hold", "outcome"]
## The render layer a drawn row is on: Godot's default, which every camera sees.
const DRAWN_LAYERS: int = 1


## Every row name, in the order `NODES` lists them.
static func names() -> Array[String]:
	var all: Array[String] = []
	for row: String in NODES:
		all.append(row)
	return all


## The `rows` value as row names, or a message naming what is wrong.
static func parse(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return "\"rows\" must be a list of row names"
	var rows: Array[String] = []
	for item: Variant in value:
		if typeof(item) != TYPE_STRING or not NODES.has(item):
			return "\"rows\" has unknown row \"%s\"; rows are %s" % [str(item), ", ".join(names())]
		if rows.has(item):
			return "\"rows\" names \"%s\" twice" % item
		rows.append(item)
	return rows


## Draws the nodes of the rows in `rows` and none of the others under `panel`.
static func apply(panel: Node3D, rows: Array[String]) -> void:
	for row: String in NODES:
		for node_name: String in NODES[row]:
			var node: VisualInstance3D = panel.get_node_or_null(node_name) as VisualInstance3D
			if node != null:
				node.layers = DRAWN_LAYERS if rows.has(row) else 0


## Whether `row` can draw under `panel`: every one of its nodes is on a layer.
## A row may still hide itself, as the countdown does before a meltdown.
static func drawn(panel: Node3D, row: String) -> bool:
	for node_name: String in NODES.get(row, []):
		var node: VisualInstance3D = panel.get_node_or_null(node_name) as VisualInstance3D
		if node == null or node.layers == 0:
			return false
	return NODES.has(row)
